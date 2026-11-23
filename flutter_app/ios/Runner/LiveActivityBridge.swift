// Flutter ↔ Live Activity 연결 (MethodChannel "snapback/live_activity").
// 앱 하단 분석 진행 바와 같은 내용을 잠금화면 · 알림 센터 · 다이내믹 아일랜드에 띄운다.
import ActivityKit
import Flutter
import UIKit

final class LiveActivityBridge {
  static let shared = LiveActivityBridge()

  /// 현재 Live Activity (iOS 16.1+ 에서만 Activity 타입이라 Any 로 보관)
  private var activity: Any?
  private var last: [String: Any] = [:]
  private var bgTask: UIBackgroundTaskIdentifier = .invalid

  func register(messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "snapback/live_activity", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "update":
        self.last = args
        self.apply(args, interrupted: false)
        result(nil)
      case "end":
        self.last = [:]
        self.finish(args)
        result(nil)
      case "cancel":
        // 분석 취소 → 잠금화면에서 바로 내림
        self.last = [:]
        if #available(iOS 16.1, *), let act = self.activity as? Activity<AnalysisActivityAttributes> {
          self.activity = nil
          Task { await act.end(dismissalPolicy: .immediate) }
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    // 지난 실행에서 남은 활동 정리
    if #available(iOS 16.1, *) {
      Task {
        for a in Activity<AnalysisActivityAttributes>.activities {
          await a.end(dismissalPolicy: .immediate)
        }
      }
    }
    let nc = NotificationCenter.default
    nc.addObserver(self, selector: #selector(didEnterBackground),
                   name: UIApplication.didEnterBackgroundNotification, object: nil)
    nc.addObserver(self, selector: #selector(willEnterForeground),
                   name: UIApplication.willEnterForegroundNotification, object: nil)
  }

  private func state(_ a: [String: Any], interrupted: Bool) -> Any? {
    guard #available(iOS 16.1, *) else { return nil }
    return AnalysisActivityAttributes.ContentState(
      done: a["done"] as? Int ?? 0,
      total: a["total"] as? Int ?? 0,
      paused: a["paused"] as? Bool ?? false,
      finished: a["finished"] as? Bool ?? false,
      interrupted: interrupted
    )
  }

  private func apply(_ a: [String: Any], interrupted: Bool, completion: (() -> Void)? = nil) {
    guard #available(iOS 16.1, *),
          let s = state(a, interrupted: interrupted) as? AnalysisActivityAttributes.ContentState
    else { completion?(); return }
    if let act = activity as? Activity<AnalysisActivityAttributes>, act.activityState == .active {
      Task {
        if #available(iOS 16.2, *) {
          await act.update(ActivityContent(state: s, staleDate: nil))
        } else {
          await act.update(using: s)
        }
        completion?()
      }
      return
    }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { completion?(); return }
    do {
      if #available(iOS 16.2, *) {
        activity = try Activity.request(
          attributes: AnalysisActivityAttributes(),
          content: ActivityContent(state: s, staleDate: nil))
      } else {
        activity = try Activity.request(
          attributes: AnalysisActivityAttributes(), contentState: s)
      }
    } catch {
      NSLog("Live Activity 시작 실패: \(error)")
    }
    completion?()
  }

  /// 분석 완료: '분석 완료' 상태로 바꾸고 15분 뒤 잠금화면에서 사라지게 한다.
  private func finish(_ a: [String: Any]) {
    guard #available(iOS 16.1, *),
          let act = activity as? Activity<AnalysisActivityAttributes>,
          let s = state(a, interrupted: false) as? AnalysisActivityAttributes.ContentState
    else { return }
    activity = nil
    let policy = ActivityUIDismissalPolicy.after(Date().addingTimeInterval(15 * 60))
    Task {
      if #available(iOS 16.2, *) {
        await act.end(ActivityContent(state: s, staleDate: nil), dismissalPolicy: policy)
      } else {
        await act.end(using: s, dismissalPolicy: policy)
      }
    }
  }

  /// 백그라운드로 가면 iOS 가 허락하는 동안(보통 약 30초) 분석을 이어 가고,
  /// 시간이 다 되면 '잠시 멈춤 · 앱을 열면 이어서 분석해요'로 바꿔 둔다.
  @objc private func didEnterBackground() {
    guard activity != nil, !last.isEmpty,
          (last["finished"] as? Bool) != true, (last["paused"] as? Bool) != true
    else { return }
    let app = UIApplication.shared
    bgTask = app.beginBackgroundTask(withName: "snapback.analysis") { [weak self] in
      guard let self else { return }
      self.apply(self.last, interrupted: true) {
        DispatchQueue.main.async { self.endBackgroundTask() }
      }
    }
  }

  @objc private func willEnterForeground() {
    endBackgroundTask()
    if activity != nil, !last.isEmpty { apply(last, interrupted: false) }
  }

  private func endBackgroundTask() {
    guard bgTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(bgTask)
    bgTask = .invalid
  }
}

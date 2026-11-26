import BackgroundTasks
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 충전 중 장기 백그라운드 분석 작업은 앱 실행이 끝나기 전에 등록해야 한다
    BackgroundAnalysisBridge.shared.registerTask()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 사진 분석 진행을 잠금화면·알림 센터에 띄우는 Live Activity 연결
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SnapbackLiveActivity") {
      LiveActivityBridge.shared.register(messenger: registrar.messenger())
    }
    // 충전 중 백그라운드 분석(BGProcessingTask) ↔ Flutter 연결
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SnapbackBackground") {
      BackgroundAnalysisBridge.shared.register(messenger: registrar.messenger())
    }
  }
}

/// 충전 중 장기 백그라운드 분석 (MethodChannel "snapback/background").
///
/// 일반 백그라운드는 약 30초만 허락돼(LiveActivityBridge) 사진이 많으면 분석이 멈춘다.
/// 분석할 사진이 남은 채로 앱이 백그라운드로 가면 BGProcessingTask 를 예약해 두고,
/// iOS 가 충전 중·네트워크 연결·기기를 쓰지 않을 때 실행해 주면 Flutter 에 남은 분석을 이어 하게 한다.
/// 허락된 시간이 끝나면 Flutter 가 지금 사진까지 마치고 대기열을 저장하며, 남았으면 다시 예약한다.
final class BackgroundAnalysisBridge {
  static let shared = BackgroundAnalysisBridge()
  static let taskId = "com.snapback.snapbackApp.analysis"

  private var channel: FlutterMethodChannel?
  private var flutterReady = false
  private var pending = false
  private var waitingTask: BGProcessingTask?
  private var running: BGProcessingTask?

  func registerTask() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskId, using: nil) { task in
      guard let task = task as? BGProcessingTask else { return task.setTaskCompleted(success: false) }
      DispatchQueue.main.async { self.handle(task) }
    }
  }

  func register(messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "snapback/background", binaryMessenger: messenger)
    channel = ch
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "ready":
        // Flutter 가 대기열을 복원하고 준비됨 → 기다리던 작업이 있으면 지금 시작
        self.flutterReady = true
        if let task = self.waitingTask {
          self.waitingTask = nil
          self.start(task)
        }
        result(nil)
      case "setPending":
        self.pending = call.arguments as? Bool ?? false
        if !self.pending {
          BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskId)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(didEnterBackground),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
  }

  /// 분석할 사진이 남은 채로 백그라운드로 가면 예약 (충전 중 + 네트워크 필요)
  @objc private func didEnterBackground() {
    if pending { schedule() }
  }

  private func schedule() {
    let req = BGProcessingTaskRequest(identifier: Self.taskId)
    req.requiresExternalPower = true
    req.requiresNetworkConnectivity = true
    do {
      try BGTaskScheduler.shared.submit(req)
    } catch {
      NSLog("백그라운드 분석 예약 실패: \(error)")
    }
  }

  private func handle(_ task: BGProcessingTask) {
    task.expirationHandler = { [weak self] in
      DispatchQueue.main.async { self?.expire(task) }
    }
    if flutterReady {
      start(task)
    } else {
      // 백그라운드로 새로 실행된 경우: Flutter 가 준비될 때까지(최대 20초) 기다린다
      waitingTask = task
      DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
        guard let self, self.waitingTask === task else { return }
        self.waitingTask = nil
        self.finish(task, success: false)
      }
    }
  }

  private func start(_ task: BGProcessingTask) {
    guard let ch = channel else { return finish(task, success: false) }
    running = task
    ch.invokeMethod("run", arguments: nil) { [weak self] result in
      guard let self, self.running === task else { return }
      self.finish(task, success: (result as? Bool) == true)
    }
  }

  private func expire(_ task: BGProcessingTask) {
    if waitingTask === task { waitingTask = nil }
    channel?.invokeMethod("expire", arguments: nil)
    finish(task, success: false)
  }

  private func finish(_ task: BGProcessingTask, success: Bool) {
    if running === task { running = nil }
    task.setTaskCompleted(success: success)
    // 아직 남았으면 다음 충전 때 이어서
    if !success || pending { schedule() }
  }
}

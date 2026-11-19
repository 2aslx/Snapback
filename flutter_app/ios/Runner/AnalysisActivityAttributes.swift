// 사진 분석 Live Activity 데이터 모델.
// 앱(Runner)과 위젯 확장(SnapbackLiveActivity) 두 타깃이 함께 컴파일한다.
import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct AnalysisActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    /// 분석한 사진 수
    var done: Int
    /// 전체 사진 수
    var total: Int
    /// 사용자가 일시정지함
    var paused: Bool
    /// 모두 끝남
    var finished: Bool
    /// 앱이 백그라운드에서 오래 있어 iOS 가 분석을 멈춤 (앱을 열면 이어서)
    var interrupted: Bool

    var progress: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
    var percent: Int { Int((progress * 100).rounded()) }
    var status: String {
      if finished { return "분석 완료" }
      if interrupted { return "잠시 멈춤" }
      if paused { return "일시정지됨" }
      return "사진 분석 중"
    }
  }
}

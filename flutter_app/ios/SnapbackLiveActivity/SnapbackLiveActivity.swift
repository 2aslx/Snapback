// 사진 분석 Live Activity — 앱 하단 분석 진행 바(_MiniProgressCard)와 같은 디자인.
// 잠금화면 · 알림 센터 · 다이내믹 아일랜드에 표시된다.
import ActivityKit
import SwiftUI
import WidgetKit

@main
struct SnapbackLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    if #available(iOS 16.1, *) {
      AnalysisLiveActivity()
    }
  }
}

private let warm1 = Color(red: 0xF4 / 255, green: 0xA4 / 255, blue: 0x5A / 255) // #F4A45A
private let pri = Color(red: 0xE8 / 255, green: 0x79 / 255, blue: 0x3A / 255) // #E8793A
private let pauseBg = Color(red: 0x7A / 255, green: 0x3A / 255, blue: 0x14 / 255) // #7A3A14

@available(iOS 16.1, *)
private func countText(_ s: AnalysisActivityAttributes.ContentState) -> String {
  "\(s.done.formatted()) / \(s.total.formatted())장"
}

/// 상태별 캐릭터: 달리기 / 서 있기(일시정지) / 만세(완료)
@available(iOS 16.1, *)
private func character(_ s: AnalysisActivityAttributes.ContentState) -> String {
  s.finished ? "CharCheer" : (s.paused || s.interrupted ? "CharIdle" : "CharRun")
}

/// .mtrk — 흰 트랙 + 진행 위치의 미니 캐릭터
@available(iOS 16.1, *)
private struct Track: View {
  let state: AnalysisActivityAttributes.ContentState
  var runner: CGFloat = 26
  var trackColor: Color = .white.opacity(0.35)
  var fillColor: Color = .white

  var body: some View {
    GeometryReader { g in
      ZStack(alignment: .bottomLeading) {
        Capsule().fill(trackColor).frame(height: 4).padding(.bottom, 4)
        Capsule().fill(fillColor)
          .frame(width: max(4, g.size.width * state.progress), height: 4)
          .padding(.bottom, 4)
        Image(character(state)).resizable().scaledToFit()
          .frame(width: runner, height: runner)
          .offset(x: (g.size.width - runner) * state.progress, y: -5)
          .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
      }
    }
    .frame(height: runner + 4)
  }
}

@available(iOS 16.1, *)
struct AnalysisLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: AnalysisActivityAttributes.self) { ctx in
      // 잠금화면 · 알림 센터: 앱 하단 바와 같은 주황 그라데이션 카드
      let s = ctx.state
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          (Text(s.status).fontWeight(.bold) + Text(" · " + countText(s)))
            .font(.system(size: 15))
            .monospacedDigit()
          Track(state: s)
          if s.interrupted {
            Text("앱을 열면 이어서 분석해요")
              .font(.system(size: 12)).opacity(0.85)
          }
        }
        Text("\(s.percent)%")
          .font(.system(size: 17, weight: .bold))
          .monospacedDigit()
        if !s.finished {
          Image(systemName: s.paused || s.interrupted ? "play.fill" : "pause.fill")
            .font(.system(size: 15, weight: .bold))
            .frame(width: 36, height: 36)
            .background(Circle().fill(pauseBg))
        }
      }
      .foregroundColor(.white)
      .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 12)
      .background(
        LinearGradient(colors: [warm1, pri], startPoint: .topLeading, endPoint: .bottomTrailing))
      .activityBackgroundTint(pri)
      .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { ctx in
      let s = ctx.state
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(character(s)).resizable().scaledToFit().frame(width: 40, height: 40)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text("\(s.percent)%")
            .font(.system(size: 22, weight: .bold)).monospacedDigit()
            .foregroundColor(warm1)
        }
        DynamicIslandExpandedRegion(.center) {
          (Text(s.status).fontWeight(.bold) + Text(" · " + countText(s)))
            .font(.system(size: 14)).monospacedDigit()
            .lineLimit(1)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 4) {
            Track(state: s, runner: 22, trackColor: .white.opacity(0.2), fillColor: warm1)
            if s.interrupted {
              Text("앱을 열면 이어서 분석해요").font(.system(size: 12)).foregroundColor(.secondary)
            }
          }
        }
      } compactLeading: {
        Image(character(s)).resizable().scaledToFit().frame(width: 22, height: 22)
      } compactTrailing: {
        Text("\(s.percent)%")
          .font(.system(size: 14, weight: .bold)).monospacedDigit()
          .foregroundColor(warm1)
      } minimal: {
        ProgressView(value: s.progress) {
          Image(character(s)).resizable().scaledToFit().frame(width: 14, height: 14)
        }
        .progressViewStyle(.circular)
        .tint(warm1)
      }
      .keylineTint(warm1)
    }
  }
}

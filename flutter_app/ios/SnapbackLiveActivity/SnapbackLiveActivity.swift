// 사진 분석 Live Activity — 앱 하단 분석 카드(_MiniProgressCard, 디자인 B3)와 같은 디자인.
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

// 디자인 B3 · 화이트 오렌지 (앱 하단 분석 카드와 같은 색)
private let pri = Color(red: 0xF2 / 255, green: 0x6B / 255, blue: 0x1D / 255) // #F26B1D
private let ink = Color(red: 0x1C / 255, green: 0x17 / 255, blue: 0x14 / 255) // #1C1714
private let mute = Color(red: 0x77 / 255, green: 0x70 / 255, blue: 0x6A / 255) // #77706A

@available(iOS 16.1, *)
private func countText(_ s: AnalysisActivityAttributes.ContentState) -> String {
  "\(s.done.formatted()) / \(s.total.formatted()) · \(s.percent)%"
}

/// 상태별 찰칵이: 달리기 / 서 있기(일시정지) / 만세(완료)
@available(iOS 16.1, *)
private func character(_ s: AnalysisActivityAttributes.ContentState) -> String {
  s.finished ? "CharCheer" : (s.paused || s.interrupted ? "CharIdle" : "CharRun")
}

/// 얇은 진행선
@available(iOS 16.1, *)
private struct Bar: View {
  let progress: Double
  var track: Color = .black.opacity(0.06)
  var body: some View {
    GeometryReader { g in
      ZStack(alignment: .leading) {
        Capsule().fill(track)
        Capsule().fill(pri).frame(width: max(5, g.size.width * progress))
      }
    }
    .frame(height: 5)
  }
}

@available(iOS 16.1, *)
struct AnalysisLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: AnalysisActivityAttributes.self) { ctx in
      // 잠금화면 · 알림 센터: 앱 하단 분석 카드와 같은 흰 카드
      let s = ctx.state
      HStack(spacing: 12) {
        Image(character(s)).resizable().scaledToFit().frame(width: 54, height: 54)
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text(s.status).font(.system(size: 16, weight: .bold)).foregroundColor(ink)
            Spacer(minLength: 6)
            Text(countText(s)).font(.system(size: 14)).monospacedDigit().foregroundColor(mute)
          }
          Bar(progress: s.progress)
          if s.interrupted {
            Text("앱을 열면 이어서 분석해요").font(.system(size: 12)).foregroundColor(mute)
          }
        }
        if !s.finished {
          Image(systemName: s.paused || s.interrupted ? "play.fill" : "pause.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(ink))
        }
      }
      .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 12)
      .activityBackgroundTint(Color.white.opacity(0.92))
      .activitySystemActionForegroundColor(ink)
    } dynamicIsland: { ctx in
      let s = ctx.state
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(character(s)).resizable().scaledToFit().frame(width: 44, height: 44)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text("\(s.percent)%")
            .font(.system(size: 22, weight: .bold)).monospacedDigit()
            .foregroundColor(pri)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 2) {
            Text(s.status).font(.system(size: 15, weight: .bold))
            Text("\(s.done.formatted()) / \(s.total.formatted())장")
              .font(.system(size: 13)).monospacedDigit().foregroundColor(.secondary)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 4) {
            Bar(progress: s.progress, track: .white.opacity(0.2))
            if s.interrupted {
              Text("앱을 열면 이어서 분석해요").font(.system(size: 12)).foregroundColor(.secondary)
            }
          }
          .padding(.top, 4)
        }
      } compactLeading: {
        Image(character(s)).resizable().scaledToFit().frame(width: 28, height: 28)
      } compactTrailing: {
        Text("\(s.percent)%")
          .font(.system(size: 14, weight: .bold)).monospacedDigit()
          .foregroundColor(pri)
      } minimal: {
        ProgressView(value: s.progress) {
          Image(character(s)).resizable().scaledToFit().frame(width: 14, height: 14)
        }
        .progressViewStyle(.circular)
        .tint(pri)
      }
      .keylineTint(pri)
    }
  }
}

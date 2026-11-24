import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 사진 분석 진행을 잠금화면·알림 센터에 띄우는 Live Activity 연결
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SnapbackLiveActivity") {
      LiveActivityBridge.shared.register(messenger: registrar.messenger())
    }
  }
}

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
    // AERO Engine 2 — Apple Intelligence bridge (channel com.onyxbeacon/aero).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AeroAppleAIPlugin") {
      AeroAppleAIPlugin.register(with: registrar)
    }
  }
}

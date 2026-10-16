import Flutter
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// AERO Engine 2 — Apple Intelligence via FoundationModels.
// FoundationModels ships with iOS 26 (iPhone 15 Pro / 16 / 17 series with Apple Intelligence on).
// `#if canImport` keeps the app building on an older Xcode; it then reports "sdkMissing" instead of failing.
// Channel: com.onyxbeacon/aero
//   appleIntelligenceStatus -> String: available | deviceNotEligible | appleIntelligenceNotEnabled | modelNotReady | unavailable | osTooOld | sdkMissing
//   generate {prompt, instructions} -> String, or FlutterError(UNAVAILABLE | GENERATION_FAILED | INVALID_ARGS)
class AeroAppleAIPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.onyxbeacon/aero", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AeroAppleAIPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "appleIntelligenceStatus":
      result(AeroAppleAIPlugin.status())
    case "generate":
      guard let args = call.arguments as? [String: Any],
            let prompt = args["prompt"] as? String, !prompt.isEmpty else {
        result(FlutterError(code: "INVALID_ARGS", message: "prompt is required", details: nil))
        return
      }
      let instructions = args["instructions"] as? String ?? ""
      generate(prompt: prompt, instructions: instructions, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func status() -> String {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      switch SystemLanguageModel.default.availability {
      case .available:
        return "available"
      case .unavailable(let reason):
        switch reason {
        case .deviceNotEligible: return "deviceNotEligible"
        case .appleIntelligenceNotEnabled: return "appleIntelligenceNotEnabled"
        case .modelNotReady: return "modelNotReady"
        @unknown default: return "unavailable"
        }
      @unknown default:
        return "unavailable"
      }
    }
    return "osTooOld"
    #else
    return "sdkMissing"
    #endif
  }

  private func generate(prompt: String, instructions: String, result: @escaping FlutterResult) {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      let current = AeroAppleAIPlugin.status()
      guard current == "available" else {
        result(FlutterError(code: "UNAVAILABLE", message: current, details: nil))
        return
      }
      // A fresh session per message: the Dart side sends the recent conversation inside `prompt`,
      // which keeps every request well under the model's 4,096-token window.
      // Instructions go in Apple's real instructions slot so the model actually takes on AERO's role.
      Task {
        do {
          let session = instructions.isEmpty
            ? LanguageModelSession()
            : LanguageModelSession(instructions: instructions)
          let response = try await session.respond(to: prompt)
          let text = response.content
          DispatchQueue.main.async { result(text) }
        } catch {
          NSLog("[AERO] Apple Intelligence generate failed: \(error)")
          DispatchQueue.main.async {
            result(FlutterError(code: "GENERATION_FAILED", message: error.localizedDescription, details: nil))
          }
        }
      }
      return
    }
    #endif
    result(FlutterError(code: "UNAVAILABLE", message: AeroAppleAIPlugin.status(), details: nil))
  }
}

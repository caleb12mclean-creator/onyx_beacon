import Flutter
import UIKit
import CoreLocation
import MapKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// AERO native bridge. Channel: com.onyxbeacon/aero
//   appleIntelligenceStatus -> String: available | deviceNotEligible | appleIntelligenceNotEnabled | modelNotReady | unavailable | osTooOld | sdkMissing
//   generate {prompt, instructions} -> String, or FlutterError(UNAVAILABLE | GENERATION_FAILED | INVALID_ARGS)
//   placesSearch {query, near} -> {near: "you" | <city> | "", items: [{name, address?, phone?, url?, miles?}]}
//                                 or FlutterError(PLACES_FAILED | INVALID_ARGS)
//
// Apple Intelligence: FoundationModels ships with iOS 26 (iPhone 15 Pro / 16 / 17 series with Apple Intelligence on).
// `#if canImport` keeps the app building on an older Xcode; it then reports "sdkMissing" instead of failing.
// Places: Apple Maps search (MKLocalSearch) is built into iOS — free, no API key, no account. Location is asked for
// only the first time someone asks about places nearby; if it's declined, the city from AERO's profile is used.
class AeroAppleAIPlugin: NSObject, FlutterPlugin {
  private var locationFetcher: AeroLocationFetcher?
  private var geocoder: CLGeocoder?

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
    case "placesSearch":
      guard let args = call.arguments as? [String: Any],
            let query = args["query"] as? String, !query.isEmpty else {
        result(FlutterError(code: "INVALID_ARGS", message: "query is required", details: nil))
        return
      }
      let near = args["near"] as? String ?? ""
      placesSearch(query: query, near: near, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Apple Intelligence

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

  // MARK: - Nearby places (Apple Maps)

  private func placesSearch(query: String, near: String, result: @escaping FlutterResult) {
    let fetcher = AeroLocationFetcher()
    locationFetcher = fetcher
    fetcher.fetch { location in
      // Release the fetcher on the next run-loop turn, never while it is still inside its own delegate callback.
      DispatchQueue.main.async { self.locationFetcher = nil }
      if let location = location {
        self.runSearch(query: query, center: location.coordinate, label: "you", result: result)
      } else if !near.isEmpty {
        let geocoder = CLGeocoder()
        self.geocoder = geocoder
        geocoder.geocodeAddressString(near) { placemarks, _ in
          DispatchQueue.main.async { self.geocoder = nil }
          let center = placemarks?.first?.location?.coordinate
          self.runSearch(query: query, center: center, label: center == nil ? "" : near, result: result)
        }
      } else {
        self.runSearch(query: query, center: nil, label: "", result: result)
      }
    }
  }

  private func runSearch(query: String, center: CLLocationCoordinate2D?, label: String, result: @escaping FlutterResult) {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    request.resultTypes = .pointOfInterest
    if let center = center {
      // ~25-mile box around the person (or their city).
      request.region = MKCoordinateRegion(center: center, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
    }
    MKLocalSearch(request: request).start { response, error in
      let origin = center.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
      var items: [[String: Any]] = []
      for item in response?.mapItems ?? [] {
        var entry: [String: Any] = ["name": item.name ?? "Unnamed place"]
        let placemark = item.placemark
        if let address = placemark.title, !address.isEmpty { entry["address"] = address }
        if let phone = item.phoneNumber, !phone.isEmpty { entry["phone"] = phone }
        if let url = item.url { entry["url"] = url.absoluteString }
        if let origin = origin, let location = placemark.location {
          entry["miles"] = location.distance(from: origin) / 1609.344
        }
        items.append(entry)
      }
      if origin != nil {
        items.sort {
          (($0["miles"] as? Double) ?? Double.greatestFiniteMagnitude) < (($1["miles"] as? Double) ?? Double.greatestFiniteMagnitude)
        }
      }
      let top = Array(items.prefix(8))
      DispatchQueue.main.async {
        if top.isEmpty, let error = error {
          let ns = error as NSError
          // MKErrorDomain code 4 = placemarkNotFound: simply no matches, not a failure.
          if ns.domain == "MKErrorDomain" && ns.code == 4 {
            let empty: [String: Any] = ["near": label, "items": [Any]()]
            result(empty)
          } else {
            NSLog("[AERO] places search failed: \(error)")
            result(FlutterError(code: "PLACES_FAILED", message: error.localizedDescription, details: nil))
          }
        } else {
          let payload: [String: Any] = ["near": label, "items": top]
          result(payload)
        }
      }
    }
  }
}

/// One-shot "where am I roughly" lookup. Asks permission the first time; gives up after 15 s and returns nil.
final class AeroLocationFetcher: NSObject, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private var completion: ((CLLocation?) -> Void)?

  func fetch(_ done: @escaping (CLLocation?) -> Void) {
    completion = done
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyKilometer
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedWhenInUse, .authorizedAlways:
      manager.requestLocation()
    default:
      finish(nil)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.finish(nil) }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard completion != nil else { return }
    switch manager.authorizationStatus {
    case .authorizedWhenInUse, .authorizedAlways:
      manager.requestLocation()
    case .notDetermined:
      break
    default:
      finish(nil)
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    finish(locations.last)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    finish(nil)
  }

  private func finish(_ location: CLLocation?) {
    guard let done = completion else { return }
    completion = nil
    done(location)
  }
}

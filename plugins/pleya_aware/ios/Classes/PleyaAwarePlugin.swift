import Flutter
import UIKit

#if canImport(WiFiAware)
  import Network
  import WiFiAware
#endif
#if canImport(DeviceDiscoveryUI)
  import DeviceDiscoveryUI
  import SwiftUI
#endif

/// Wi-Fi Aware byte-stream transport for Pleya Share (iOS 26+, iPhone 12+).
///
/// Host: publishes the `_pleya-share._tcp` Aware service (declared in the
/// app's Info.plist under WiFiAwareServices) and accepts connections via a
/// NetworkListener; every connection is pumped to Dart as a byte stream.
/// Guest: browses for paired hosts and opens a NetworkConnection.
///
/// iOS requires a one-time system pairing (DeviceDiscoveryUI) before
/// endpoints can connect; `presentPairing` shows that sheet.
public class PleyaAwarePlugin: NSObject, FlutterPlugin {
  private var sink: FlutterEventSink?
  private var nextStreamId = 1

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = PleyaAwarePlugin()
    let channel = FlutterMethodChannel(name: "pleya_aware", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    let events = FlutterEventChannel(name: "pleya_aware/events", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { self.sink?(event) }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if canImport(WiFiAware)
      if #available(iOS 26.0, *) {
        AwareEngine.shared.emit = { [weak self] event in self?.emit(event) }
        switch call.method {
        case "isSupported":
          result(WACapabilities.supportedFeatures.contains(.wifiAware))
        case "startPublishing":
          let info = (call.arguments as? [String: Any])?["serviceInfo"] as? String ?? ""
          AwareEngine.shared.startPublishing(serviceInfo: info)
          result(nil)
        case "stopPublishing":
          AwareEngine.shared.stopPublishing()
          result(nil)
        case "startDiscovery":
          AwareEngine.shared.startDiscovery()
          result(nil)
        case "stopDiscovery":
          AwareEngine.shared.stopDiscovery()
          result(nil)
        case "connect":
          let peerId = (call.arguments as? [String: Any])?["peerId"] as? Int ?? -1
          AwareEngine.shared.connect(peerId: peerId) { streamId in
            if let streamId { result(streamId) } else {
              result(FlutterError(code: "connect_failed", message: nil, details: nil))
            }
          }
        case "write":
          let args = call.arguments as? [String: Any]
          if let id = args?["streamId"] as? Int, let data = args?["bytes"] as? FlutterStandardTypedData {
            AwareEngine.shared.write(streamId: id, data: data.data)
          }
          result(nil)
        case "closeStream":
          if let id = (call.arguments as? [String: Any])?["streamId"] as? Int {
            AwareEngine.shared.closeStream(id)
          }
          result(nil)
        case "presentPairing":
          let asHost = (call.arguments as? [String: Any])?["asHost"] as? Bool ?? false
          AwareEngine.shared.presentPairing(asHost: asHost)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
        return
      }
    #endif
    // Older iOS / SDK without WiFiAware: only isSupported is meaningful.
    switch call.method {
    case "isSupported", "presentPairing", "stopPublishing", "stopDiscovery", "closeStream":
      result(call.method == "isSupported" ? false : nil)
    default:
      result(FlutterError(code: "unsupported", message: "Wi-Fi Aware requires iOS 26", details: nil))
    }
  }
}

extension PleyaAwarePlugin: FlutterStreamHandler {
  public func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  public func onCancel(withArguments _: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}

#if canImport(WiFiAware)
  /// The actual Aware machinery, isolated behind availability.
  @available(iOS 26.0, *)
  final class AwareEngine {
    static let shared = AwareEngine()
    var emit: (([String: Any]) -> Void)?

    private var listenerTask: Task<Void, Never>?
    private var browserTask: Task<Void, Never>?
    private var nextStreamId = 1
    private var nextPeerId = 1
    private var connections: [Int: NetworkConnection<TLS>] = [:]
    private var endpoints: [Int: WAEndpoint] = [:]
    private let lock = NSLock()

    static var service: String { "_pleya-share._tcp" }

    // ── Host ──

    func startPublishing(serviceInfo _: String) {
      guard listenerTask == nil else { return }
      listenerTask = Task {
        do {
          guard let publishable = WAPublishableService.allServices[Self.service] else { return }
          let listener = try NetworkListener(for: .wifiAware(.connecting(to: publishable, from: .allPairedDevices))) {
            TLS()
          }
          try await listener.run { connection in
            self.adopt(connection: connection, accepted: true)
          }
        } catch {
          NSLog("PleyaAware: listener failed: \(error)")
        }
      }
    }

    func stopPublishing() {
      listenerTask?.cancel()
      listenerTask = nil
    }

    // ── Guest ──

    func startDiscovery() {
      guard browserTask == nil else { return }
      browserTask = Task {
        do {
          guard let subscribable = WASubscribableService.allServices[Self.service] else { return }
          let browser = NetworkBrowser(for: .wifiAware(.connecting(to: .allPairedDevices, from: subscribable)))
          try await browser.run { waEndpoints in
            for endpoint in waEndpoints {
              self.lock.lock()
              let known = self.endpoints.values.contains { "\($0)" == "\(endpoint)" }
              var peerId = -1
              if !known {
                peerId = self.nextPeerId
                self.nextPeerId += 1
                self.endpoints[peerId] = endpoint
              }
              self.lock.unlock()
              if peerId > 0 {
                // iOS advertises no free-form service info; the Dart side
                // matches loosely and the HTTP handshake is the real
                // identity check.
                self.emit?(["type": "discovered", "peerId": peerId, "serviceInfo": "\(endpoint)"])
              }
            }
          }
        } catch {
          NSLog("PleyaAware: browser failed: \(error)")
        }
      }
    }

    func stopDiscovery() {
      browserTask?.cancel()
      browserTask = nil
      lock.lock()
      endpoints.removeAll()
      lock.unlock()
    }

    func connect(peerId: Int, completion: @escaping (Int?) -> Void) {
      lock.lock()
      let endpoint = endpoints[peerId]
      lock.unlock()
      guard let endpoint else {
        completion(nil)
        return
      }
      Task {
        let connection = NetworkConnection(to: endpoint) { TLS() }
        let id = self.adopt(connection: connection, accepted: false)
        completion(id)
      }
    }

    // ── Byte pump ──

    @discardableResult
    private func adopt(connection: NetworkConnection<TLS>, accepted: Bool) -> Int {
      lock.lock()
      let id = nextStreamId
      nextStreamId += 1
      connections[id] = connection
      lock.unlock()
      if accepted { emit?(["type": "accepted", "streamId": id]) }
      Task {
        do {
          while true {
            let received = try await connection.receive(atLeast: 1, atMost: 64 * 1024)
            let data = Data(received.content)
            if data.isEmpty { break }
            self.emit?(["type": "data", "streamId": id, "bytes": FlutterStandardTypedData(bytes: data)])
          }
        } catch {}
        self.closeStream(id)
      }
      return id
    }

    func write(streamId: Int, data: Data) {
      lock.lock()
      let connection = connections[streamId]
      lock.unlock()
      guard let connection else { return }
      Task {
        try? await connection.send(data)
      }
    }

    func closeStream(_ id: Int) {
      lock.lock()
      let connection = connections.removeValue(forKey: id)
      lock.unlock()
      guard let connection else { return }
      // Stream protocol: an empty send with endOfStream tears the TLS
      // stream down gracefully; the peer's receive loop then finishes.
      Task { try? await connection.send(Data(), endOfStream: true) }
      emit?(["type": "closed", "streamId": id])
    }

    // ── Pairing sheet ──

    func presentPairing(asHost: Bool) {
      #if canImport(DeviceDiscoveryUI)
        DispatchQueue.main.async {
          guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first?.rootViewController
          else { return }
          let view: AnyView
          if asHost {
            guard let publishable = WAPublishableService.allServices[Self.service] else { return }
            view = AnyView(
              DevicePairingView(.wifiAware(.connecting(to: publishable, from: .selected([])))) {
                Text("Pair a Pleya device")
              } fallback: {
                Text("Wi-Fi Aware is not available")
              }
            )
          } else {
            guard let subscribable = WASubscribableService.allServices[Self.service] else { return }
            view = AnyView(
              DevicePicker(.wifiAware(.connecting(to: .selected([]), from: subscribable))) { _ in
                // Paired; browser will find it from now on.
              } label: {
                Text("Find a Pleya host")
              } fallback: {
                Text("Wi-Fi Aware is not available")
              }
            )
          }
          let host = UIHostingController(rootView: view)
          root.present(host, animated: true)
        }
      #endif
    }
  }
#endif

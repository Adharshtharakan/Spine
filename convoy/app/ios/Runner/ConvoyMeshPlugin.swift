import Flutter
import MultipeerConnectivity
import UIKit

/// Offline convoy mesh over MultipeerConnectivity (Bluetooth + peer-to-peer
/// Wi-Fi, no internet needed). Same channel contract as the Android
/// Nearby Connections plugin. Only peers advertising the same trip tag are
/// invited or accepted; frames are also HMAC-checked in Dart.
final class ConvoyMeshPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  // ≤15 chars, matches NSBonjourServices (_convoy-mesh._tcp/_udp) in Info.plist.
  private static let serviceType = "convoy-mesh"

  private var sink: FlutterEventSink?
  private var peerID: MCPeerID?
  private var session: MCSession?
  private var advertiser: MCNearbyServiceAdvertiser?
  private var browser: MCNearbyServiceBrowser?
  private var tripTag = ""
  private var endpointName = ""

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ConvoyMeshPlugin()
    let methods = FlutterMethodChannel(name: "convoy/mesh", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
    let events = FlutterEventChannel(name: "convoy/mesh/events", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "start":
      tripTag = args["tripTag"] as? String ?? ""
      endpointName = args["endpointName"] as? String ?? tripTag
      start()
      result(nil)
    case "broadcast":
      if let data = (args["bytes"] as? FlutterStandardTypedData)?.data,
         let s = session, !s.connectedPeers.isEmpty {
        let reliable = args["reliable"] as? Bool ?? true
        try? s.send(data, toPeers: s.connectedPeers, with: reliable ? .reliable : .unreliable)
      }
      result(nil)
    case "stop":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start() {
    stop()
    // Display names are capped at 63 bytes by MultipeerConnectivity.
    let me = MCPeerID(displayName: String(endpointName.prefix(60)))
    peerID = me
    let s = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
    s.delegate = self
    session = s

    let adv = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: ["trip": tripTag], serviceType: Self.serviceType)
    adv.delegate = self
    adv.startAdvertisingPeer()
    advertiser = adv

    let br = MCNearbyServiceBrowser(peer: me, serviceType: Self.serviceType)
    br.delegate = self
    br.startBrowsingForPeers()
    browser = br
  }

  private func stop() {
    advertiser?.stopAdvertisingPeer()
    browser?.stopBrowsingForPeers()
    session?.disconnect()
    advertiser = nil
    browser = nil
    session = nil
    emitPeers()
  }

  private func emitPeers() {
    let n = session?.connectedPeers.count ?? 0
    DispatchQueue.main.async { self.sink?(["type": "peers", "count": n]) }
  }
}

extension ConvoyMeshPlugin: MCSessionDelegate {
  func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
    emitPeers()
  }

  func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
    let bytes = FlutterStandardTypedData(bytes: data)
    DispatchQueue.main.async { self.sink?(["type": "payload", "bytes": bytes]) }
  }

  func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
  func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
  func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension ConvoyMeshPlugin: MCNearbyServiceBrowserDelegate {
  func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
    guard info?["trip"] == tripTag, let s = session, let me = self.peerID else { return }
    guard !s.connectedPeers.contains(peerID) else { return }
    // One side invites to avoid duplicate sessions: the smaller name.
    guard me.displayName < peerID.displayName else { return }
    browser.invitePeer(peerID, to: s, withContext: tripTag.data(using: .utf8), timeout: 20)
  }

  func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}

extension ConvoyMeshPlugin: MCNearbyServiceAdvertiserDelegate {
  func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                  withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
    let theirTrip = context.flatMap { String(data: $0, encoding: .utf8) }
    invitationHandler(theirTrip == tripTag, theirTrip == tripTag ? session : nil)
  }
}

import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private static let captureChannelName = "spine/capture_guard"
  private static let storyShareChannelName = "spine/story_share"

  private var captureChannel: FlutterMethodChannel?
  private var isProtected = false

  /// Covers the app's content in the App Switcher while protection is on.
  private var privacyCover: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: AppDelegate.captureChannelName,
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "setProtected" else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.isProtected = (call.arguments as? Bool) ?? false
        result(nil)
      }

      captureChannel = channel

      let storyChannel = FlutterMethodChannel(
        name: AppDelegate.storyShareChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      storyChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        switch call.method {
        case "canShare":
          let target = (call.arguments as? [String: Any])?["target"] as? String
          result(self.canShareToStory(target: target))
        case "shareToStory":
          let args = call.arguments as? [String: Any]
          let target = args?["target"] as? String
          let path = args?["path"] as? String
          result(self.shareToStory(target: target, path: path))
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    // iOS provides no way to *prevent* a screenshot — Apple deliberately
    // doesn't expose one. The most an app can do is know that one was taken
    // and tell the Dart side, which is what this notification is for.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @objc private func handleScreenshot() {
    guard isProtected else { return }
    captureChannel?.invokeMethod("screenshotTaken", arguments: nil)
  }

  // The app switcher snapshot is the one capture iOS *does* let an app control.
  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    guard isProtected, let window = window, privacyCover == nil else { return }

    let cover = UIView(frame: window.bounds)
    cover.backgroundColor = UIColor(
      red: 0.051, green: 0.047, blue: 0.035, alpha: 1  // Spine ink
    )
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(cover)
    privacyCover = cover
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }

  // MARK: - Story sharing
  //
  // iOS has no "add to story" intent the way Android does. Instagram and
  // Facebook both instead read a specifically-keyed UIPasteboard item after
  // being opened via a custom URL scheme — see Meta's "Sharing to Stories"
  // docs. Both require LSApplicationQueriesSchemes entries (Info.plist) to
  // even ask whether the app is installed.

  private func storyScheme(for target: String?) -> URL? {
    switch target {
    case "instagram": return URL(string: "instagram-stories://share")
    case "facebook": return URL(string: "facebook-stories://share")
    default: return nil
    }
  }

  private func canShareToStory(target: String?) -> Bool {
    guard let scheme = storyScheme(for: target) else { return false }
    return UIApplication.shared.canOpenURL(scheme)
  }

  private func shareToStory(target: String?, path: String?) -> Bool {
    guard let path = path,
      let scheme = storyScheme(for: target),
      UIApplication.shared.canOpenURL(scheme),
      let imageData = FileManager.default.contents(atPath: path)
    else { return false }

    var items: [String: Any] = [:]
    switch target {
    case "instagram":
      items["com.instagram.sharedSticker.backgroundImage"] = imageData
    case "facebook":
      items["com.facebook.sharedSticker.backgroundImage"] = imageData
      // Facebook's contract also wants the sharing app's Facebook App ID.
      // Add a `FacebookAppID` key to Info.plist to populate this — until
      // then the sticker still hands off, just without app attribution.
      if let appId = Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String {
        items["com.facebook.sharedSticker.appID"] = appId
      }
    default:
      return false
    }

    UIPasteboard.general.setItems(
      [items],
      options: [.expirationDate: Date().addingTimeInterval(60 * 5)]
    )
    UIApplication.shared.open(scheme, options: [:], completionHandler: nil)
    return true
  }
}

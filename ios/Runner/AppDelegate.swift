import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private static let captureChannelName = "spine/capture_guard"

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
}

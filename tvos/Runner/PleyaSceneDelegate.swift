import Flutter
import UIKit

/// The window scene of the app. tvOS 27 refuses to launch an app that has not
/// adopted the UIScene lifecycle: UIKit traps in
/// `_UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption` before the
/// first frame (build 314 on a tvOS 27.0 Apple TV, 1 Oct 2026). The scene loads
/// `Main.storyboard` (`UISceneStoryboardFile` in Info.plist), whose initial view
/// controller is `PleyaFlutterViewController`; `FlutterSceneDelegate` attaches
/// the implicit engine, and `AppDelegate` registers the plugins once that
/// engine exists.
///
/// Opening URLs moved here too: under scenes, a Top Shelf deep link arrives as
/// a scene connection option on a cold start and through `openURLContexts`
/// while running, no longer through `launchOptions` or
/// `application(_:open:options:)`.
@objc(PleyaSceneDelegate)
class PleyaSceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts {
      _ = SystemShelfPlugin.handleOpenURL(context.url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let unhandled = URLContexts.filter { !SystemShelfPlugin.handleOpenURL($0.url) }
    if !unhandled.isEmpty {
      super.scene(scene, openURLContexts: unhandled)
    }
  }
}

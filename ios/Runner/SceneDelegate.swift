import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    registerNativeChannels()
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    registerNativeChannels()
  }

  private func registerNativeChannels() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    OnDeviceVisionChannel.register(with: controller.binaryMessenger)
    AudioPlaybackChannel.register(with: controller.binaryMessenger)
  }
}

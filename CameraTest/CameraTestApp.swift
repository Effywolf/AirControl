import AppKit

@main
class CameraTestApp: NSObject, NSApplicationDelegate {

    private var gestureController: GestureController!
    private var menuBarController: MenuBarController!
    private static var appDelegate: CameraTestApp?

    static func main() {
        let app = NSApplication.shared
        appDelegate = CameraTestApp()
        app.delegate = appDelegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        
        gestureController = GestureController()
        menuBarController = MenuBarController()
        menuBarController.setup(with: gestureController)
        gestureController.start()

        print("Gesture Control app started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        gestureController.stop()
        print("Gesture Control app terminated")
    }
}

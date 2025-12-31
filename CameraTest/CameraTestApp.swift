//
//  CameraTestApp.swift
//  CameraTest
//
//  Created by Effy on 2025-12-30.
//

import AppKit

@main
class CameraTestApp: NSObject, NSApplicationDelegate {

    private var gestureController: GestureController!
    private var menuBarController: MenuBarController!

    // Keep strong reference to prevent deallocation
    private static var appDelegate: CameraTestApp?

    static func main() {
        let app = NSApplication.shared
        appDelegate = CameraTestApp()
        app.delegate = appDelegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize controllers
        gestureController = GestureController()
        menuBarController = MenuBarController()

        // Setup menu bar
        menuBarController.setup(with: gestureController)

        // Start gesture control automatically
        gestureController.start()

        print("Gesture Control app started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up
        gestureController.stop()
        print("Gesture Control app terminated")
    }
}

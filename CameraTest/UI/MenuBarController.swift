//
//  MenuBarController.swift
//  CameraTest
//
//  Created by Effy on 2025-12-30.
//

import AppKit

class MenuBarController {

    private var statusItem: NSStatusItem?
    private var gestureController: GestureController?

    func setup(with gestureController: GestureController) {
        self.gestureController = gestureController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "Gesture Control")
            button.image?.isTemplate = true
        }
		
        updateMenu()
    }

    private func updateMenu() {
        let menu = NSMenu()

        // Status item
        let statusTitle = gestureController?.isActive == true ? "Gesture Control: On" : "Gesture Control: Off"
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        // Toggle gesture control
        let toggleTitle = gestureController?.isActive == true ? "Stop Gesture Control" : "Start Gesture Control"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleGestureControl), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // Debug mode toggle
        let debugTitle = gestureController?.isDebugModeEnabled() == true ? "Debug Mode: On" : "Debug Mode: Off"
        let debugItem = NSMenuItem(title: debugTitle, action: #selector(toggleDebugMode), keyEquivalent: "d")
        debugItem.target = self
        menu.addItem(debugItem)

        menu.addItem(NSMenuItem.separator())

        // About item
        let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        // Quit item
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

		statusItem.menu = menu
    }

    @objc private func toggleGestureControl() {
        if gestureController?.isActive == true {
            gestureController?.stop()
        } else {
            gestureController?.start()
        }

        updateMenu()
    }

    @objc private func toggleDebugMode() {
        let currentDebugMode = gestureController?.isDebugModeEnabled() ?? false
        gestureController?.setDebugMode(!currentDebugMode)
        updateMenu()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Gesture Control"
        alert.informativeText = """
        Control your Mac's audio with hand gestures!

        Gestures:
        • Open Palm - Play/Pause
        • Thumbs Up - Volume Up
        • Thumbs Down - Volume Down
        • Swipe Right - Next Track
        • Swipe Left - Previous Track
        • Pinch - Toggle Mute

        Version 1.0
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        gestureController?.stop()
        NSApplication.shared.terminate(nil)
    }

    func updateStatus() {
        updateMenu()
    }
}

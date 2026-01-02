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
    private var calibrationWindowController: CalibrationWindowController?

    func setup(with gestureController: GestureController) {
        print("🟢 MenuBarController.setup() called")
        self.gestureController = gestureController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        print("🟢 StatusItem created: \(String(describing: statusItem))")

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "Gesture Control")
            button.image?.isTemplate = true
            print("🟢 Menu bar icon set")
        } else {
            print("❌ Failed to get statusItem button")
        }

        updateMenu()
        print("🟢 Menu updated and attached")
    }

    private func updateMenu() {
        print("🔵 updateMenu() started")
        let menu = NSMenu()

        // Status menu item (renamed to avoid conflict with statusItem property)
        let statusTitle = gestureController?.isActive == true ? "Gesture Control: On" : "Gesture Control: Off"
        let statusMenuItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        print("🔵 Added status item")

        menu.addItem(NSMenuItem.separator())

        // Toggle gesture control
        let toggleTitle = gestureController?.isActive == true ? "Stop Gesture Control" : "Start Gesture Control"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleGestureControl), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        print("🔵 Added toggle item")

        menu.addItem(NSMenuItem.separator())

        // Calibration menu
        print("🔵 Creating calibration menu item...")
        let calibrateItem = NSMenuItem(title: "Calibrate Gestures...", action: #selector(startCalibration), keyEquivalent: "")
        calibrateItem.target = self
        menu.addItem(calibrateItem)
        print("🔵 Added calibration item")

        // Profile switcher submenu
        print("🔵 Creating profiles submenu...")
        let profilesMenu = NSMenu()
        if let currentProfile = gestureController?.getActiveProfile(),
           let allProfiles = gestureController?.getAllProfiles() {
            print("🔵 Found \(allProfiles.count) profiles")

            for profile in allProfiles {
                let profileItem = NSMenuItem(title: profile.name, action: #selector(switchProfile(_:)), keyEquivalent: "")
                profileItem.target = self
                // Store UUID as string to avoid Objective-C bridging issues
                profileItem.representedObject = profile.id.uuidString

                // Checkmark for active profile
                if profile.id == currentProfile.id {
                    profileItem.state = .on
                }

                profilesMenu.addItem(profileItem)
                print("🔵 Added profile: \(profile.name)")
            }
        } else {
            print("❌ Could not get profiles")
        }

        let profilesMenuItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        profilesMenuItem.submenu = profilesMenu
        menu.addItem(profilesMenuItem)
        print("🔵 Added profiles menu")

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
        print("🔵 Added quit item")

        print("🔵 Setting menu on statusItem: \(String(describing: statusItem))")
        print("🔵 Menu has \(menu.items.count) items")
		statusItem!.menu = menu
        print("🔵 updateMenu() completed")
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

    @objc private func startCalibration() {
        print("🔵 startCalibration called")
        guard let gestureController = gestureController else {
            print("❌ gestureController is nil")
            return
        }

        print("🔵 Creating CalibrationWindowController")
        // Create and show calibration window
        calibrationWindowController = CalibrationWindowController(gestureController: gestureController)

        print("🔵 Showing window: \(String(describing: calibrationWindowController?.window))")
        calibrationWindowController?.showWindow(nil)
        calibrationWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        print("🔵 Window should be visible now")
    }

    @objc private func switchProfile(_ sender: NSMenuItem) {
        guard let uuidString = sender.representedObject as? String,
              let profileId = UUID(uuidString: uuidString) else {
            print("⚠️ Invalid profile ID")
            return
        }

        gestureController?.switchProfile(id: profileId)
        updateMenu()

        // Show confirmation
        if let profileName = gestureController?.getActiveProfile().name {
            let notification = NSUserNotification()
            notification.title = "Profile Switched"
            notification.informativeText = "Now using profile: \(profileName)"
            NSUserNotificationCenter.default.deliver(notification)
        }
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

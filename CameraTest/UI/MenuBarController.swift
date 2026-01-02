import AppKit

class MenuBarController {

    private var statusItem: NSStatusItem?
    private var gestureController: GestureController?
    private var calibrationWindowController: CalibrationWindowController?

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

        let statusTitle = gestureController?.isActive == true ? "Gesture Control: On" : "Gesture Control: Off"
        let statusMenuItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let toggleTitle = gestureController?.isActive == true ? "Stop Gesture Control" : "Start Gesture Control"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleGestureControl), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let calibrateItem = NSMenuItem(title: "Calibrate Gestures...", action: #selector(startCalibration), keyEquivalent: "")
        calibrateItem.target = self
        menu.addItem(calibrateItem)

        let profilesMenu = NSMenu()
        if let currentProfile = gestureController?.getActiveProfile(),
           let allProfiles = gestureController?.getAllProfiles() {
            for profile in allProfiles {
                let profileItem = NSMenuItem(title: profile.name, action: #selector(switchProfile(_:)), keyEquivalent: "")
                profileItem.target = self
                profileItem.representedObject = profile.id.uuidString

                if profile.id == currentProfile.id {
                    profileItem.state = .on
                }

                profilesMenu.addItem(profileItem)
            }
        }

        let profilesMenuItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        profilesMenuItem.submenu = profilesMenu
        menu.addItem(profilesMenuItem)

        menu.addItem(NSMenuItem.separator())

        let debugTitle = gestureController?.isDebugModeEnabled() == true ? "Debug Mode: On" : "Debug Mode: Off"
        let debugItem = NSMenuItem(title: debugTitle, action: #selector(toggleDebugMode), keyEquivalent: "d")
        debugItem.target = self
        menu.addItem(debugItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

		statusItem!.menu = menu
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
        guard let gestureController = gestureController else {
            return
        }

        calibrationWindowController = CalibrationWindowController(gestureController: gestureController)

        calibrationWindowController?.showWindow(nil)
        calibrationWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func switchProfile(_ sender: NSMenuItem) {
        guard let uuidString = sender.representedObject as? String,
              let profileId = UUID(uuidString: uuidString) else {
            print("⚠️ Invalid profile ID")
            return
        }

        gestureController?.switchProfile(id: profileId)
        updateMenu()

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

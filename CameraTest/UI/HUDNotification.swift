//
//  HUDNotification.swift
//  CameraTest
//
//  Created by Effy on 2025-12-30.
//

import AppKit
import SwiftUI

class HUDNotification {

    private var window: NSWindow?
    private var dismissTimer: Timer?
    private let displayDuration: TimeInterval = 1.5
    private var isShowing = false
    private let hudQueue = DispatchQueue(label: "com.cameratest.hud", qos: .userInteractive)

    static let shared = HUDNotification()

    private init() {}

    // MARK: - Show HUD

    func show(gesture: HandGesture, message: String, volume: Float? = nil) {
        hudQueue.async { [weak self] in
            guard let self = self else { return }

            // Ensure we're not already showing
            DispatchQueue.main.sync {
                self.dismissTimer?.invalidate()
                self.window?.close()
                self.window = nil
                self.isShowing = false
            }

            // Small delay to ensure cleanup
            usleep(10000) // 10ms

            DispatchQueue.main.async {
                self.displayHUD(gesture: gesture, message: message, volume: volume)
                self.scheduleAutoDismiss()
            }
        }
    }

    private func displayHUD(gesture: HandGesture, message: String, volume: Float?) {
        guard !isShowing else { return }
        isShowing = true

        // Create HUD window
        let hudWindow = createHUDWindow()

        // Create content view
        let contentView = HUDContentView(
            icon: gesture.icon,
            message: message,
            volume: volume
        )

        hudWindow.contentView = NSHostingView(rootView: contentView)
        hudWindow.orderFrontRegardless()

        self.window = hudWindow
    }

    private func createHUDWindow() -> NSWindow {
        let screenFrame = NSScreen.main?.frame ?? .zero
        let windowSize = CGSize(width: 200, height: 200)
        let windowOrigin = CGPoint(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.midY - windowSize.height / 2
        )

        let window = NSWindow(
            contentRect: NSRect(origin: windowOrigin, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.ignoresMouseEvents = true
        window.hasShadow = true

        return window
    }

    private func scheduleAutoDismiss() {
        dismissTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.dismissTimer?.invalidate()
            self.dismissTimer = nil
            self.window?.close()
            self.window = nil
            self.isShowing = false
        }
    }
}

// MARK: - HUD Content View

struct HUDContentView: View {
    let icon: String
    let message: String
    let volume: Float?

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.7))
                .shadow(radius: 20)

            VStack(spacing: 16) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundColor(.white)

                // Message
                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                // Volume indicator if applicable
                if let volume = volume {
                    VStack(spacing: 4) {
                        // Progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background bar
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.3))
                                    .frame(height: 4)

                                // Filled bar
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white)
                                    .frame(width: geometry.size.width * CGFloat(volume), height: 4)
                            }
                        }
                        .frame(height: 4)

                        // Volume percentage
                        Text("\(Int(volume * 100))%")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(width: 120)
                }
            }
            .padding(24)
        }
        .frame(width: 200, height: 200)
    }
}

// MARK: - Convenience Methods

extension HUDNotification {
    func showVolume(_ volume: Float, isIncreasing: Bool) {
        let icon = isIncreasing ? "speaker.wave.3.fill" : "speaker.wave.2.fill"
        let message = "Volume"
        show(gesture: .thumbsUp, message: message, volume: volume)
    }

    func showMute(_ isMuted: Bool) {
        let message = isMuted ? "Muted" : "Unmuted"
        show(gesture: .pinch, message: message, volume: nil)
    }

    func showPlayPause() {
        show(gesture: .openPalm, message: "Play/Pause", volume: nil)
    }

    func showSkip(forward: Bool) {
        let gesture: HandGesture = forward ? .swipeRight : .swipeLeft
        let message = forward ? "Next Track" : "Previous Track"
        show(gesture: gesture, message: message, volume: nil)
    }
}

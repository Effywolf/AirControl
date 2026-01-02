//
//  GestureController.swift
//  CameraTest
//
//  Created by Effy on 2025-12-30.
//

import Foundation
import CoreMedia
import CoreImage

class GestureController {
    let cameraService: CameraService
    let gestureService: GestureRecognitionService
    private let audioService: AudioControlService
    private let profileManager: ProfileManager
    private let hudNotification = HUDNotification.shared
    private(set) var isActive: Bool = false
	private var lastGestureTime: [HandGesture: Date] = [:]
	private let debounceInterval: TimeInterval = 0.5

    init() {
        self.cameraService = CameraService()
        self.gestureService = GestureRecognitionService()
        self.audioService = AudioControlService()
        self.profileManager = ProfileManager()

        setupDelegates()

        // Apply active profile on startup
        let activeProfile = profileManager.getActiveProfile()
        gestureService.applyProfile(activeProfile)
        print("📝 Loaded profile: \(activeProfile.name)")
    }

    // MARK: - Setup

    private func setupDelegates() {
        cameraService.delegate = self
        gestureService.delegate = self
    }

    // MARK: - Control

    func start() {
        // Check accessibility permissions first
        if !audioService.checkAccessibilityPermissions() {
            print("⚠️ Accessibility permissions not granted. Please grant permissions in System Settings > Privacy & Security > Accessibility")
            print("⚠️ Media controls (play/pause, next/previous track) will not work without these permissions.")
            print("⚠️ Volume controls will still work.")
        }

        cameraService.requestCameraPermission { [weak self] granted in
            guard granted, let self = self else {
                print("Camera permission denied")
                return
            }

            do {
                try self.cameraService.setupCaptureSession()
                self.cameraService.startCapture()
                self.isActive = true
                print("Gesture control started")
            } catch {
                print("Failed to start gesture control: \(error)")
            }
        }
    }

    func stop() {
        cameraService.stopCapture()
        isActive = false
        print("Gesture control stopped")
    }

    func setDebugMode(_ enabled: Bool) {
        gestureService.debugMode = enabled
        print("Debug mode: \(enabled ? "ON" : "OFF")")
    }

    func isDebugModeEnabled() -> Bool {
        return gestureService.debugMode
    }

    // MARK: - Profile Management

    func switchProfile(id: UUID) {
        do {
            let profile = try profileManager.getProfile(id: id) ?? profileManager.defaultProfile
            try profileManager.setActiveProfile(id: profile.id)
            gestureService.applyProfile(profile)
            print("📝 Switched to profile: \(profile.name)")
        } catch {
            print("❌ Failed to switch profile: \(error)")
        }
    }

    func getActiveProfile() -> GestureProfile {
        return profileManager.getActiveProfile()
    }

    func getAllProfiles() -> [GestureProfile] {
        return profileManager.getAllProfiles()
    }

    func getProfileManager() -> ProfileManager {
        return profileManager
    }

    // MARK: - Gesture Handling

	private func handleGesture(_ gesture: HandGesture) {
		let now = Date()
		if let lastTime = lastGestureTime[gesture],
		   now.timeIntervalSince(lastTime) < debounceInterval {
			return
		}
		lastGestureTime[gesture] = now
		print("Gesture recognized: \(gesture.rawValue)")
		
		switch gesture {
		case .openPalm:
			audioService.playPause()
			hudNotification.show(gesture: gesture, message: "Play/Pause")
			
		case .thumbsUp:
			audioService.increaseVolume()
			let volume = audioService.getVolume()
			hudNotification.show(gesture: gesture, message: "Volume", volume: volume)
			
		case .thumbsDown:
			audioService.decreaseVolume()
			let volume = audioService.getVolume()
			hudNotification.show(gesture: gesture, message: "Volume", volume: volume)
			
		case .swipeRight:
			audioService.nextTrack()
			hudNotification.show(gesture: gesture, message: "Next Track")
			
		case .swipeLeft:
			audioService.previousTrack()
			hudNotification.show(gesture: gesture, message: "Previous Track")
			
		case .pinch:
			audioService.toggleMute()
			let isMuted = audioService.getMuted()
			hudNotification.show(gesture: gesture, message: isMuted ? "Muted" : "Unmuted")
		}
	}
}

// MARK: - CameraServiceDelegate

extension GestureController: CameraServiceDelegate {
	nonisolated func cameraService(_ service: CameraService, didOutput pixelBuffer: CVPixelBuffer) {
		gestureService.processVideoFrame(pixelBuffer)
	}
	
	nonisolated func cameraService(_ service: CameraService, didFailWithError error: Error) {
		print("Camera error: \(error)")
	}
}

// MARK: - GestureRecognitionDelegate

extension GestureController: GestureRecognitionDelegate {
    func gestureRecognized(_ gesture: HandGesture) {
        // Don't trigger actions during calibration
        guard !gestureService.calibrationMode else {
            return
        }
        handleGesture(gesture)
    }
}

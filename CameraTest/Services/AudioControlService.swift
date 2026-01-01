import Foundation
import AppKit
import ISSoundAdditions

class AudioControlService {

	enum TrackDirection {
		case forward
		case backward
	}

	var volumeStep: Float = 0.1

	// Check if accessibility permissions are granted
	func checkAccessibilityPermissions() -> Bool {
		let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
		return AXIsProcessTrustedWithOptions(options as CFDictionary)
	}

	private func hasAccessibilityPermissions() -> Bool {
		return AXIsProcessTrusted()
	}

	func getVolume() -> Float {
		do {
			return try Sound.output.readVolume()
		} catch {
			print("Failed to get volume: \(error)")
			return 0
		}
	}

	func setVolume(_ volume: Float) {
		do {
			try Sound.output.setVolume(max(0, min(1, volume)))
		} catch {
			print("Failed to set volume: \(error)")
		}
	}

	func increaseVolume() {
		Sound.output.increaseVolume(by: volumeStep)
	}

	func decreaseVolume() {
		Sound.output.decreaseVolume(by: volumeStep)
	}

	func getMuted() -> Bool {
		do {
			return try Sound.output.readMute()
		} catch {
			print("Failed to get muted state: \(error)")
			return false
		}
	}

	func setMuted(_ muted: Bool) {
		do {
			try Sound.output.mute(muted)
		} catch {
			print("Failed to set muted state: \(error)")
		}
	}

	func toggleMute() {
		setMuted(!getMuted())
	}
	
	func playPause() {
		guard hasAccessibilityPermissions() else {
			print("⚠️ Accessibility permissions required for play/pause control")
			return
		}
		sendMediaKey(keyCode: NX_KEYTYPE_PLAY)
	}

	func skipTrack(direction: TrackDirection) {
		guard hasAccessibilityPermissions() else {
			print("⚠️ Accessibility permissions required for track control")
			return
		}
		switch direction {
		case .forward:
			sendMediaKey(keyCode: NX_KEYTYPE_NEXT)
		case .backward:
			sendMediaKey(keyCode: NX_KEYTYPE_PREVIOUS)
		}
	}

	func nextTrack() {
		skipTrack(direction: .forward)
	}

	func previousTrack() {
		skipTrack(direction: .backward)
	}
	
	private func sendMediaKey(keyCode: Int32) {
		let data1 = Int((keyCode << 16) | (0xa << 8))

		if let eventDown = NSEvent.otherEvent(
			with: .systemDefined,
			location: NSPoint.zero,
			modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			subtype: 8,
			data1: data1,
			data2: -1
		) {
			eventDown.cgEvent?.post(tap: .cghidEventTap)
		}

		usleep(50000)

		if let eventUp = NSEvent.otherEvent(
			with: .systemDefined,
			location: NSPoint.zero,
			modifierFlags: NSEvent.ModifierFlags(rawValue: 0xb00),
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			subtype: 8,
			data1: data1,
			data2: -1
		) {
			eventUp.cgEvent?.post(tap: .cghidEventTap)
		}
	}
}

private let NX_KEYTYPE_PLAY: Int32 = 16
private let NX_KEYTYPE_NEXT: Int32 = 17
private let NX_KEYTYPE_PREVIOUS: Int32 = 18

import Foundation
import AppKit
import ISSoundAdditions

class AudioControlService {

	private var lastMediaKeyTime: [Int32: Date] = [:]
	private let debounceInterval: TimeInterval = 0.3
	
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
		let now = Date()
		if let lastTime = lastMediaKeyTime[keyCode],
		   now.timeIntervalSince(lastTime) < debounceInterval {
			return
		}
		lastMediaKeyTime[keyCode] = now
		
		let data1Down = Int((keyCode << 16) | (0xa << 8))
		let data1Up = Int((keyCode << 16) | (0xb << 8))
		
		NSEvent.otherEvent(
			with: .systemDefined,
			location: .zero,
			modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			subtype: 8,
			data1: data1Down,
			data2: -1
		)?.cgEvent?.post(tap: .cghidEventTap)
		
		NSEvent.otherEvent(
			with: .systemDefined,
			location: .zero,
			modifierFlags: NSEvent.ModifierFlags(rawValue: 0xb00),
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			subtype: 8,
			data1: data1Up,
			data2: -1
		)?.cgEvent?.post(tap: .cghidEventTap)
	}
}

private let NX_KEYTYPE_PLAY: Int32 = 16
private let NX_KEYTYPE_NEXT: Int32 = 17
private let NX_KEYTYPE_PREVIOUS: Int32 = 18

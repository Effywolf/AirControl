import Foundation
import AppKit
import ISSoundAdditions

class AudioControlService {

	enum TrackDirection {
		case forward
		case backward
	}

	var volumeStep: Float = 0.1

	func getVolume() -> Float {
		return Sound.output.volume
	}

	func setVolume(_ volume: Float) {
		Sound.output.volume = max(0, min(1, volume))
	}

	func increaseVolume() {
		Sound.output.increaseVolume(by: volumeStep)
	}

	func decreaseVolume() {
		Sound.output.decreaseVolume(by: volumeStep)
	}

	func getMuted() -> Bool {
		return Sound.output.isMuted
	}

	func setMuted(_ muted: Bool) {
		Sound.output.isMuted = muted
	}

	func toggleMute() {
		setMuted(!getMuted())
	}
	
	func playPause() {
		sendMediaKey(keyCode: NX_KEYTYPE_PLAY)
	}
	
	func skipTrack(direction: TrackDirection) {
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
		let flags: UInt64 = 0xa00
		
		if let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true) {
			eventDown.flags = CGEventFlags(rawValue: flags)
			eventDown.post(tap: .cghidEventTap)
		}
		
		usleep(50000)
		
		if let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false) {
			eventUp.flags = CGEventFlags(rawValue: flags)
			eventUp.post(tap: .cghidEventTap)
		}
	}
}

private let NX_KEYTYPE_PLAY: Int32 = 16
private let NX_KEYTYPE_NEXT: Int32 = 17
private let NX_KEYTYPE_PREVIOUS: Int32 = 18

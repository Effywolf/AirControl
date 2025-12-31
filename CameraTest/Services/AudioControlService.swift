import Foundation
import CoreAudio
import AudioToolbox
import AppKit

class AudioControlService {
	
	enum TrackDirection {
		case forward
		case backward
	}
	
	var volumeStep: Float = 0.1
	
	private let audioQueue = DispatchQueue(label: "com.cameratest.audio")
	
	private func getDefaultOutputDevice() -> AudioDeviceID? {
		var deviceID = AudioDeviceID(0)
		var size = UInt32(MemoryLayout<AudioDeviceID>.size)
		
		var address = AudioObjectPropertyAddress(
			mSelector: kAudioHardwarePropertyDefaultOutputDevice,
			mScope: kAudioObjectPropertyScopeGlobal,
			mElement: kAudioObjectPropertyElementMain
		)
		
		let status = AudioObjectGetPropertyData(
			AudioObjectID(kAudioObjectSystemObject),
			&address,
			0, nil,
			&size,
			&deviceID
		)
		
		guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
		return deviceID
	}
	
	private func hasVolumeControl(device: AudioDeviceID) -> Bool {
		var address = AudioObjectPropertyAddress(
			mSelector: kAudioDevicePropertyVolumeScalar,
			mScope: kAudioDevicePropertyScopeOutput,
			mElement: 1
		)
		return AudioObjectHasProperty(device, &address)
	}
	
	func getVolume() -> Float {
		audioQueue.sync {
			guard let deviceID = getDefaultOutputDevice() else { return 0 }
			
			var volume: Float32 = 0
			var size = UInt32(MemoryLayout<Float32>.size)
			
			var address = AudioObjectPropertyAddress(
				mSelector: kAudioDevicePropertyVolumeScalar,
				mScope: kAudioDevicePropertyScopeOutput,
				mElement: 1
			)
			
			if !AudioObjectHasProperty(deviceID, &address) {
				address.mElement = kAudioObjectPropertyElementMain
				address.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
			}
			
			let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
			return status == noErr ? volume : 0
		}
	}
	
	func setVolume(_ volume: Float) {
		audioQueue.async {
			guard let deviceID = self.getDefaultOutputDevice() else { return }
			
			var vol = max(0, min(1, volume))
			let size = UInt32(MemoryLayout<Float32>.size)
			
			var address = AudioObjectPropertyAddress(
				mSelector: kAudioDevicePropertyVolumeScalar,
				mScope: kAudioDevicePropertyScopeOutput,
				mElement: 1
			)
			
			if !AudioObjectHasProperty(deviceID, &address) {
				address.mElement = kAudioObjectPropertyElementMain
				address.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
			}
			
			AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &vol)
		}
	}
	
	func increaseVolume() {
		let current = getVolume()
		setVolume(current + volumeStep)
	}
	
	func decreaseVolume() {
		let current = getVolume()
		setVolume(current - volumeStep)
	}
	
	func getMuted() -> Bool {
		audioQueue.sync {
			guard let deviceID = getDefaultOutputDevice() else { return false }
			
			var muted: UInt32 = 0
			var size = UInt32(MemoryLayout<UInt32>.size)
			
			var address = AudioObjectPropertyAddress(
				mSelector: kAudioDevicePropertyMute,
				mScope: kAudioDevicePropertyScopeOutput,
				mElement: kAudioObjectPropertyElementMain
			)
			
			guard AudioObjectHasProperty(deviceID, &address) else { return false }
			
			let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
			return status == noErr && muted != 0
		}
	}
	
	func setMuted(_ muted: Bool) {
		audioQueue.async {
			guard let deviceID = self.getDefaultOutputDevice() else { return }
			
			var value: UInt32 = muted ? 1 : 0
			let size = UInt32(MemoryLayout<UInt32>.size)
			
			var address = AudioObjectPropertyAddress(
				mSelector: kAudioDevicePropertyMute,
				mScope: kAudioDevicePropertyScopeOutput,
				mElement: kAudioObjectPropertyElementMain
			)
			
			guard AudioObjectHasProperty(deviceID, &address) else { return }
			
			AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
		}
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

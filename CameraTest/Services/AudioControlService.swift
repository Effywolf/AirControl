//
//  AudioControlService.swift
//  CameraTest
//
//  Created by Effy on 2025-12-30.
//

import Foundation
import CoreAudio
import ApplicationServices
import AppKit

class AudioControlService {

    enum TrackDirection {
        case forward
        case backward
    }

    private var currentVolume: Float = 0.5
    private var isMuted: Bool = false
    private var volumeBeforeMute: Float = 0.5

    // Volume step size (10% by default)
    var volumeStep: Float = 0.1

    // Thread safety - semaphore to prevent concurrent AppleScript execution
    private let scriptSemaphore = DispatchSemaphore(value: 1)

    // MARK: - Initialization

    init() {
        loadCurrentVolume()
    }

    // MARK: - Volume Control (AppleScript-based for reliability)

    func adjustVolume(delta: Float) {
        // Use cached volume to avoid calling getCurrentVolume() which is slow
        var newVolume = currentVolume + delta
        newVolume = max(0.0, min(1.0, newVolume))
        setVolume(newVolume)
    }

    func increaseVolume() {
        adjustVolume(delta: volumeStep)
    }

    func decreaseVolume() {
        adjustVolume(delta: -volumeStep)
    }

    func setVolume(_ volume: Float) {
        let clampedVolume = max(0.0, min(1.0, volume))
        currentVolume = clampedVolume

        // Convert to 0-100 scale for AppleScript
        let volumePercent = Int(clampedVolume * 100)

        let script = "set volume output volume \(volumePercent)"
        executeAppleScript(script)
    }

    func getCurrentVolume() -> Float {
        loadCurrentVolume()
        return currentVolume
    }

    private func loadCurrentVolume() {
        let script = "output volume of (get volume settings)"

        if let result = executeAppleScript(script),
           let volumeStr = result.stringValue,
           let volumeInt = Int(volumeStr) {
            currentVolume = Float(volumeInt) / 100.0
        }
    }

    // MARK: - Mute Control

    func toggleMute() {
        if isMuted {
            unmute()
        } else {
            mute()
        }
    }

    func mute() {
        if !isMuted {
            volumeBeforeMute = currentVolume
            let script = "set volume with output muted"
            executeAppleScript(script)
            isMuted = true
        }
    }

    func unmute() {
        if isMuted {
            let script = "set volume without output muted"
            executeAppleScript(script)
            isMuted = false
        }
    }

    // MARK: - Media Control

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

    // MARK: - AppleScript Helper

    @discardableResult
    private func executeAppleScript(_ script: String) -> NSAppleEventDescriptor? {
        // Wait for semaphore with timeout to prevent concurrent execution
        let timeout = DispatchTime.now() + .milliseconds(100)
        guard scriptSemaphore.wait(timeout: timeout) == .success else {
            print("AppleScript timeout - skipping")
            return nil
        }

        defer { scriptSemaphore.signal() }

        var result: NSAppleEventDescriptor?

        // AppleScript MUST run on main thread
        if Thread.isMainThread {
            result = executeAppleScriptOnMainThread(script)
        } else {
            DispatchQueue.main.sync {
                result = executeAppleScriptOnMainThread(script)
            }
        }

        return result
    }

    private func executeAppleScriptOnMainThread(_ script: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&error)

        if let error = error {
            print("AppleScript error: \(error)")
            return nil
        }

        return result
    }

    // MARK: - Media Key Simulation

    private func sendMediaKey(keyCode: Int32) {
        let flags = 0xa00 // Media key flags

        // Key down event
        if let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true) {
            eventDown.flags = CGEventFlags(rawValue: CGEventFlags.RawValue(flags))
            eventDown.post(tap: .cghidEventTap)
        }

        // Small delay
        usleep(50000) // 50ms

        // Key up event
        if let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false) {
            eventUp.flags = CGEventFlags(rawValue: CGEventFlags.RawValue(flags))
            eventUp.post(tap: .cghidEventTap)
        }
    }
}

// Media key codes
private let NX_KEYTYPE_PLAY: Int32 = 16
private let NX_KEYTYPE_NEXT: Int32 = 17
private let NX_KEYTYPE_PREVIOUS: Int32 = 18
private let NX_KEYTYPE_FAST: Int32 = 19
private let NX_KEYTYPE_REWIND: Int32 = 20

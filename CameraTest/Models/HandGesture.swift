//
//  HandGesture.swift
//  CameraTest
//
//  Created by Effy on 2025-12-30.
//

import Foundation

enum HandGesture: String, CaseIterable, Codable {
    case openPalm = "Open Palm"
    case thumbsUp = "Thumbs Up"
    case thumbsDown = "Thumbs Down"
    case swipeLeft = "Swipe Left"
    case swipeRight = "Swipe Right"
    case pinch = "Pinch"

    var description: String {
        switch self {
        case .openPalm:
            return "Play/Pause"
        case .thumbsUp:
            return "Volume Up"
        case .thumbsDown:
            return "Volume Down"
        case .swipeLeft:
            return "Previous Track"
        case .swipeRight:
            return "Next Track"
        case .pinch:
            return "Toggle Mute"
        }
    }

    var icon: String {
        switch self {
        case .openPalm:
            return "hand.raised.fill"
        case .thumbsUp:
            return "hand.thumbsup.fill"
        case .thumbsDown:
            return "hand.thumbsdown.fill"
        case .swipeLeft:
            return "arrow.left"
        case .swipeRight:
            return "arrow.right"
        case .pinch:
            return "speaker.slash.fill"
        }
    }
}

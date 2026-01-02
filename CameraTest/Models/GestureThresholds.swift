//
//  GestureThresholds.swift
//  CameraTest
//

import Foundation
import CoreGraphics

struct GestureThresholds: Codable, Equatable {
    // MARK: - Global Thresholds

    /// Time interval between gesture recognitions (prevents rapid re-triggering)
    var gestureCooldown: TimeInterval

    /// Minimum confidence threshold for Vision framework detection
    var gestureConfidenceThreshold: Float

    /// Number of consecutive frames a gesture must be held for stability
    var requiredHoldFrames: Int

    // MARK: - Swipe Thresholds

    /// Minimum horizontal distance threshold for swipe detection (as percentage of screen width)
    var swipeDistanceThreshold: CGFloat

    /// Time window for swipe gesture completion
    var swipeTimeWindow: TimeInterval

    /// Maximum vertical movement allowed during horizontal swipe
    var swipeVerticalTolerance: CGFloat

    /// Minimum number of position samples required for swipe detection
    var swipeMinFrames: Int

    // MARK: - Open Palm Thresholds

    /// Minimum offset for finger extension above wrist
    var palmFingerExtensionOffset: CGFloat

    /// Minimum distance between index and middle fingers for spread detection
    var palmFingerSpreadMinIndex: CGFloat

    /// Minimum distance between middle and ring fingers for spread detection
    var palmFingerSpreadMinMiddle: CGFloat

    /// Maximum horizontal movement threshold (prevents false positives during swipes)
    var palmHorizontalMovementThreshold: CGFloat

    // MARK: - Thumbs Up/Down Thresholds

    /// Minimum distance for thumb extension from hand center
    var thumbExtensionDistance: CGFloat

    /// Vertical delta threshold between thumb and MCP joint for up/down detection
    var thumbVerticalDelta: CGFloat

    // MARK: - Pinch Thresholds

    /// Maximum distance between thumb tip and index finger tip for pinch detection
    var pinchDistance: CGFloat

    /// Minimum extension threshold for thumb and index finger
    var pinchFingerExtensionMin: CGFloat

    /// Offset threshold for other fingers (should be curled)
    var pinchOtherFingersOffset: CGFloat

    // MARK: - Default Values

    /// Factory default thresholds based on current hardcoded values
    static var defaults: GestureThresholds {
        return GestureThresholds(
            // Global
            gestureCooldown: 2.0,
            gestureConfidenceThreshold: 0.5,
            requiredHoldFrames: 2,

            // Swipe
            swipeDistanceThreshold: 0.20,      // 20% of screen width
            swipeTimeWindow: 0.7,              // 700ms
            swipeVerticalTolerance: 0.10,      // 10% vertical movement allowed
            swipeMinFrames: 6,                 // Minimum position history samples

            // Open Palm
            palmFingerExtensionOffset: 0.05,   // Fingers above wrist
            palmFingerSpreadMinIndex: 0.04,    // Index-middle spread
            palmFingerSpreadMinMiddle: 0.04,   // Middle-ring spread
            palmHorizontalMovementThreshold: 0.05, // Max horizontal movement

            // Thumbs Up/Down
            thumbExtensionDistance: 0.08,      // Thumb extension from center
            thumbVerticalDelta: 0.08,          // Vertical difference threshold

            // Pinch
            pinchDistance: 0.05,               // Max thumb-index distance
            pinchFingerExtensionMin: 0.03,     // Minimum finger extension
            pinchOtherFingersOffset: 0.05      // Other fingers curl threshold
        )
    }

    // MARK: - Validation

    /// Validates that all thresholds are within reasonable bounds
    func validate() -> Bool {
        // Global thresholds
        guard gestureCooldown >= 0.1 && gestureCooldown <= 10.0 else { return false }
        guard gestureConfidenceThreshold >= 0.1 && gestureConfidenceThreshold <= 1.0 else { return false }
        guard requiredHoldFrames >= 1 && requiredHoldFrames <= 10 else { return false }

        // Swipe thresholds
        guard swipeDistanceThreshold >= 0.05 && swipeDistanceThreshold <= 0.50 else { return false }
        guard swipeTimeWindow >= 0.2 && swipeTimeWindow <= 2.0 else { return false }
        guard swipeVerticalTolerance >= 0.05 && swipeVerticalTolerance <= 0.30 else { return false }
        guard swipeMinFrames >= 3 && swipeMinFrames <= 20 else { return false }

        // Open Palm thresholds
        guard palmFingerExtensionOffset >= 0.01 && palmFingerExtensionOffset <= 0.20 else { return false }
        guard palmFingerSpreadMinIndex >= 0.01 && palmFingerSpreadMinIndex <= 0.15 else { return false }
        guard palmFingerSpreadMinMiddle >= 0.01 && palmFingerSpreadMinMiddle <= 0.15 else { return false }
        guard palmHorizontalMovementThreshold >= 0.01 && palmHorizontalMovementThreshold <= 0.20 else { return false }

        // Thumbs thresholds
        guard thumbExtensionDistance >= 0.02 && thumbExtensionDistance <= 0.20 else { return false }
        guard thumbVerticalDelta >= 0.02 && thumbVerticalDelta <= 0.20 else { return false }

        // Pinch thresholds
        guard pinchDistance >= 0.01 && pinchDistance <= 0.15 else { return false }
        guard pinchFingerExtensionMin >= 0.01 && pinchFingerExtensionMin <= 0.10 else { return false }
        guard pinchOtherFingersOffset >= 0.01 && pinchOtherFingersOffset <= 0.15 else { return false }

        return true
    }
}

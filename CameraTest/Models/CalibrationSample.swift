//
//  CalibrationSample.swift
//  CameraTest
//

import Foundation
import CoreGraphics
import Vision

// MARK: - CalibrationSample

/// Represents a single hand pose sample captured during calibration
struct CalibrationSample {
    /// The gesture this sample represents
    let gesture: HandGesture

    /// Timestamp when the sample was captured
    let timestamp: Date

    /// All hand joint points detected by Vision framework
    let handPoints: [VNHumanHandPoseObservation.JointName: CGPoint]

    /// Confidence score from Vision framework (0.0 to 1.0)
    let confidence: Float

    // MARK: - Convenience Accessors

    /// Gets a specific joint point, returns nil if not found
    func point(for jointName: VNHumanHandPoseObservation.JointName) -> CGPoint? {
        return handPoints[jointName]
    }

    /// Checks if all required joints are present for the gesture type
    var hasRequiredJoints: Bool {
        // At minimum, we need wrist and fingertips
        guard let _ = handPoints[.wrist],
              let _ = handPoints[.thumbTip],
              let _ = handPoints[.indexTip],
              let _ = handPoints[.middleTip],
              let _ = handPoints[.ringTip],
              let _ = handPoints[.littleTip] else {
            return false
        }
        return true
    }
}

// MARK: - CalibrationSession

/// Manages collection of samples for a single gesture during calibration
class CalibrationSession {
    /// The gesture being calibrated
    let gesture: HandGesture

    /// Collected samples
    private(set) var samples: [CalibrationSample] = []

    /// Number of samples required for this gesture
    let requiredSamples: Int

    /// Minimum acceptable confidence for samples
    let minimumConfidence: Float

    /// Whether enough valid samples have been collected
    var isComplete: Bool {
        return samples.count >= requiredSamples
    }

    /// Progress as a percentage (0.0 to 1.0)
    var progress: Float {
        return min(1.0, Float(samples.count) / Float(requiredSamples))
    }

    // MARK: - Initialization

    init(gesture: HandGesture, requiredSamples: Int = 10, minimumConfidence: Float = 0.5) {
        self.gesture = gesture
        self.requiredSamples = requiredSamples
        self.minimumConfidence = minimumConfidence
    }

    // MARK: - Sample Management

    /// Adds a sample if it meets quality requirements
    /// - Returns: true if sample was added, false if rejected
    @discardableResult
    func addSample(_ sample: CalibrationSample) -> Bool {
        // Validate sample quality
        guard sample.gesture == gesture else { return false }
        guard sample.confidence >= minimumConfidence else { return false }
        guard sample.hasRequiredJoints else { return false }

        // Don't accept more samples than needed
        guard samples.count < requiredSamples else { return false }

        samples.append(sample)
        return true
    }

    /// Removes the most recent sample
    func removeLastSample() {
        samples.removeLast()
    }

    /// Clears all collected samples
    func reset() {
        samples.removeAll()
    }

    /// Gets samples with timestamps within a specified time window
    func samplesInTimeWindow(_ duration: TimeInterval) -> [CalibrationSample] {
        let cutoffTime = Date().addingTimeInterval(-duration)
        return samples.filter { $0.timestamp >= cutoffTime }
    }
}

// MARK: - SerializableCalibrationData

/// Simplified calibration data for storage (doesn't store full hand point data)
struct SerializableCalibrationData: Codable {
    let gesture: HandGesture
    let sampleCount: Int
    let averageConfidence: Float
    let calibrationDate: Date

    /// Key metrics extracted from samples (gesture-specific)
    let metrics: [String: Double]

    init(from session: CalibrationSession, metrics: [String: Double]) {
        self.gesture = session.gesture
        self.sampleCount = session.samples.count
        self.averageConfidence = session.samples.isEmpty ? 0 :
            session.samples.map { $0.confidence }.reduce(0, +) / Float(session.samples.count)
        self.calibrationDate = Date()
        self.metrics = metrics
    }
}

//
//  CalibrationEngine.swift
//  CameraTest
//

import Foundation
import CoreGraphics
import Vision

// MARK: - CalibrationEngine

class CalibrationEngine {
    // MARK: - Main Calibration Method

    /// Computes optimal thresholds from all collected calibration sessions
    func computeThresholds(from sessions: [HandGesture: CalibrationSession]) -> GestureThresholds {
        var thresholds = GestureThresholds.defaults

        // Calibrate each gesture type if we have enough samples
        for (gesture, session) in sessions {
            guard session.samples.count >= 5 else {
                print("⚠️ Insufficient samples for \(gesture.rawValue) (\(session.samples.count)/5), using defaults")
                continue
            }

            switch gesture {
            case .openPalm:
                calibrateOpenPalm(samples: session.samples, thresholds: &thresholds)
            case .thumbsUp:
                calibrateThumbs(samples: session.samples, isUp: true, thresholds: &thresholds)
            case .thumbsDown:
                calibrateThumbs(samples: session.samples, isUp: false, thresholds: &thresholds)
            case .swipeLeft, .swipeRight:
                calibrateSwipe(samples: session.samples, thresholds: &thresholds)
            case .pinch:
                calibratePinch(samples: session.samples, thresholds: &thresholds)
            }
        }

        // Global calibration from all samples
        calibrateGlobalSettings(from: sessions, thresholds: &thresholds)

        return thresholds
    }

    // MARK: - Per-Gesture Calibration Algorithms

    private func calibrateOpenPalm(samples: [CalibrationSample], thresholds: inout GestureThresholds) {
        var fingerExtensions: [CGFloat] = []
        var indexMiddleSpreads: [CGFloat] = []
        var middleRingSpreads: [CGFloat] = []

        for sample in samples {
            guard let wrist = sample.point(for: .wrist),
                  let indexTip = sample.point(for: .indexTip),
                  let middleTip = sample.point(for: .middleTip),
                  let ringTip = sample.point(for: .ringTip) else {
                continue
            }

            // Measure finger extension heights above wrist
            let extensions = [
                sample.point(for: .thumbTip),
                sample.point(for: .indexTip),
                sample.point(for: .middleTip),
                sample.point(for: .ringTip),
                sample.point(for: .littleTip)
            ].compactMap { $0 }
             .map { $0.y - wrist.y }

            if let minExtension = extensions.min() {
                fingerExtensions.append(minExtension)
            }

            // Measure finger spreads
            let indexMiddleSpread = distance(indexTip, middleTip)
            let middleRingSpread = distance(middleTip, ringTip)

            indexMiddleSpreads.append(indexMiddleSpread)
            middleRingSpreads.append(middleRingSpread)
        }

        // Calculate thresholds at 70% of mean (captures most samples)
        if !fingerExtensions.isEmpty {
            let meanExtension = fingerExtensions.mean()
            let stdExtension = fingerExtensions.standardDeviation()
            let threshold = meanExtension - (0.5 * stdExtension)
            thresholds.palmFingerExtensionOffset = clamp(threshold, min: 0.01, max: 0.20)
        }

        if !indexMiddleSpreads.isEmpty {
            let meanSpread = indexMiddleSpreads.mean()
            thresholds.palmFingerSpreadMinIndex = clamp(meanSpread * 0.7, min: 0.01, max: 0.15)
        }

        if !middleRingSpreads.isEmpty {
            let meanSpread = middleRingSpreads.mean()
            thresholds.palmFingerSpreadMinMiddle = clamp(meanSpread * 0.7, min: 0.01, max: 0.15)
        }
    }

    private func calibrateThumbs(samples: [CalibrationSample], isUp: Bool, thresholds: inout GestureThresholds) {
        var thumbDeltas: [CGFloat] = []
        var thumbExtensions: [CGFloat] = []

        for sample in samples {
            guard let thumbTip = sample.point(for: .thumbTip),
                  let thumbIP = sample.point(for: .thumbIP),
                  let indexMCP = sample.point(for: .indexMCP),
                  let middleMCP = sample.point(for: .middleMCP),
                  let ringMCP = sample.point(for: .ringMCP),
                  let littleMCP = sample.point(for: .littleMCP) else {
                continue
            }

            // Calculate thumb vertical delta from hand center
            let averageMCPY = (indexMCP.y + middleMCP.y + ringMCP.y + littleMCP.y) / 4
            let thumbDelta = abs(thumbTip.y - averageMCPY)
            thumbDeltas.append(thumbDelta)

            // Calculate thumb extension
            let thumbExt = distance(thumbTip, thumbIP)
            thumbExtensions.append(thumbExt)
        }

        // Set threshold at 80% of mean delta (to capture most samples)
        if !thumbDeltas.isEmpty {
            let meanDelta = thumbDeltas.mean()
            let stdDelta = thumbDeltas.standardDeviation()
            let threshold = meanDelta - (0.3 * stdDelta)
            thresholds.thumbVerticalDelta = clamp(threshold, min: 0.02, max: 0.20)
        }

        if !thumbExtensions.isEmpty {
            let meanExtension = thumbExtensions.mean()
            thresholds.thumbExtensionDistance = clamp(meanExtension * 0.8, min: 0.02, max: 0.20)
        }
    }

    private func calibrateSwipe(samples: [CalibrationSample], thresholds: inout GestureThresholds) {
        // Build trajectories from samples
        let sortedSamples = samples.sorted { $0.timestamp < $1.timestamp }
        guard sortedSamples.count >= 3 else { return }

        var horizontalDistances: [CGFloat] = []
        var verticalDistances: [CGFloat] = []
        var durations: [TimeInterval] = []

        // Analyze movement between first and last position in each sample sequence
        for i in stride(from: 0, to: sortedSamples.count - 2, by: 3) {
            guard i + 2 < sortedSamples.count,
                  let firstWrist = sortedSamples[i].point(for: .wrist),
                  let lastWrist = sortedSamples[i + 2].point(for: .wrist) else {
                continue
            }

            let horizontalDist = abs(lastWrist.x - firstWrist.x)
            let verticalDist = abs(lastWrist.y - firstWrist.y)
            let duration = sortedSamples[i + 2].timestamp.timeIntervalSince(sortedSamples[i].timestamp)

            horizontalDistances.append(horizontalDist)
            verticalDistances.append(verticalDist)
            durations.append(duration)
        }

        // Set distance threshold at 70% of average observed distance
        if !horizontalDistances.isEmpty {
            let avgDistance = horizontalDistances.mean()
            thresholds.swipeDistanceThreshold = clamp(avgDistance * 0.7, min: 0.05, max: 0.50)
        }

        // Set time window to average duration * 1.5 (allow some variation)
        if !durations.isEmpty {
            let avgDuration = durations.mean()
            thresholds.swipeTimeWindow = clamp(avgDuration * 1.5, min: 0.2, max: 2.0)
        }

        // Set vertical tolerance at 120% of max observed vertical movement
        if !verticalDistances.isEmpty {
            let maxVertical = verticalDistances.max() ?? 0.10
            thresholds.swipeVerticalTolerance = clamp(maxVertical * 1.2, min: 0.05, max: 0.30)
        }
    }

    private func calibratePinch(samples: [CalibrationSample], thresholds: inout GestureThresholds) {
        var pinchDistances: [CGFloat] = []
        var thumbExtensions: [CGFloat] = []
        var indexExtensions: [CGFloat] = []

        for sample in samples {
            guard let thumbTip = sample.point(for: .thumbTip),
                  let indexTip = sample.point(for: .indexTip),
                  let thumbIP = sample.point(for: .thumbIP),
                  let indexDIP = sample.point(for: .indexDIP) else {
                continue
            }

            // Measure thumb-index distance
            let pinchDist = distance(thumbTip, indexTip)
            pinchDistances.append(pinchDist)

            // Measure finger extensions
            let thumbExt = distance(thumbTip, thumbIP)
            let indexExt = distance(indexTip, indexDIP)

            thumbExtensions.append(thumbExt)
            indexExtensions.append(indexExt)
        }

        // Set threshold slightly above mean pinch distance (allow some tolerance)
        if !pinchDistances.isEmpty {
            let meanDistance = pinchDistances.mean()
            let stdDistance = pinchDistances.standardDeviation()
            let threshold = meanDistance + (0.5 * stdDistance)
            thresholds.pinchDistance = clamp(threshold, min: 0.01, max: 0.15)
        }

        // Set finger extension at 80% of observed values
        if !thumbExtensions.isEmpty && !indexExtensions.isEmpty {
            let minExtension = min(thumbExtensions.mean(), indexExtensions.mean())
            thresholds.pinchFingerExtensionMin = clamp(minExtension * 0.8, min: 0.01, max: 0.10)
        }
    }

    private func calibrateGlobalSettings(from sessions: [HandGesture: CalibrationSession], thresholds: inout GestureThresholds) {
        // Calculate average confidence across all samples
        var allConfidences: [Float] = []

        for session in sessions.values {
            allConfidences.append(contentsOf: session.samples.map { $0.confidence })
        }

        if !allConfidences.isEmpty {
            let meanConfidence = allConfidences.reduce(0, +) / Float(allConfidences.count)
            let minConfidence = allConfidences.min() ?? 0.5

            // Set confidence threshold at 90% of minimum observed (to be inclusive)
            let threshold = minConfidence * 0.9
            thresholds.gestureConfidenceThreshold = Float(clamp(CGFloat(threshold), min: 0.1, max: 1.0))
        }

        // Keep other global settings at defaults (cooldown, hold frames)
        // These are user preference rather than hand-specific
    }

    // MARK: - Helper Methods

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        return Swift.max(minValue, Swift.min(maxValue, value))
    }

    private func clamp(_ value: TimeInterval, min minValue: TimeInterval, max maxValue: TimeInterval) -> TimeInterval {
        return Swift.max(minValue, Swift.min(maxValue, value))
    }

    private func clamp(_ value: Int, min minValue: Int, max maxValue: Int) -> Int {
        return Swift.max(minValue, Swift.min(maxValue, value))
    }

    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - Statistical Extensions

extension Array where Element == CGFloat {
    func mean() -> CGFloat {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / CGFloat(count)
    }

    func standardDeviation() -> CGFloat {
        guard !isEmpty else { return 0 }
        let avg = mean()
        let variance = map { pow($0 - avg, 2) }.mean()
        return sqrt(variance)
    }

    func median() -> CGFloat {
        guard !isEmpty else { return 0 }
        let sorted = self.sorted()
        let mid = count / 2
        if count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            return sorted[mid]
        }
    }
}

extension Array where Element == TimeInterval {
    func mean() -> TimeInterval {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}

//
//  GestureRecognitionService.swift
//  CameraTest
//
//  Created by Effy on 2025-12-30.
//

@preconcurrency import Vision
import CoreImage
import Combine
import Foundation

protocol GestureRecognitionDelegate: AnyObject {
    func gestureRecognized(_ gesture: HandGesture)
}

protocol CalibrationDelegate: AnyObject {
    func didCaptureSample(_ sample: CalibrationSample)
}

class GestureRecognitionService: NSObject, @unchecked Sendable {

    nonisolated(unsafe) weak var delegate: GestureRecognitionDelegate?
    nonisolated(unsafe) weak var calibrationDelegate: CalibrationDelegate?

    nonisolated(unsafe) private var handPoseRequest: VNDetectHumanHandPoseRequest?
    private let requestQueue = DispatchQueue(label: "com.cameratest.gesture.recognition")

    nonisolated(unsafe) private var currentThresholds: GestureThresholds = .defaults
    nonisolated(unsafe) var calibrationMode: Bool = false
    nonisolated(unsafe) var calibrationTargetGesture: HandGesture?

    nonisolated(unsafe) var debugMode: Bool = false

    nonisolated(unsafe) private var lastGestureTime: Date?
    nonisolated(unsafe) private var gestureHoldFrames: [HandGesture: Int] = [:]

    nonisolated(unsafe) private var handPositionHistory: [(position: CGPoint, timestamp: Date)] = []
    private let maxHistoryCount = 10

    override init() {
        super.init()
        setupHandPoseRequest()
    }

    // MARK: setup

    private func setupHandPoseRequest() {
        handPoseRequest = VNDetectHumanHandPoseRequest()
        handPoseRequest?.maximumHandCount = 1
    }

    // MARK: profile management

    func applyProfile(_ profile: GestureProfile) {
        currentThresholds = profile.thresholds
        if debugMode {
            print("📝 Applied profile: \(profile.name)")
        }
    }

    func getCurrentThresholds() -> GestureThresholds {
        return currentThresholds
    }

    // MARK: process video frame

	nonisolated func processVideoFrame(_ pixelBuffer: CVPixelBuffer) {
		guard let request = handPoseRequest else {
			return
		}
		
		let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
		
		requestQueue.async { [weak self] in
			do {
				try handler.perform([request])
				self?.handleHandPoseResults(request.results)
			} catch {
				print("Hand pose detection failed: \(error)")
			}
		}
	}

    // MARK: handle results

    private func handleHandPoseResults(_ results: [VNHumanHandPoseObservation]?) {
        guard let observation = results?.first else {
            handPositionHistory.removeAll()
            gestureHoldFrames.removeAll()
            return
        }

        if calibrationMode {
            handleCalibrationFrame(observation)
            return
        }

        if let lastTime = lastGestureTime,
           Date().timeIntervalSince(lastTime) < currentThresholds.gestureCooldown {
            return
        }

        if let gesture = detectGesture(from: observation) {
            gestureHoldFrames[gesture, default: 0] += 1

            if debugMode {
                print("Detected \(gesture.rawValue) - Hold frames: \(gestureHoldFrames[gesture, default: 0])/\(currentThresholds.requiredHoldFrames)")
            }

            for key in gestureHoldFrames.keys where key != gesture {
                gestureHoldFrames[key] = 0
            }

            if gestureHoldFrames[gesture, default: 0] >= currentThresholds.requiredHoldFrames {
                lastGestureTime = Date()
                gestureHoldFrames.removeAll()

                if gesture == .swipeLeft || gesture == .swipeRight {
                    handPositionHistory.removeAll()
                }

                if debugMode {
                    print("✅ Gesture confirmed: \(gesture.rawValue)")
                }

                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.gestureRecognized(gesture)
                }
            }
        } else {
            gestureHoldFrames.removeAll()
        }
    }

    // MARK: gesture detection

    private func detectGesture(from observation: VNHumanHandPoseObservation) -> HandGesture? {
        guard let handPoints = try? observation.recognizedPoints(.all) else {
            return nil
        }

        if debugMode, let wrist = handPoints[.wrist], let indexTip = handPoints[.indexTip] {
            print("🔍 Wrist Y: \(wrist.location.y), IndexTip Y: \(indexTip.location.y)")
        }

        if let swipeGesture = detectSwipe(handPoints: handPoints) {
            return swipeGesture
        }

        if detectOpenPalm(handPoints: handPoints) {
            return .openPalm
        }

        if detectPinch(handPoints: handPoints) {
            return .pinch
        }

        if let thumbGesture = detectThumbsUpDown(handPoints: handPoints) {
            return thumbGesture
        }

        return nil
    }

    // MARK: open palm detection

    private func detectOpenPalm(handPoints: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        guard let wrist = handPoints[.wrist],
              let thumbTip = handPoints[.thumbTip],
              let indexTip = handPoints[.indexTip],
              let middleTip = handPoints[.middleTip],
              let ringTip = handPoints[.ringTip],
              let littleTip = handPoints[.littleTip],
              wrist.confidence > currentThresholds.gestureConfidenceThreshold else {
            if debugMode {
                print("❌ Open Palm: Failed confidence check")
            }
            return false
        }

        if handPositionHistory.count >= 3 {
            let recentPositions = handPositionHistory.suffix(3)
            let firstPos = recentPositions.first!.position
            let lastPos = recentPositions.last!.position
            let horizontalMovement = abs(lastPos.x - firstPos.x)

            if horizontalMovement > currentThresholds.palmHorizontalMovementThreshold {
                if debugMode {
                    print("❌ Open Palm: Hand moving horizontally (likely swipe)")
                }
                return false
            }
        }

        let fingertips = [thumbTip, indexTip, middleTip, ringTip, littleTip]

        let allExtended = fingertips.allSatisfy { tip in
            tip.confidence > currentThresholds.gestureConfidenceThreshold &&
            tip.location.y > wrist.location.y + currentThresholds.palmFingerExtensionOffset
        }

        let fingerSpread = distance(indexTip.location, middleTip.location) > currentThresholds.palmFingerSpreadMinIndex &&
                          distance(middleTip.location, ringTip.location) > currentThresholds.palmFingerSpreadMinMiddle

        if debugMode {
            print("🖐 Open Palm: extended=\(allExtended), spread=\(fingerSpread)")
        }

        return allExtended && fingerSpread
    }

    // MARK: thumbs up/down detection

    private func detectThumbsUpDown(handPoints: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> HandGesture? {
        guard let thumbTip = handPoints[.thumbTip],
              let thumbIP = handPoints[.thumbIP],
              let indexMCP = handPoints[.indexMCP],
              let middleMCP = handPoints[.middleMCP],
              let ringMCP = handPoints[.ringMCP],
              let littleMCP = handPoints[.littleMCP],
              thumbTip.confidence > currentThresholds.gestureConfidenceThreshold else {
            return nil
        }

        let indexCurled = (handPoints[.indexTip]?.location.y ?? 0) < indexMCP.location.y
        let middleCurled = (handPoints[.middleTip]?.location.y ?? 0) < middleMCP.location.y
        let ringCurled = (handPoints[.ringTip]?.location.y ?? 0) < ringMCP.location.y
        let littleCurled = (handPoints[.littleTip]?.location.y ?? 0) < littleMCP.location.y

        let fingersCurled = indexCurled && middleCurled && ringCurled && littleCurled

        if debugMode {
            print("👍 Thumbs: curled=[\(indexCurled), \(middleCurled), \(ringCurled), \(littleCurled)]")
        }

        if !fingersCurled {
            return nil
        }

        let thumbExtended = distance(thumbTip.location, thumbIP.location) > currentThresholds.thumbExtensionDistance

        if debugMode {
            print("👍 Thumb extended: \(thumbExtended)")
        }

        if !thumbExtended {
            return nil
        }

        let averageMCPY = (indexMCP.location.y + middleMCP.location.y + ringMCP.location.y + littleMCP.location.y) / 4
        let thumbDelta = thumbTip.location.y - averageMCPY

        if debugMode {
            print("👍 Thumb Y: \(thumbTip.location.y), Avg MCP Y: \(averageMCPY), Delta: \(thumbDelta)")
        }

        if thumbDelta > currentThresholds.thumbVerticalDelta {
            if debugMode {
                print("✅ Thumbs UP detected")
            }
            return .thumbsUp
        } else if thumbDelta < -currentThresholds.thumbVerticalDelta {
            if debugMode {
                print("✅ Thumbs DOWN detected")
            }
            return .thumbsDown
        }

        if debugMode {
            print("⚠️ Thumb gesture ambiguous (delta too small)")
        }

        return nil
    }

    // MARK: swipe detection

    private func detectSwipe(handPoints: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> HandGesture? {
        guard let wrist = handPoints[.wrist],
              wrist.confidence > currentThresholds.gestureConfidenceThreshold else {
            return nil
        }

        let now = Date()
        let position = wrist.location

        handPositionHistory.append((position: position, timestamp: now))

        handPositionHistory = handPositionHistory.filter { now.timeIntervalSince($0.timestamp) < currentThresholds.swipeTimeWindow }

        if handPositionHistory.count < currentThresholds.swipeMinFrames {
            return nil
        }

        let firstPosition = handPositionHistory.first!.position
        let lastPosition = handPositionHistory.last!.position
        let horizontalDistance = lastPosition.x - firstPosition.x
        let verticalDistance = abs(lastPosition.y - firstPosition.y)

        if verticalDistance > currentThresholds.swipeVerticalTolerance {
            return nil
        }

        if abs(horizontalDistance) > currentThresholds.swipeDistanceThreshold {
            if horizontalDistance > 0 {
                return .swipeRight
            } else {
                return .swipeLeft
            }
        }

        return nil
    }

    // MARK: pinch detection

    private func detectPinch(handPoints: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        guard let thumbTip = handPoints[.thumbTip],
              let indexTip = handPoints[.indexTip],
              let thumbIP = handPoints[.thumbIP],
              let indexDIP = handPoints[.indexDIP],
              let middleTip = handPoints[.middleTip],
              let ringTip = handPoints[.ringTip],
              let littleTip = handPoints[.littleTip],
              thumbTip.confidence > currentThresholds.gestureConfidenceThreshold,
              indexTip.confidence > currentThresholds.gestureConfidenceThreshold else {
            return false
        }

        let pinchDistance = distance(thumbTip.location, indexTip.location)

        let thumbExtended = distance(thumbTip.location, thumbIP.location) > currentThresholds.pinchFingerExtensionMin
        let indexExtended = distance(indexTip.location, indexDIP.location) > currentThresholds.pinchFingerExtensionMin

        let wrist = handPoints[.wrist]
        let otherFingersCurled = (middleTip.location.y < (wrist?.location.y ?? 0) + currentThresholds.pinchOtherFingersOffset) ||
                                 (ringTip.location.y < (wrist?.location.y ?? 0) + currentThresholds.pinchOtherFingersOffset) ||
                                 (littleTip.location.y < (wrist?.location.y ?? 0) + currentThresholds.pinchOtherFingersOffset)

        return pinchDistance < currentThresholds.pinchDistance && thumbExtended && indexExtended && otherFingersCurled
    }

    // MARK: helper functions

    private func distance(_ point1: CGPoint, _ point2: CGPoint) -> CGFloat {
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        return sqrt(dx * dx + dy * dy)
    }

    // MARK: calibration support

    private func handleCalibrationFrame(_ observation: VNHumanHandPoseObservation) {
        guard let calibrationDelegate = calibrationDelegate,
              let targetGesture = calibrationTargetGesture else {
            return
        }

        guard let allPoints = try? observation.recognizedPoints(.all) else {
            return
        }

        var handPoints: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
        for (jointName, recognizedPoint) in allPoints {
            handPoints[jointName] = recognizedPoint.location
        }

        let sample = CalibrationSample(
            gesture: targetGesture,
            timestamp: Date(),
            handPoints: handPoints,
            confidence: observation.confidence
        )

        DispatchQueue.main.async {
            calibrationDelegate.didCaptureSample(sample)
        }
    }

    // MARK: configuration (legacy)

    @available(*, deprecated, message: "Use applyProfile() instead")
    func setGestureCooldown(_ cooldown: TimeInterval) {
        currentThresholds.gestureCooldown = cooldown
    }

    @available(*, deprecated, message: "Use applyProfile() instead")
    func setConfidenceThreshold(_ threshold: Float) {
        currentThresholds.gestureConfidenceThreshold = threshold
    }
}

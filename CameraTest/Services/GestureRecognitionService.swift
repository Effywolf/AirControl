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

class GestureRecognitionService: NSObject, @unchecked Sendable {

    nonisolated(unsafe) weak var delegate: GestureRecognitionDelegate?

    nonisolated(unsafe) private var handPoseRequest: VNDetectHumanHandPoseRequest?
    private let requestQueue = DispatchQueue(label: "com.cameratest.gesture.recognition")

    // Debug mode
    nonisolated(unsafe) var debugMode: Bool = false

    nonisolated(unsafe) private var lastGestureTime: Date?
    nonisolated(unsafe) private var gestureCooldown: TimeInterval = 2.0
    nonisolated(unsafe) private var gestureConfidenceThreshold: Float = 0.5
    nonisolated(unsafe) private var gestureHoldFrames: [HandGesture: Int] = [:]
    private let requiredHoldFrames = 2

    // Swipe gesture tracking
    nonisolated(unsafe) private var handPositionHistory: [(position: CGPoint, timestamp: Date)] = []
    private let maxHistoryCount = 10
    private let swipeDistanceThreshold: CGFloat = 0.20 // 20% of screen width (more movement needed)
    private let swipeTimeWindow: TimeInterval = 0.7

    override init() {
        super.init()
        setupHandPoseRequest()
    }

    // MARK: - Setup

    private func setupHandPoseRequest() {
        handPoseRequest = VNDetectHumanHandPoseRequest()
        handPoseRequest?.maximumHandCount = 1 // track one hand at a time
    }

    // MARK: - Process Video Frame

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

    // MARK: - Handle Results

    private func handleHandPoseResults(_ results: [VNHumanHandPoseObservation]?) {
        guard let observation = results?.first else {
            // No hand detected - reset tracking
            handPositionHistory.removeAll()
            gestureHoldFrames.removeAll()
            return
        }

        // cooldown period
        if let lastTime = lastGestureTime,
           Date().timeIntervalSince(lastTime) < gestureCooldown {
            return
        }

        // Detect gestures
        if let gesture = detectGesture(from: observation) {
            // Increment hold count for this gesture
            gestureHoldFrames[gesture, default: 0] += 1

            if debugMode {
                print("Detected \(gesture.rawValue) - Hold frames: \(gestureHoldFrames[gesture, default: 0])/\(requiredHoldFrames)")
            }

            // Reset other gestures
            for key in gestureHoldFrames.keys where key != gesture {
                gestureHoldFrames[key] = 0
            }

            // Check if gesture has been held long enough
            if gestureHoldFrames[gesture, default: 0] >= requiredHoldFrames {
                lastGestureTime = Date()
                gestureHoldFrames.removeAll()

                // Clear swipe history when swipe gesture is confirmed
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
            // No clear gesture detected, reset hold counts
            gestureHoldFrames.removeAll()
        }
    }

    // MARK: - Gesture Detection

    private func detectGesture(from observation: VNHumanHandPoseObservation) -> HandGesture? {
        guard let handPoints = try? observation.recognizedPoints(.all) else {
            return nil
        }

        // Debug: Print coordinate info
        if debugMode, let wrist = handPoints[.wrist], let indexTip = handPoints[.indexTip] {
            print("🔍 Wrist Y: \(wrist.location.y), IndexTip Y: \(indexTip.location.y)")
        }

        // gestures in priority order
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

    // MARK: - Open Palm Detection

    private func detectOpenPalm(handPoints: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        guard let wrist = handPoints[.wrist],
              let thumbTip = handPoints[.thumbTip],
              let indexTip = handPoints[.indexTip],
              let middleTip = handPoints[.middleTip],
              let ringTip = handPoints[.ringTip],
              let littleTip = handPoints[.littleTip],
              wrist.confidence > gestureConfidenceThreshold else {
            if debugMode {
                print("❌ Open Palm: Failed confidence check")
            }
            return false
        }

        // Don't detect open palm if hand is moving horizontally (likely a swipe)
        if handPositionHistory.count >= 3 {
            let recentPositions = handPositionHistory.suffix(3)
            let firstPos = recentPositions.first!.position
            let lastPos = recentPositions.last!.position
            let horizontalMovement = abs(lastPos.x - firstPos.x)

            if horizontalMovement > 0.08 {
                if debugMode {
                    print("❌ Open Palm: Hand moving horizontally (likely swipe)")
                }
                return false
            }
        }

        // All fingertips should be extended and above the wrist
        let fingertips = [thumbTip, indexTip, middleTip, ringTip, littleTip]

        // Check if all fingers are extended (tips above wrist)
        // Vision coordinates: Y increases upward (0=bottom, 1=top)
        let allExtended = fingertips.allSatisfy { tip in
            tip.confidence > gestureConfidenceThreshold &&
            tip.location.y > wrist.location.y + 0.08 // Tips should be significantly higher
        }

        // Check fingers are spread out (distance between adjacent fingers)
        let fingerSpread = distance(indexTip.location, middleTip.location) > 0.06 &&
                          distance(middleTip.location, ringTip.location) > 0.05

        if debugMode {
            print("🖐 Open Palm: extended=\(allExtended), spread=\(fingerSpread)")
        }

        return allExtended && fingerSpread
    }

    // MARK: - Thumbs Up/Down Detection

    private func detectThumbsUpDown(handPoints: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> HandGesture? {
        guard let thumbTip = handPoints[.thumbTip],
              let thumbIP = handPoints[.thumbIP],
              let indexMCP = handPoints[.indexMCP],
              let middleMCP = handPoints[.middleMCP],
              let ringMCP = handPoints[.ringMCP],
              let littleMCP = handPoints[.littleMCP],
              thumbTip.confidence > gestureConfidenceThreshold else {
            return nil
        }

        // Check if other fingers are curled (tips below MCPs = curled)
        // Vision coordinates: Y increases upward, so curled fingers have tip.y < MCP.y
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

        // Check thumb orientation
        let thumbExtended = distance(thumbTip.location, thumbIP.location) > 0.05

        if debugMode {
            print("👍 Thumb extended: \(thumbExtended)")
        }

        if !thumbExtended {
            return nil
        }

        // Determine if thumbs up or down based on thumb position relative to hand
        // Vision coordinates: Y increases upward (0=bottom, 1=top)
        let averageMCPY = (indexMCP.location.y + middleMCP.location.y + ringMCP.location.y + littleMCP.location.y) / 4
        let thumbDelta = thumbTip.location.y - averageMCPY

        if debugMode {
            print("👍 Thumb Y: \(thumbTip.location.y), Avg MCP Y: \(averageMCPY), Delta: \(thumbDelta)")
        }

        // Reduced threshold for better detection (0.08 instead of 0.1)
        if thumbDelta > 0.08 {
            // Thumb is above hand center (larger Y) = thumbs up
            if debugMode {
                print("✅ Thumbs UP detected")
            }
            return .thumbsUp
        } else if thumbDelta < -0.08 {
            // Thumb is below hand center (smaller Y) = thumbs down
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

    // MARK: - Swipe Detection

    private func detectSwipe(handPoints: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> HandGesture? {
        guard let wrist = handPoints[.wrist],
              wrist.confidence > gestureConfidenceThreshold else {
            return nil
        }

        let now = Date()
        let position = wrist.location

        // Add to history
        handPositionHistory.append((position: position, timestamp: now))

        // Keep only recent history within time window
        handPositionHistory = handPositionHistory.filter { now.timeIntervalSince($0.timestamp) < swipeTimeWindow }

        if handPositionHistory.count < 6 {
            return nil
        }

        // Calculate horizontal movement
        let firstPosition = handPositionHistory.first!.position
        let lastPosition = handPositionHistory.last!.position
        let horizontalDistance = lastPosition.x - firstPosition.x
        let verticalDistance = abs(lastPosition.y - firstPosition.y)

        // Swipe should be mostly horizontal
        if verticalDistance > 0.10 {
            return nil // Too much vertical movement
        }

        // Detect swipe direction
        if abs(horizontalDistance) > swipeDistanceThreshold {
            // Don't clear history here - let it be cleared when gesture is confirmed
            // or when hand is no longer detected

            if horizontalDistance > 0 {
                return .swipeRight
            } else {
                return .swipeLeft
            }
        }

        return nil
    }

    // MARK: - Pinch Detection

    private func detectPinch(handPoints: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        guard let thumbTip = handPoints[.thumbTip],
              let indexTip = handPoints[.indexTip],
              let thumbIP = handPoints[.thumbIP],
              let indexDIP = handPoints[.indexDIP],
              let middleTip = handPoints[.middleTip],
              let ringTip = handPoints[.ringTip],
              let littleTip = handPoints[.littleTip],
              thumbTip.confidence > gestureConfidenceThreshold,
              indexTip.confidence > gestureConfidenceThreshold else {
            return false
        }

        // Check if thumb and index finger tips are close together (stricter threshold)
        let pinchDistance = distance(thumbTip.location, indexTip.location)

        // Also check that the fingers are actually extended toward each other
        let thumbExtended = distance(thumbTip.location, thumbIP.location) > 0.03
        let indexExtended = distance(indexTip.location, indexDIP.location) > 0.03

        // Other fingers should be relatively curled or not extended
        let wrist = handPoints[.wrist]
        let otherFingersCurled = (middleTip.location.y < (wrist?.location.y ?? 0) + 0.15) ||
                                 (ringTip.location.y < (wrist?.location.y ?? 0) + 0.15) ||
                                 (littleTip.location.y < (wrist?.location.y ?? 0) + 0.15)

        // Stricter pinch distance and require other fingers not fully extended
        return pinchDistance < 0.05 && thumbExtended && indexExtended && otherFingersCurled
    }

    // MARK: - Helper Functions

    private func distance(_ point1: CGPoint, _ point2: CGPoint) -> CGFloat {
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        return sqrt(dx * dx + dy * dy)
    }

    // MARK: - Configuration

    func setGestureCooldown(_ cooldown: TimeInterval) {
        self.gestureCooldown = cooldown
    }

    func setConfidenceThreshold(_ threshold: Float) {
        self.gestureConfidenceThreshold = threshold
    }
}

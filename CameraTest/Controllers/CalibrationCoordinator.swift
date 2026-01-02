import Foundation
import Combine

// MARK: - CalibrationState

enum CalibrationState: Equatable {
    case notStarted
    case welcome
    case transition(HandGesture) // Pause before starting next gesture
    case calibratingGesture(HandGesture)
    case processing
    case review
    case completed
}

// MARK: - CalibrationError

enum CalibrationError: Error, LocalizedError {
    case cameraNotAvailable
	/// gesture, collected, required
    case insufficientSamples(HandGesture, Int, Int)
    case invalidThresholds
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .cameraNotAvailable:
            return "Camera is not available for calibration"
        case .insufficientSamples(let gesture, let collected, let required):
            return "Insufficient samples for \(gesture.rawValue): \(collected)/\(required)"
        case .invalidThresholds:
            return "Computed thresholds are invalid"
        case .saveFailed(let error):
            return "Failed to save profile: \(error.localizedDescription)"
        }
    }
}

// MARK: - CalibrationCoordinator

class CalibrationCoordinator: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var currentState: CalibrationState = .notStarted
    @Published private(set) var currentGesture: HandGesture?
    @Published private(set) var currentSession: CalibrationSession?
    @Published private(set) var error: CalibrationError?
    @Published var profileName: String = ""

    // MARK: - Dependencies

    private let gestureService: GestureRecognitionService
    private let cameraService: CameraService
    private let profileManager: ProfileManager
    private let calibrationEngine: CalibrationEngine

    // MARK: - State

    private var sessions: [HandGesture: CalibrationSession] = [:]
    private var gestureOrder: [HandGesture] = [.openPalm, .thumbsUp, .thumbsDown, .swipeLeft, .swipeRight, .pinch]
    private var currentGestureIndex: Int = 0
    private var computedThresholds: GestureThresholds?
    private var savedProfile: GestureProfile?
    private let samplesPerGesture: Int
    private let minimumConfidence: Float

    // MARK: - Initialization

    init(
        gestureService: GestureRecognitionService,
        cameraService: CameraService,
        profileManager: ProfileManager,
        samplesPerGesture: Int = 10,
        minimumConfidence: Float = 0.5
    ) {
        self.gestureService = gestureService
        self.cameraService = cameraService
        self.profileManager = profileManager
        self.calibrationEngine = CalibrationEngine()
        self.samplesPerGesture = samplesPerGesture
        self.minimumConfidence = minimumConfidence

        for gesture in gestureOrder {
            sessions[gesture] = CalibrationSession(
                gesture: gesture,
                requiredSamples: samplesPerGesture,
                minimumConfidence: minimumConfidence
            )
        }
    }

    // MARK: - Calibration Flow Control

    func start(profileName: String) {
        self.profileName = profileName
        currentState = .welcome
    }

    func beginCalibration() {
        // first gesture
        currentGestureIndex = 0
        moveToNextGesture()
    }

    func moveToNextGesture() {
        guard currentGestureIndex < gestureOrder.count else {
            // gestures calibrated, move to processing
            processCalibrationData()
            return
        }

        let gesture = gestureOrder[currentGestureIndex]
        currentGesture = gesture
        currentSession = sessions[gesture]

        // transition screen
        currentState = .transition(gesture)
        print("⏸️ Get ready for: \(gesture.rawValue)")

        // wait 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.startCalibratingGesture(gesture)
        }
    }

    private func startCalibratingGesture(_ gesture: HandGesture) {
        currentState = .calibratingGesture(gesture)

        // enable calibration mode in gesture service
        gestureService.calibrationMode = true
        gestureService.calibrationTargetGesture = gesture
        gestureService.calibrationDelegate = self

        print("📸 Starting calibration for \(gesture.rawValue)")
    }

    func skipCurrentGesture() {
        print("⏭️ Skipping \(currentGesture?.rawValue ?? "unknown") - will use defaults")
        currentGestureIndex += 1
        moveToNextGesture()
    }

    func recalibrateGesture(_ gesture: HandGesture) {
        if let session = sessions[gesture] {
            session.reset()
        }

        if let index = gestureOrder.firstIndex(of: gesture) {
            currentGestureIndex = index
            moveToNextGesture()
        }
    }

    func finishCalibration() {
        // disable calibration mode
        gestureService.calibrationMode = false
        gestureService.calibrationTargetGesture = nil
        gestureService.calibrationDelegate = nil

        currentState = .completed
        print("✅ Calibration completed")
    }

    func cancel() {
        // disable calibration mode
        gestureService.calibrationMode = false
        gestureService.calibrationTargetGesture = nil
        gestureService.calibrationDelegate = nil

        // reset all sessions
        for session in sessions.values {
            session.reset()
        }

        currentState = .notStarted
        print("❌ Calibration cancelled")
    }

    // MARK: - Processing

    private func processCalibrationData() {
        currentState = .processing
        print("🔄 Processing calibration data...")

        // disable calibration mode
        gestureService.calibrationMode = false
        gestureService.calibrationTargetGesture = nil

        // compute thresholds on background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let thresholds = self.calibrationEngine.computeThresholds(from: self.sessions)

            DispatchQueue.main.async {
                self.computedThresholds = thresholds
                self.currentState = .review
                print("✅ Thresholds computed")
            }
        }
    }

    func saveProfile() {
        guard let thresholds = computedThresholds else {
            error = .invalidThresholds
            return
        }

        do {
            let profile = try profileManager.createProfile(
                name: profileName.isEmpty ? "My Profile" : profileName,
                thresholds: thresholds
            )

            savedProfile = profile
            print("💾 Profile saved: \(profile.name)")

            try profileManager.setActiveProfile(id: profile.id)
            print("📝 Profile set as active")

        } catch {
            self.error = .saveFailed(error)
            print("❌ Failed to save profile: \(error)")
        }
    }

    // MARK: - Session Management

    func getSessions() -> [HandGesture: CalibrationSession] {
        return sessions
    }

    func getSession(for gesture: HandGesture) -> CalibrationSession? {
        return sessions[gesture]
    }

    func getCurrentProgress() -> Float {
        guard let session = currentSession else { return 0 }
        return session.progress
    }

    func canProceedToNext() -> Bool {
        guard let session = currentSession else { return false }
        return session.isComplete
    }

    func proceedToNext() {
        currentGestureIndex += 1
        moveToNextGesture()
    }

    // MARK: - Getters

    func getComputedThresholds() -> GestureThresholds? {
        return computedThresholds
    }

    func getSavedProfile() -> GestureProfile? {
        return savedProfile
    }

    func getGestureOrder() -> [HandGesture] {
        return gestureOrder
    }
}

// MARK: - CalibrationDelegate

extension CalibrationCoordinator: CalibrationDelegate {
    func didCaptureSample(_ sample: CalibrationSample) {
        guard let session = sessions[sample.gesture],
              sample.gesture == currentGesture else {
            return
        }

        let added = session.addSample(sample)

        if added {
            print("📸 Sample captured for \(sample.gesture.rawValue): \(session.samples.count)/\(session.requiredSamples)")

            // update current session to trigger UI refresh
            DispatchQueue.main.async { [weak self] in
                self?.currentSession = session
            }

            if session.isComplete {
                print("✅ \(sample.gesture.rawValue) calibration complete")

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.proceedToNext()
                }
            }
        }
    }
}

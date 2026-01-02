import AppKit
import Combine

class CalibrationWindowController: NSWindowController {

    private var coordinator: CalibrationCoordinator?
    private var cancellables = Set<AnyCancellable>()
    private let titleLabel = NSTextField(labelWithString: "Gesture Calibration")
    private let instructionLabel = NSTextField(labelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "0/10 samples")
    private let progressIndicator = NSProgressIndicator()
    private let nextButton = NSButton(title: "Next", target: nil, action: nil)
    private let skipButton = NSButton(title: "Skip", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let profileNameField = NSTextField()
    private let startButton = NSButton(title: "Start Calibration", target: nil, action: nil)

    convenience init(gestureController: GestureController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Calibrate Gestures"
        window.center()

        self.init(window: window)
        self.shouldCascadeWindows = false
        window.delegate = self

        let coord = CalibrationCoordinator(
            gestureService: gestureController.gestureService,
            cameraService: gestureController.cameraService,
            profileManager: gestureController.getProfileManager()
        )
        self.coordinator = coord

        setupUI()
        setupObservers()
        showWelcomeScreen()
    }

    private func setupObservers() {
        guard let coordinator = coordinator else { return }

        coordinator.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleStateChange(state)
            }
            .store(in: &cancellables)

        coordinator.$currentSession
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                self?.updateProgress(session: session)
            }
            .store(in: &cancellables)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Title
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 20, y: 440, width: 460, height: 30)
        contentView.addSubview(titleLabel)

        // Instructions
        instructionLabel.font = NSFont.systemFont(ofSize: 14)
        instructionLabel.alignment = .center
        instructionLabel.maximumNumberOfLines = 0
        instructionLabel.frame = NSRect(x: 20, y: 250, width: 460, height: 170)
        contentView.addSubview(instructionLabel)

        // Profile name field (only shown on welcome screen)
        profileNameField.placeholderString = "Profile Name (optional)"
        profileNameField.frame = NSRect(x: 150, y: 210, width: 200, height: 24)
        profileNameField.isHidden = true
        contentView.addSubview(profileNameField)

        // Progress indicator
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 10
        progressIndicator.doubleValue = 0
        progressIndicator.frame = NSRect(x: 100, y: 170, width: 300, height: 20)
        progressIndicator.isHidden = true
        contentView.addSubview(progressIndicator)

        // Progress label
        progressLabel.alignment = .center
        progressLabel.frame = NSRect(x: 20, y: 140, width: 460, height: 20)
        progressLabel.isHidden = true
        contentView.addSubview(progressLabel)

        // Start button (only shown on welcome screen)
        startButton.target = self
        startButton.action = #selector(startCalibrationClicked)
        startButton.frame = NSRect(x: 200, y: 90, width: 100, height: 32)
        startButton.bezelStyle = .rounded
        startButton.isHidden = true
        contentView.addSubview(startButton)

        // Next button
        nextButton.target = self
        nextButton.action = #selector(nextClicked)
        nextButton.frame = NSRect(x: 380, y: 20, width: 100, height: 32)
        nextButton.bezelStyle = .rounded
        nextButton.isHidden = true
        contentView.addSubview(nextButton)

        // Skip button
        skipButton.target = self
        skipButton.action = #selector(skipClicked)
        skipButton.frame = NSRect(x: 270, y: 20, width: 100, height: 32)
        skipButton.bezelStyle = .rounded
        skipButton.isHidden = true
        contentView.addSubview(skipButton)

        // Cancel button
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.frame = NSRect(x: 20, y: 20, width: 100, height: 32)
        cancelButton.bezelStyle = .rounded
        contentView.addSubview(cancelButton)
    }

    private func showWelcomeScreen() {
        instructionLabel.stringValue = """
        Welcome to Gesture Calibration!

        This wizard will help you train the gesture recognition
        system to your hand. You'll perform each gesture 10 times.

        Gestures to calibrate:
        • Open Palm  • Thumbs Up  • Thumbs Down
        • Swipe Left  • Swipe Right  • Pinch

        Enter a profile name or leave blank for default.
        """

        profileNameField.isHidden = false
        startButton.isHidden = false
        progressIndicator.isHidden = true
        progressLabel.isHidden = true
        nextButton.isHidden = true
        skipButton.isHidden = true
    }

    private func handleStateChange(_ state: CalibrationState) {
        switch state {
        case .notStarted, .welcome:
            showWelcomeScreen()

        case .transition(let gesture):
            showTransitionScreen(for: gesture)

        case .calibratingGesture(let gesture):
            showCalibrationScreen(for: gesture)

        case .processing:
            showProcessingScreen()

        case .review:
            showReviewScreen()

        case .completed:
            showCompletedScreen()
        }
    }

    private func showTransitionScreen(for gesture: HandGesture) {
        titleLabel.stringValue = "Get Ready!"
        instructionLabel.stringValue = """
        Next Gesture: \(gesture.rawValue)

        Take a moment to relax your hand.

        Starting in 3 seconds...

        \(gesture.description)
        """

        profileNameField.isHidden = true
        startButton.isHidden = true
        progressIndicator.isHidden = true
        progressLabel.isHidden = true
        nextButton.isHidden = true
        skipButton.isHidden = false
    }

    private func showCalibrationScreen(for gesture: HandGesture) {
        titleLabel.stringValue = "Calibrating: \(gesture.rawValue)"

        // Different instructions for swipes vs static gestures
        let instructions: String
        if gesture == .swipeLeft || gesture == .swipeRight {
            instructions = """
            Perform the swipe gesture repeatedly.
            Move your hand naturally - don't hold steady!

            Gesture: \(gesture.rawValue)
            Action: \(gesture.description)

            The system will capture your movement pattern.
            Perform the swipe 10 times at your natural speed.
            """
        } else {
            instructions = """
            Perform the gesture and hold it steady.
            The system will automatically capture samples.

            Gesture: \(gesture.rawValue)
            Action: \(gesture.description)

            Make sure your hand is visible to the camera
            and perform the gesture naturally.
            """
        }

        instructionLabel.stringValue = instructions

        profileNameField.isHidden = true
        startButton.isHidden = true
        progressIndicator.isHidden = false
        progressLabel.isHidden = false
        nextButton.isHidden = false
        skipButton.isHidden = false
        nextButton.isEnabled = false
    }

    private func showProcessingScreen() {
        titleLabel.stringValue = "Processing..."
        instructionLabel.stringValue = "Computing optimal thresholds based on your samples.\nThis will only take a moment."

        progressIndicator.isHidden = true
        progressLabel.isHidden = true
        nextButton.isHidden = true
        skipButton.isHidden = true
    }

    private func showReviewScreen() {
        titleLabel.stringValue = "Calibration Complete!"
        instructionLabel.stringValue = """
        Your personalized profile has been created.

        The gesture recognition system has been tuned
        to your hand size and movement patterns.

        Your profile will be saved and activated.
        """

        nextButton.isHidden = false
        nextButton.isEnabled = true
        nextButton.title = "Save & Finish"
        skipButton.isHidden = true
    }

    private func showCompletedScreen() {
        coordinator?.saveProfile()

        let alert = NSAlert()
        alert.messageText = "Calibration Saved!"
        alert.informativeText = "Your personalized gesture profile is now active."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()

        close()
    }

    private func updateProgress(session: CalibrationSession?) {
        guard let session = session else { return }

        progressIndicator.doubleValue = Double(session.samples.count)
        progressLabel.stringValue = "\(session.samples.count)/\(session.requiredSamples) samples"

        if session.isComplete {
            nextButton.isEnabled = true
        }
    }

    // MARK: - Actions

    @objc private func startCalibrationClicked() {
        let profileName = profileNameField.stringValue.isEmpty ? "My Profile" : profileNameField.stringValue
        coordinator?.start(profileName: profileName)
        coordinator?.beginCalibration()
    }

    @objc private func nextClicked() {
        // if in review state, finish calibration instead of proceeding to next gesture
        if coordinator?.currentState == .review {
            coordinator?.finishCalibration()
        } else {
            coordinator?.proceedToNext()
        }
    }

    @objc private func skipClicked() {
        coordinator?.skipCurrentGesture()
    }

    @objc private func cancelClicked() {
        coordinator?.cancel()
        close()
    }
}

// MARK: - NSWindowDelegate

extension CalibrationWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Cancel calibration if window is closed while in progress
        if let coordinator = coordinator,
           coordinator.currentState != .completed && coordinator.currentState != .notStarted {
            coordinator.cancel()
        }

        // Clean up
        cancellables.removeAll()
    }
}

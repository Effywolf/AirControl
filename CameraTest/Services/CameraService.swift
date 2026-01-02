import AVFoundation
import Combine
import CoreImage

protocol CameraServiceDelegate: AnyObject {
	nonisolated func cameraService(_ service: CameraService, didOutput pixelBuffer: CVPixelBuffer)
	nonisolated func cameraService(_ service: CameraService, didFailWithError error: Error)
}

class CameraService: NSObject, @unchecked Sendable {

    nonisolated(unsafe) weak var delegate: CameraServiceDelegate?

    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.cameratest.camera.session")
    private var videoDataOutput: AVCaptureVideoDataOutput?

    private(set) var isRunning = false

    enum CameraError: Error {
        case cameraNotAvailable
        case inputCreationFailed
        case outputCreationFailed
        case permissionDenied
    }

    override init() {
        super.init()
    }

    // MARK: permission handling

    func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    // MARK: session configuration

    func setupCaptureSession() throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw CameraError.cameraNotAvailable
        }

        guard let input = try? AVCaptureDeviceInput(device: camera) else {
            throw CameraError.inputCreationFailed
        }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.captureSession.beginConfiguration()

            if self.captureSession.canSetSessionPreset(.vga640x480) {
                self.captureSession.sessionPreset = .vga640x480
            }

            if self.captureSession.canAddInput(input) {
                self.captureSession.addInput(input)
            }

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.cameratest.camera.output"))
            videoOutput.alwaysDiscardsLateVideoFrames = true

            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]

            if self.captureSession.canAddOutput(videoOutput) {
                self.captureSession.addOutput(videoOutput)
                self.videoDataOutput = videoOutput
            }

            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }

            self.captureSession.commitConfiguration()
        }
    }

    // MARK: session control

    func startCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.isRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.isRunning = true
            }
        }
    }

    func stopCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }
}

// MARK: avcapturevideodataoutputsamplebufferdelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
	nonisolated func captureOutput(_ output: AVCaptureOutput,
								   didOutput sampleBuffer: CMSampleBuffer,
								   from connection: AVCaptureConnection) {
		guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
		delegate?.cameraService(self, didOutput: pixelBuffer)
	}
}

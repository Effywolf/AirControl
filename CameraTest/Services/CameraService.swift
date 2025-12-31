//
//  CameraService.swift
//  CameraTest
//
//  Created by Effy on 2025-12-30.
//

import AVFoundation
import Combine

protocol CameraServiceDelegate: AnyObject {
    func cameraService(_ service: CameraService, didOutput sampleBuffer: CMSampleBuffer)
    func cameraService(_ service: CameraService, didFailWithError error: Error)
}

class CameraService: NSObject, @unchecked Sendable {

    weak var delegate: CameraServiceDelegate?

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

    // MARK: - Permission Handling

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

    // MARK: - Session Configuration

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

            // Set session preset for optimal hand tracking (640x480 @ 30fps)
            if self.captureSession.canSetSessionPreset(.vga640x480) {
                self.captureSession.sessionPreset = .vga640x480
            }

            // Add input
            if self.captureSession.canAddInput(input) {
                self.captureSession.addInput(input)
            }

            // Configure video output
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.cameratest.camera.output"))
            videoOutput.alwaysDiscardsLateVideoFrames = true

            // Set pixel format for Vision framework compatibility
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]

            if self.captureSession.canAddOutput(videoOutput) {
                self.captureSession.addOutput(videoOutput)
                self.videoDataOutput = videoOutput
            }

            // Set frame rate to 30fps
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }

            self.captureSession.commitConfiguration()
        }
    }

    // MARK: - Session Control

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

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
	func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
		delegate?.cameraService(self, didOutput: sampleBuffer)
	}
	
	func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
	}
}

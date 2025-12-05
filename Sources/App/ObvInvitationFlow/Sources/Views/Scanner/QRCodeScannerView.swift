/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import ObvAppTypes
import SwiftUI
import OSLog
@preconcurrency import AVFoundation
import ObvAppCoreConstants


struct QRCodeScannerView: UIViewControllerRepresentable {
    
    /// A binding to transfer the first successfully scanned `OlvidURL` to the parent view.
    ///
    /// - Important:
    ///   - This binding is **only updated once**—after the first successful scan.
    ///   - It remains `nil` if `doScanOlvidURL` is `false`, ensuring no unintended updates.
    @Binding var scannedOlvidURL: OlvidURL?
    let doScanOlvidURL: Bool
    
    func makeUIViewController(context: Context) -> QRCodeScannerViewController {
        let cr = QRCodeScannerViewController()
        cr.delegate = context.coordinator
        return cr
    }
    
    func updateUIViewController(_ uiViewController: QRCodeScannerViewController, context: Context) {
        context.coordinator.doScanOlvidURL = doScanOlvidURL
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(scannedOlvidURL: $scannedOlvidURL, doScanOlvidURL: doScanOlvidURL)
    }
}


// MARK: - Coordinator

final class Coordinator: NSObject, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    
    @Binding var scannedOlvidURL: OlvidURL?
    fileprivate(set) var doScanOlvidURL: Bool
    
    init(scannedOlvidURL: Binding<OlvidURL?>, doScanOlvidURL: Bool) {
        self._scannedOlvidURL = scannedOlvidURL
        self.doScanOlvidURL = doScanOlvidURL
    }
    
    @MainActor func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {

//        guard captureSession.isRunning else { return }
        
        guard scannedOlvidURL == nil else { return }
        
        guard doScanOlvidURL else { return }
        
        guard !metadataObjects.isEmpty else { return }
        
        let readableCodeObjects = metadataObjects.compactMap { $0 as? AVMetadataMachineReadableCodeObject }
        
        guard !readableCodeObjects.isEmpty else { return }
        
        let qrCodeObjects = readableCodeObjects.filter { $0.type == AVMetadataObject.ObjectType.qr }
        
        guard !qrCodeObjects.isEmpty else { return }
        
        guard qrCodeObjects.count == 1 else { return }
        
        guard let stringValue = qrCodeObjects.first!.stringValue else { return }
        
        guard let url = URL(string: stringValue) else { return }

        guard let olvidURL = OlvidURL(urlRepresentation: url) else { return }
        
//        captureSession.stopRunning()
        
        UINotificationFeedbackGenerator()
            .notificationOccurred(.success)

        withAnimation {
            scannedOlvidURL = olvidURL
        }
    }
}


// MARK: - QRCodeScannerViewController

final class QRCodeScannerViewController: UIViewController {
        
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: QRCodeScannerViewController.self))
    private let captureSession = AVCaptureSession()
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer!
    
    var delegate: AVCaptureMetadataOutputObjectsDelegate?
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        captureSession.stopRunning()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.insetsLayoutMarginsFromSafeArea = false
        
        let deviceDiscoverySession: AVCaptureDevice.DiscoverySession
        if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
            deviceDiscoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: nil,
                position: .unspecified)
        } else {
            deviceDiscoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: nil,
                position: .back)
        }
        

        guard let captureDevice = deviceDiscoverySession.devices.first else {
            // This happens in the simulator
            os_log("Failed to load capture device (note that this is expected when using a simulator)", log: log, type: .fault)
            return
        }
        
        // Configure the input of the caputre session
        
        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            captureSession.addInput(input)
        } catch let error {
            os_log("Failed to capture device input: %@", log: log, type: .error, error.localizedDescription)
            return
        }

        // Configure the output of the caputre session

        do {
            let captureMetadataOutput = AVCaptureMetadataOutput()
            captureSession.addOutput(captureMetadataOutput)
            captureMetadataOutput.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
            captureMetadataOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.qr]
        }
        
        // Initialize the video preview layer and add it as a sublayer of our view
        
        do {
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            videoPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
            videoPreviewLayer.frame = self.view.bounds
            self.view.layer.addSublayer(videoPreviewLayer)
        }

        if AVCaptureDevice.authorizationStatus(for: AVMediaType.video) == .authorized {
            self.captureSession.startRunning()
        }
        
    }
    
    private enum CaptureAutorisationError: Error {
        case restricted
        case denied
        
        var alertTitle: String {
            switch self {
            case .restricted:
                return String(localizedInThisBundle: "VIDEO_CAPTURE_RESTRICTED_TITLE")
            case .denied:
                return String(localizedInThisBundle: "VIDEO_CAPTURE_DENIED_TITLE")
            }
        }

        var alertMessage: String {
            switch self {
            case .restricted:
                return String(localizedInThisBundle: "VIDEO_CAPTURE_RESTRICTED_MESSAGE")
            case .denied:
                return String(localizedInThisBundle: "VIDEO_CAPTURE_DENIED_MESSAGE")
            }
        }

    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !captureSession.isRunning {
            
            #if DEBUG
            // We do not request any authorization in the simulator
            #else
            switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
            case .authorized:
                self.captureSession.startRunning()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted {
                        Task { @MainActor [weak self] in
                            self?.captureSession.startRunning()
                        }
                    }
                }
            case .restricted:
                showCaptureAutorisationError(captureAutorisationError: .restricted)
            case .denied:
                showCaptureAutorisationError(captureAutorisationError: .denied)
            @unknown default:
                assertionFailure()
                self.captureSession.startRunning()
            }
            #endif
                        
        }
            
    }
    
    
    private func showCaptureAutorisationError(captureAutorisationError: CaptureAutorisationError) {
        
        let alert = UIAlertController(
            title: captureAutorisationError.alertTitle,
            message: captureAutorisationError.alertMessage,
            preferredStyle: .alert
        )
        
        let okAction = UIAlertAction(title: "OK", style: .default)

        alert.addAction(okAction)
        
        self.present(alert, animated: true)
        
    }
    
    
    private func adaptVideoPreviewLayerSizeAndOrientation() {
        // Adapt the video preview layer size
        guard let videoPreviewLayer = self.videoPreviewLayer else { return }
        videoPreviewLayer.frame = self.view.bounds
        // Adapt the video preview layer to the device orientation
        if let connection = videoPreviewLayer.connection {
            if connection.isVideoOrientationSupported {
                switch UIDevice.current.orientation {
                case .portrait, .unknown, .faceUp:
                    connection.videoOrientation = .portrait
                case .portraitUpsideDown, .faceDown:
                    connection.videoOrientation = .portraitUpsideDown
                case .landscapeLeft:
                    connection.videoOrientation = .landscapeRight // Weird, but correction on iOS 13.3
                case .landscapeRight:
                    connection.videoOrientation = .landscapeLeft // Weird, but correction on iOS 13.3
                @unknown default:
                    assertionFailure()
                    connection.videoOrientation = .portrait
                }
            }
        }
    }

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        adaptVideoPreviewLayerSizeAndOrientation()
    }
    
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        adaptVideoPreviewLayerSizeAndOrientation()
    }
}

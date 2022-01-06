/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

import UIKit
import os.log
import AVFoundation

final class QRCodeScannerViewController: UIViewController {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    @IBOutlet weak var cancelButton: ObvFloatingButton!
    @IBOutlet weak var explanationLabel: UILabel!
    @IBOutlet weak var videoView: UIView!
    private let captureSession = AVCaptureSession()
    private var qrCodeFrameView: UIView?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer!
    
    var explanation: String? {
        didSet {
            explanationLabel?.text = explanation
        }
    }
    
    @IBAction func cancelButtonTapped(_ sender: Any) {
        delegate?.userCancelledQRCodeScanSession()
    }
    
    weak var delegate: QRCodeScannerViewControllerDelegate? = nil
    
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
}

// MARK: - View Controller Lifecycle

extension QRCodeScannerViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        explanationLabel.text = explanation
        
        if presentedViewController == self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.cancel, target: self, action: #selector(cancelButtonTapped))
        }
        
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                                                                      mediaType: nil,
                                                                      position: .back)
        
        guard let captureDevice = deviceDiscoverySession.devices.first else {
            os_log("Failed to load capture device", log: log, type: .error)
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
            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            captureMetadataOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.qr]
        }
        
        // Initialize the video preview layer and add it as a sublayer of our view
        
        do {
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            videoPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
            videoPreviewLayer.frame = videoView.bounds
            videoView.layer.addSublayer(videoPreviewLayer)
        }
        
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        adaptVideoPreviewLayerSizeAndOrientation()
    }
    
    
    private func adaptVideoPreviewLayerSizeAndOrientation() {
        // Adapt the video preview layer size
        guard let videoPreviewLayer = self.videoPreviewLayer else { return }
        guard let videoView = self.videoView else { return }
        videoPreviewLayer.frame = videoView.bounds
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
        
        // Start the video capture
        captureSession.startRunning()
        
        adaptVideoPreviewLayerSizeAndOrientation()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        adaptVideoPreviewLayerSizeAndOrientation()
    }
    
}

extension QRCodeScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {

        guard captureSession.isRunning else { return }
        
        guard !metadataObjects.isEmpty else { return }
        
        let readableCodeObjects = metadataObjects.compactMap { $0 as? AVMetadataMachineReadableCodeObject }
        
        guard !readableCodeObjects.isEmpty else { return }
        
        let qrCodeObjects = readableCodeObjects.filter { $0.type == AVMetadataObject.ObjectType.qr }
        
        guard !qrCodeObjects.isEmpty else { return }
        
        guard qrCodeObjects.count == 1 else { return }
        
        guard let stringValue = qrCodeObjects.first!.stringValue else { return }
        
        guard let url = URL(string: stringValue) else { return }

        captureSession.stopRunning()
        delegate?.qrCodeScanned(url: url)
        
    }
    
}

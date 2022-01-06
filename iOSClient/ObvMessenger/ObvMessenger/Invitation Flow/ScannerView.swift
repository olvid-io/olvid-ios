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

import SwiftUI
import AVFoundation
import os.log


@available(iOS 13, *)
protocol ScannerHostingViewDelegate: AnyObject {
    func scannerViewActionButtonWasTapped()
    func qrCodeWasScanned(olvidURL: OlvidURL)
}


@available(iOS 13, *)
final class ScannerHostingView: UIHostingController<ScannerView>, ScannerViewStoreDelegate {
    
    let store: ScannerViewStore
    
    weak var delegate: ScannerHostingViewDelegate?
    
    init(buttonType: ScannerView.ButtonType, delegate: ScannerHostingViewDelegate) {
        let store = ScannerViewStore()
        let view = ScannerView(buttonType: buttonType, buttonAction: store.buttonAction, qrCodeScannedAction: store.qrCodeScannedAction)
        self.store = store
        super.init(rootView: view)
        self.delegate = delegate
        self.store.delegate = self
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.overrideUserInterfaceStyle = .dark
    }
    
    // ScannerViewStoreDelegate
    
    func buttonAction() {
        delegate?.scannerViewActionButtonWasTapped()
    }
    
    func qrCodeWasScanned(olvidURL: OlvidURL) {
        delegate?.qrCodeWasScanned(olvidURL: olvidURL)
    }

    
}


// MARK: - ScannerViewStoreDelegate

protocol ScannerViewStoreDelegate: AnyObject {
    func buttonAction()
    func qrCodeWasScanned(olvidURL: OlvidURL)
}


// MARK: - ScannerViewStore

@available(iOS 13, *)
final class ScannerViewStore {
    weak var delegate: ScannerViewStoreDelegate?
    
    func buttonAction() {
        delegate?.buttonAction()
    }
    
    func qrCodeScannedAction(_ olvidURL: OlvidURL) {
        delegate?.qrCodeWasScanned(olvidURL: olvidURL)
    }
}


// MARK: - ScannerView

@available(iOS 13, *)
struct ScannerView: View {
    
    enum ButtonType {
        case showMyId
        case back
    }
    
    let buttonType: ButtonType
    let buttonAction: () -> Void
    let qrCodeScannedAction: (OlvidURL) -> Void

    private let transparentDarkColor = UIColor(displayP3Red: 0, green: 0, blue: 0, alpha: 0.8)
    private let squareSizeRatio: CGFloat = 1.8
    private let ratioForBlueLineDistanceFromSquare: CGFloat = 15
    
    private func topLeft(from geometry: GeometryProxy) -> CGPoint {
        let center = CGPoint(x: geometry.size.width/2, y: geometry.size.height/2)
        let squareSide = geometry.size.smallestSide/squareSizeRatio
        let x = center.x - squareSide/2 - squareSide/ratioForBlueLineDistanceFromSquare
        let y = center.y - squareSide/2 - squareSide/ratioForBlueLineDistanceFromSquare
        return CGPoint(x: x, y: y)
    }

    private func topRight(from geometry: GeometryProxy) -> CGPoint {
        let center = CGPoint(x: geometry.size.width/2, y: geometry.size.height/2)
        let squareSide = geometry.size.smallestSide/squareSizeRatio
        let x = center.x + squareSide/2 + squareSide/ratioForBlueLineDistanceFromSquare
        let y = center.y - squareSide/2 - squareSide/ratioForBlueLineDistanceFromSquare
        return CGPoint(x: x, y: y)
    }

    private func bottomRight(from geometry: GeometryProxy) -> CGPoint {
        let center = CGPoint(x: geometry.size.width/2, y: geometry.size.height/2)
        let squareSide = geometry.size.smallestSide/squareSizeRatio
        let x = center.x + squareSide/2 + squareSide/ratioForBlueLineDistanceFromSquare
        let y = center.y + squareSide/2 + squareSide/ratioForBlueLineDistanceFromSquare
        return CGPoint(x: x, y: y)
    }

    private func bottomLeft(from geometry: GeometryProxy) -> CGPoint {
        let center = CGPoint(x: geometry.size.width/2, y: geometry.size.height/2)
        let squareSide = geometry.size.smallestSide/squareSizeRatio
        let x = center.x - squareSide/2 - squareSide/ratioForBlueLineDistanceFromSquare
        let y = center.y + squareSide/2 + squareSide/ratioForBlueLineDistanceFromSquare
        return CGPoint(x: x, y: y)
    }

    private struct Segment: Identifiable {
        let id = UUID()
        let startPoint: CGPoint
        let vector: CGVector
        var endPoint: CGPoint {
            CGPoint(x: startPoint.x + vector.dx, y: startPoint.y + vector.dy)
        }
    }
    
    private func computeAllSegments(from geometry: GeometryProxy) -> [Segment] {
        let lineLength: CGFloat = geometry.size.smallestSide/(5*squareSizeRatio)
        return [
            Segment(startPoint: topLeft(from: geometry),
                    vector: CGVector(dx: lineLength, dy: 0)),
            Segment(startPoint: topLeft(from: geometry),
                    vector: CGVector(dx: 0, dy: lineLength)),
            Segment(startPoint: topRight(from: geometry),
                    vector: CGVector(dx: -lineLength, dy: 0)),
            Segment(startPoint: topRight(from: geometry),
                    vector: CGVector(dx: 0, dy: lineLength)),
            Segment(startPoint: bottomRight(from: geometry),
                    vector: CGVector(dx: 0, dy: -lineLength)),
            Segment(startPoint: bottomRight(from: geometry),
                    vector: CGVector(dx: -lineLength, dy: 0)),
            Segment(startPoint: bottomLeft(from: geometry),
                    vector: CGVector(dx: lineLength, dy: 0)),
            Segment(startPoint: bottomLeft(from: geometry),
                    vector: CGVector(dx: 0, dy: -lineLength)),
        ]
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                NewQRCodeScannerViewControllerRepresentable(qrCodeScannedAction: qrCodeScannedAction)
                    .edgesIgnoringSafeArea(.all)
                ZStack(alignment: .center) {
                    Rectangle()
                        .foregroundColor(Color(UIColor(white: 0.8, alpha: 1.0)))
                        .edgesIgnoringSafeArea(.all)
                    Rectangle()
                        .frame(width: geometry.size.smallestSide/squareSizeRatio,
                               height: geometry.size.smallestSide/squareSizeRatio,
                               alignment: .center)
                        .foregroundColor(Color.black)
                        .border(Color.red, width: 2)
                }
                .compositingGroup()
                .luminanceToAlpha()
                ZStack(alignment: .center) {
                    Rectangle()
                        .frame(width: geometry.size.smallestSide/squareSizeRatio,
                               height: geometry.size.smallestSide/squareSizeRatio,
                               alignment: .center)
                        .foregroundColor(.clear)
                        .border(Color.white, width: 2)
                    Image("badge-for-qrcode")
                        .resizable()
                        .frame(width: 28, height: 28, alignment: .center)
                        .opacity(0.3)
                }
                .edgesIgnoringSafeArea(.all)
                Path { path in
                    computeAllSegments(from: geometry).forEach { (segment) in
                        path.move(to: segment.startPoint)
                        path.addLine(to: segment.endPoint)
                    }
                }
                .stroke(style: StrokeStyle(lineWidth: 3.0, lineCap: .round))
                .foregroundColor(Color(AppTheme.shared.colorScheme.olvidLight))
                VStack {
                    Spacer()
                    switch buttonType {
                    case .showMyId:
                        OlvidButton(style: .blue, title: Text("Show my Id"), systemIcon: .qrcode, action: buttonAction)
                    case .back:
                        OlvidButton(style: .blue, title: Text("Back"), systemIcon: .arrowshapeTurnUpBackwardFill, action: buttonAction)
                    }
                }.padding(.all, 16)
            }
        }
    }
}


fileprivate extension CGSize {
    var smallestSide: CGFloat { min(width, height) }
}


@available(iOS 13, *)
fileprivate struct NewQRCodeScannerViewControllerRepresentable: UIViewControllerRepresentable {
    
    let qrCodeScannedAction: (OlvidURL) -> Void

    func makeUIViewController(context: Context) -> NewQRCodeScannerViewController {
        NewQRCodeScannerViewController(qrCodeScannedAction: qrCodeScannedAction)
    }
    
    func updateUIViewController(_ uiViewController: NewQRCodeScannerViewController, context: Context) {}

}


/// This view controller embeds the capture device allowing to scan QR codes.
fileprivate final class NewQRCodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    
    let qrCodeScannedAction: (OlvidURL) -> Void
    
    init(qrCodeScannedAction: @escaping (OlvidURL) -> Void) {
        self.qrCodeScannedAction = qrCodeScannedAction
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
    private let captureSession = AVCaptureSession()
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.insetsLayoutMarginsFromSafeArea = false
        
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                                                                      mediaType: nil,
                                                                      position: .back)

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
            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            captureMetadataOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.qr]
        }
        
        // Initialize the video preview layer and add it as a sublayer of our view
        
        do {
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            videoPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
            videoPreviewLayer.frame = self.view.bounds
            self.view.layer.addSublayer(videoPreviewLayer)
        }

    }
    
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        adaptVideoPreviewLayerSizeAndOrientation()
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
        // Start the video capture
        captureSession.startRunning()
        adaptVideoPreviewLayerSizeAndOrientation()
    }
    
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        adaptVideoPreviewLayerSizeAndOrientation()
    }

    
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

        guard let olvidURL = OlvidURL(urlRepresentation: url) else { return }
        
        captureSession.stopRunning()
        
        UINotificationFeedbackGenerator()
            .notificationOccurred(.success)

        qrCodeScannedAction(olvidURL)
        
    }

}


















@available(iOS 13, *)
struct ScannerView_Previews: PreviewProvider {
    static var previews: some View {
        ScannerView(buttonType: .showMyId, buttonAction: {}, qrCodeScannedAction: { _ in })
    }
}

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

import SwiftUI
import ObvAppTypes
import ObvDesignSystem
import ObvTypes
import CoreData


@MainActor
public protocol ObvScannerViewActions: AnyObject {
    func userScannedOrPastedAnOlvidURL(_ view: NewScannerView, scannedOlvidURL: OlvidURL) -> (remoteURLIdentity: ObvURLIdentity, mutualScanURLToShow: ObvMutualScanUrl)?
    func userWantsToStartTrustEstablishmentProtocolOfRemoteIdentity(_ view: NewScannerView, ownedCryptoId: ObvCryptoId, remoteURLIdentity: ObvURLIdentity)
}


/// When the `NewScannerView` enters `remoteIdentityScanned` mode, it displays the current user’s `ObvMutualScanUrl`
/// and requests a stream of `NewScannerViewModel` updates from its data source.
/// This stream notifies the view when a one-to-one discussion with the contact is available,
/// and when a new direct trust origin is created within the engine for that contact,
/// enabling automatic presentation of the confirmation screen.
public struct ObvNewScannerViewModel: Sendable, Equatable {
    let scanValidationViewModel: ScanValidationViewModel
    let aNewDirectTrustOriginWasCreated: Bool
    
    public init(scanValidationViewModel: ScanValidationViewModel, aNewDirectTrustOriginWasCreated: Bool) {
        self.scanValidationViewModel = scanValidationViewModel
        self.aNewDirectTrustOriginWasCreated = aNewDirectTrustOriginWasCreated
    }
    
}

@MainActor
public protocol ObvNewScannerViewDataSource {
    func getAsyncStreamOfObvNewScannerViewModel(_ view: NewScannerView, contactIdentifier: ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvNewScannerViewModel>)
    func finishAsyncStreamOfObvNewScannerViewModel(_ view: NewScannerView, streamUUID: UUID)
}

/// ScannerView: A SwiftUI view for scanning and exchanging OlvidURLs of kind `invitation` and `mutualScan`.
///
/// This view operates in two modes:
/// - **`singleScan`**: Displays only the `QRCodeScannerView`.
/// - **`mutualScan`**: Displays both the `QRCodeScannerView` and a bottom sheet with the current user's invitation QR code.
///
/// ### Mode Switching
/// The user can switch between `singleScan` and `mutualScan` modes at any time.
///
/// ### Scanning Behavior
/// - The embedded `QRCodeScannerView` sets the `scannedOlvidURL` variable when it detects an `OlvidURL`.
/// - `scannedOlvidURL` is set only once per session.
/// - Upon setting, the `OlvidURL` is passed to a delegate (typically the app), which handles the URL based on its type.
///   - For most `OlvidURL` types (e.g., Keycloak configuration), the scanner is dismissed, and the appropriate flow (e.g., Keycloak binding) is presented.
///   - For contact invitation QR codes, the delegate returns:
///     - The remote user's URL identity.
///     - An `ObvMutualScanUrl`, which replaces the QR code in the bottom sheet.
///   - The remote user can scan this mutual scan URL to complete the contact exchange.
///
/// ### Special Cases
/// - If the local user imports a remote user's invitation QR code (e.g., via email or external scan), this view is **not** shown.
///   Instead, a dedicated view is presented to avoid confusion.
public struct NewScannerView: View {
    
    let ownedCryptoId: ObvCryptoId
    let actions: ObvScannerViewActions
    let router: InvitationFlowRouter

    @State private var scannerMode: ScannerMode
    
    public enum ScannerMode: Equatable, Hashable {
        case singleScan(ownedURLIdentity: ObvURLIdentity)
        case mutualScan(ownedURLIdentityToShow: ObvURLIdentity)
        case remoteIdentityScanned(remoteURLIdentity: ObvURLIdentity, mutualScanURLToShow: ObvMutualScanUrl)
    }
    
    init(ownedCryptoId: ObvCryptoId, initialScannerMode: ScannerMode, actions: ObvScannerViewActions, router: InvitationFlowRouter) {
        self.ownedCryptoId = ownedCryptoId
        self.scannerMode = initialScannerMode
        switch initialScannerMode {
        case .singleScan:
            showBottomSheet = false
            graphicalOverlayAnimationAmount = 1.0
        case .mutualScan, .remoteIdentityScanned:
            showBottomSheet = true
            graphicalOverlayAnimationAmount = 0.0
        }
        self.actions = actions
        self.router = router
    }
    
    /// The most recently scanned (via `QRCodeScannerView`) or pasted `OlvidURL`.
    /// - The scanner only sets this if it is `nil`.
    /// - Manual pastes always update the value.
    @State private var scannedOrPastedOlvidURL: OlvidURL?
    
    /// Tracks the bottom sheet height.
    ///
    /// This makes it possible to adapt the position of the overlay of the `QRCodeScannerView`.
    @State private var sheetHeight = 0.0
    
    /// Determines whether a bottom sheet is displayed, showing a QR code based on the current context:
    ///
    /// - **Invitation QR Code**: Allows another user to scan and initiate an invitation flow.
    /// - **Mutual Scan QR Code (`ObvMutualScanUrl`)**: Displayed only after scanning another user's invitation QR code.
    @State private var showBottomSheet: Bool

    /// Controls the animation for the graphical overlay's appearance.
    ///
    /// Initially set to `0`, this value animates to `1.0` when the view appears,
    /// creating a smooth fade-in effect for the overlay above the QR code scanner.
    @State private var graphicalOverlayAnimationAmount: CGFloat
    
    @State private var currentDetent: PresentationDetent = .medium
    
    /// A Boolean value indicating whether the `QRCodeScannerView` has successfully scanned a valid `OlvidURL`.
    ///
    /// When `true`, the scanner overlay updates to display a green checkmark, confirming to the user that the scan was successful.
    /// When `true`, the `QRCodeScannerView` does not update the `scannedOlvidURL` binding.
    private var isRemoteOlvidURLScannedOrImported: Bool {
        switch scannerMode {
        case .singleScan, .mutualScan:
            return scannedOrPastedOlvidURL != nil
        case .remoteIdentityScanned:
            return true
        }
    }
    
    private var bottomSheetMode: BottomSheetInternalView.Mode? {
        switch scannerMode {
        case .singleScan:
            return nil
        case .mutualScan(let ownedURLIdentityToShow):
            return .mutualScan(ownedURLIdentityToShow: ownedURLIdentityToShow)
        case .remoteIdentityScanned(remoteURLIdentity: let remoteURLIdentity, mutualScanURLToShow: let mutualScanURLToShow):
            return .remoteIdentityScanned(remoteURLIdentity: remoteURLIdentity, mutualScanURLToShow: mutualScanURLToShow)
        }
    }
    
    private var showSwitchToMutualScanModeButton: Bool {
        switch scannerMode {
        case .singleScan:
            return true
        case .mutualScan, .remoteIdentityScanned:
            return false
        }
    }
    
    private func switchToMutualScanModeButtonTapped() {
        switch scannerMode {
        case .singleScan(ownedURLIdentity: let ownedURLIdentity):
            self.scannerMode = .mutualScan(ownedURLIdentityToShow: ownedURLIdentity)
        case .mutualScan, .remoteIdentityScanned:
            break
        }
    }
    
    /// Requests a stream of `NewScannerViewModel` models when the `ScannerMode` is `.remoteIdentityScanned`,
    /// allowing detection of the remote Olvid user scanning our `ObvMutualScanUrl` (indicating a one-to-one discussion is available).
    /// Also ensures the bottom sheet is shown or hidden as appropriate for the current `ScannerMode`.
    private func onChangeOfScannerMode(_ newScannerMode: ScannerMode) {
        
        // Ensure the bottom sheet is shown or hidden as appropriate
        
        switch newScannerMode {
        case .singleScan:
            showBottomSheet = false
        case .mutualScan, .remoteIdentityScanned:
            showBottomSheet = true
        }
        
        // Requests a stream of `NewScannerViewModel` models when the `ScannerMode` is `.remoteIdentityScanned`,

        switch newScannerMode {
        case .singleScan, .mutualScan:
            break
        case .remoteIdentityScanned(remoteURLIdentity: let remoteURLIdentity, mutualScanURLToShow: let mutualScanURLToShow):
            let contactIdentifier = ObvContactIdentifier(contactCryptoId: remoteURLIdentity.cryptoId, ownedCryptoId: mutualScanURLToShow.cryptoId)
            Task {
                await requestAsyncStreamOfObvQRCodeViewViewModel(contactIdentifier: contactIdentifier)
            }
        }
        
    }

    /// When the `ScannerMode` is `.remoteIdentityScanned`, requests a stream of `NewScannerViewModel` from the data source.
    /// This stream allows to detect when a one-to-one discussion becomes available with the remote user, and when a new direct trust origin is created within the engine—indicating they scanned our `ObvMutualScanUrl`—
    /// and to trigger navigation to the confirmation screen.
    private func requestAsyncStreamOfObvQRCodeViewViewModel(contactIdentifier: ObvContactIdentifier) async {
        do {
            let (streamUUID, stream) = try await router.scannerViewDataSource.getAsyncStreamOfObvNewScannerViewModel(self, contactIdentifier: contactIdentifier)
            for await receivedModel in stream {
                let scanValidationViewModel = receivedModel.scanValidationViewModel
                guard scanValidationViewModel.activeOneToOneDiscussionAvailable else { continue }
                guard receivedModel.aNewDirectTrustOriginWasCreated else { continue }
                self.showBottomSheet = false // Required to prevent a bug where the bottom sheet re-appears (and connot be dismissed) after the scanValidation presentation.
                router.presentFullScreen(.scanValidation(currentOwnedCryptoId: ownedCryptoId, initalScanViewModel: scanValidationViewModel))
                break // Stop receiving stream updates since the parent router will soon present the scan validation
            }
            router.scannerViewDataSource.finishAsyncStreamOfObvNewScannerViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }

    
    /// Handles the dismissal of the bottom sheet when the user pulls it down in `mutualScan` mode.
    ///
    /// - Note:
    ///   - In `remoteIdentityScanned` mode, the sheet is non-dismissible (`interactiveDismiss` is disabled).
    ///   - In `singleScan` mode, the sheet is already dismissed.
    ///
    /// When the sheet is dismissed in `mutualScan` mode:
    ///   - The app switches to `singleScan` mode.
    ///   - The user can return to `mutualScan` mode by tapping a button at the bottom of the screen.
    ///
    /// Additionally, the sheet height is set to 0 to ensure the QR code scanner overlay resizes correctly.
    private func onDismissOfBottomSheet() {

        switch scannerMode {
        case .singleScan:
            break
        case .mutualScan(let ownedURLIdentityToShow):
            self.scannerMode = .singleScan(ownedURLIdentity: ownedURLIdentityToShow)
        case .remoteIdentityScanned:
            break
        }
        
        setSheetHeight(0)
        
    }
    
    private var interactiveDismissDisabled: Bool {
        switch scannerMode {
        case .singleScan, .mutualScan:
            return false
        case .remoteIdentityScanned:
            return true
        }
    }
    
    /// Updates the `sheetHeight` whenever the bottom sheet's height changes.
    ///
    /// This ensures the `GraphicalOverlayOverQRCodeScanner` adjusts its size and position dynamically.
    private func setSheetHeight(_ newSheetHeight: CGFloat) {
        withAnimation { self.sheetHeight = newSheetHeight }
    }
    
    @State private var showAlertPastedInvitationLinkIsOwnInvitationLink: Bool = false
    
    private func onChangeOfScannedOlvidURL(_ newScannedOlvidURL: OlvidURL?) {
        guard let newScannedOlvidURL else { return }
        guard let (remoteURLIdentity, mutualScanURLToShow) = actions.userScannedOrPastedAnOlvidURL(self, scannedOlvidURL: newScannedOlvidURL) else {
            // The scanned OlvidURL is not an invitation (e.g., it could be a Keycloak configuration).
            // Since this scanner is part of the invitation flow, it will be dismissed and replaced
            // by the appropriate flow for the scanned OlvidURL type.
            return
        }
        // Make sure the "remote" identity is distinct from the owned identity
        guard remoteURLIdentity.cryptoId != mutualScanURLToShow.cryptoId else {
            showAlertPastedInvitationLinkIsOwnInvitationLink = true
            return
        }
        // The scanned OlvidURL was an invitation. We received a mutual scan URL in response,
        // which replaces the current user's invitation URL in the bottom sheet.
        switch scannerMode {
        case .singleScan, .mutualScan:
            self.scannerMode = .remoteIdentityScanned(remoteURLIdentity: remoteURLIdentity, mutualScanURLToShow: mutualScanURLToShow)
        case .remoteIdentityScanned:
            assertionFailure()
        }
    }
    
    private func contactCannotScanAndUserWantsToInviteRemotely() {
        switch scannerMode {
        case .singleScan, .mutualScan:
            return
        case .remoteIdentityScanned(remoteURLIdentity: let remoteURLIdentity, mutualScanURLToShow: _):
            actions.userWantsToStartTrustEstablishmentProtocolOfRemoteIdentity(self, ownedCryptoId: ownedCryptoId, remoteURLIdentity: remoteURLIdentity)
        }
    }
    
    @ViewBuilder
    private var bodyForIphoneAndIPad: some View {
        Group {
            GeometryReader { geometry in
                ZStack {
                    
                    QRCodeScannerView(scannedOlvidURL: $scannedOrPastedOlvidURL, doScanOlvidURL: !isRemoteOlvidURLScannedOrImported)
                        .ignoresSafeArea()
                    
                    GraphicalOverlayOverQRCodeScanner(geometrySize: geometry.size,
                                                      geometrySafeAreaInsets: geometry.safeAreaInsets,
                                                      sheetHeight: sheetHeight,
                                                      isURLScanned: isRemoteOlvidURLScannedOrImported,
                                                      animationAmount: graphicalOverlayAnimationAmount)
                    
                    if showSwitchToMutualScanModeButton {
                        VStack {
                            Spacer()
                            AddContactButton(action: switchToMutualScanModeButtonTapped)
                                .padding(.bottom)
                        }
                    }
                    
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.25).delay(showBottomSheet ? 0.9 : 0.0)) {
                        graphicalOverlayAnimationAmount = 1.0
                    }
                }
                .sheet(isPresented: $showBottomSheet, onDismiss: onDismissOfBottomSheet) {
                    if let bottomSheetMode {
                        GeometryReader { proxy in
                            BottomSheetInternalView(
                                ownedCryptoId: ownedCryptoId,
                                mode: bottomSheetMode,
                                currentDetent: currentDetent,
                                router: router,
                                contactCannotScanAndUserWantsToInviteRemotely: contactCannotScanAndUserWantsToInviteRemotely)
                            .presentationBackgroundInteractionOniOS16Dot4(.enabledUpThrough(detent: .medium)) // Enabled interaction of the behind view if sheet is in medium detent maximum
                            .presentationDetents([.medium, .fraction(0.99)], selection: $currentDetent) // use .fraction(0.99) instead of .large to prevent view behind to zoom out
                            .interactiveDismissDisabled(interactiveDismissDisabled)
                            .onChange(of: proxy.size.height, perform: setSheetHeight)
                            .onAppear(perform: { setSheetHeight(proxy.size.height) })
                        }
                        
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DismissButton(action: { router.dismiss() })
                }
                ToolbarItem(placement: .topBarTrailing) {
                    CopyPasteMenu(ownedCryptoId: ownedCryptoId,
                                  actions: router.copyPasteMenuActions,
                                  pastedOlvidURL: $scannedOrPastedOlvidURL)
                    .foregroundStyle(.white)
                }
            }
        }
    }

    @ViewBuilder
    private var bodyForMacOS: some View {
        ZStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    
                    ZStack {
                        
                        QRCodeScannerView(scannedOlvidURL: $scannedOrPastedOlvidURL, doScanOlvidURL: !isRemoteOlvidURLScannedOrImported)
                            .ignoresSafeArea()
                        
                        GraphicalOverlayOverQRCodeScanner(geometrySize: .init(width: geometry.size.width, height: geometry.size.height / (bottomSheetMode == nil ? 1.0 : 2.0)),
                                                          geometrySafeAreaInsets: .init(top: 0, leading: 0, bottom: 0, trailing: 0),
                                                          sheetHeight: 0.0,
                                                          isURLScanned: isRemoteOlvidURLScannedOrImported,
                                                          animationAmount: 1.0)
                        
                        if showSwitchToMutualScanModeButton {
                            VStack {
                                Spacer()
                                AddContactButton(action: switchToMutualScanModeButtonTapped)
                                    .padding(.bottom)
                            }
                        }
                        
                    }
                    
                    if let bottomSheetMode {
                        if #available(iOS 26.0, *) {
                            BottomSheetInternalView(ownedCryptoId: ownedCryptoId,
                                                    mode: bottomSheetMode,
                                                    currentDetent: .medium,
                                                    router: router,
                                                    contactCannotScanAndUserWantsToInviteRemotely: contactCannotScanAndUserWantsToInviteRemotely)
                            .padding(.bottom)
                            .glassEffect(.regular.tint(.black.opacity(0.8)), in: Rectangle())
                        } else {
                            BottomSheetInternalView(ownedCryptoId: ownedCryptoId,
                                                    mode: bottomSheetMode,
                                                    currentDetent: .medium,
                                                    router: router,
                                                    contactCannotScanAndUserWantsToInviteRemotely: contactCannotScanAndUserWantsToInviteRemotely)
                            .padding(.bottom)
                            .background(.black)
                        }
                    }
                    
                }
            }
            
            VStack {
                HStack {
                    DismissButtonForMacOS(action: { router.dismiss() })
                        .keyboardShortcut(.escape)
                        .padding([.leading, .top])
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            
        }
    }
    
    public var body: some View {
        Group {
            #if targetEnvironment(macCatalyst)
            bodyForMacOS
            #else
            bodyForIphoneAndIPad
            #endif
        }
        .onChange(of: scannerMode, perform: onChangeOfScannerMode)
        .onChange(of: scannedOrPastedOlvidURL, perform: onChangeOfScannedOlvidURL)
        .alert(String(localizedInThisBundle: "CANNOT_INVITE_YOURSELF_TITLE"), isPresented: $showAlertPastedInvitationLinkIsOwnInvitationLink, actions: {}) {
            Text("CANNOT_INVITE_YOURSELF_MESSAGE")
        }
    }
    
}

// MARK: - Internal view

private struct DismissButtonForMacOS: View {
    
    let action: () -> Void
    
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: .close, action: action)
                .buttonStyle(.glassProminent)
        } else {
            Button(action: action) {
                Image(systemIcon: .xmark)
                    .foregroundStyle(.white)
            }
        }
    }

}


// MARK: - Internal view

private struct DismissButton: View {
    
    let action: () -> Void
    
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Image(systemIcon: .xmark)
            }
        } else {
            Button(action: action) {
                Image(systemIcon: .xmark)
                    .foregroundStyle(.white)
            }
        }
    }
    
}


// MARK: - Private view

/// A button displayed at the bottom of the screen in `singleScan` mode.
///
/// Tapping this button switches the scanner to `mutualScan` mode, which is designed for establishing
/// a connection with another user by scanning each other's QR codes.
private struct AddContactButton: View {

    let action: () -> Void
    
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Text("ADD_A_CONTACT_BUTTON_TITLE")
            }
            .buttonStyle(.glass)
        } else {
            Button(action: action) {
                Text("ADD_A_CONTACT_BUTTON_TITLE")
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
}



// MARK: - Internal view

private struct BottomSheetInternalView: View {
    
    let ownedCryptoId: ObvCryptoId
    let mode: Mode
    let currentDetent: PresentationDetent
    let router: InvitationFlowRouter
    let contactCannotScanAndUserWantsToInviteRemotely: () -> Void
    
    enum Mode: Equatable, CustomDebugStringConvertible {
        case mutualScan(ownedURLIdentityToShow: ObvURLIdentity)
        case remoteIdentityScanned(remoteURLIdentity: ObvURLIdentity, mutualScanURLToShow: ObvMutualScanUrl)
        var debugDescription: String {
            switch self {
            case .mutualScan: return "mutualScan"
            case .remoteIdentityScanned: return "remoteIdentityScanned"
            }
        }
    }
    
    
    private var urlToShow: URL {
        switch mode {
        case .mutualScan(ownedURLIdentityToShow: let ownedURLIdentityToShow):
            return ownedURLIdentityToShow.urlRepresentation(for: .doubleScan)
        case .remoteIdentityScanned(remoteURLIdentity: _, mutualScanURLToShow: let mutualScanURLToShow):
            return mutualScanURLToShow.urlRepresentation
        }
    }
    
    @State var showAdditionalButton: Bool = false
    
    private func evaluateButtonAppearance() {
        Task {
            try? await Task.sleep(seconds: 3)
            withAnimation { showAdditionalButton = true }
        }
    }
    
    private func userCannotScanAndWantsToInviteContactDifferently() {
        router.presentFullScreen(.sharingProfile(currentOwnedCryptoId: ownedCryptoId))
    }
    

    var body: some View {
        VStack(alignment: .center) {
            
            HStack {
                Spacer(minLength: 0)
                Text("SCAN_MUTUAL_TITLE")
                    .multilineTextAlignment(.center)
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer(minLength: 0)
            }
            .padding(.top)
            
            Spacer()
              
            QRCodeView(ownedCryptoId: ownedCryptoId,
                       dataSource: router.qrCodeViewDataSource,
                       avatarViewDataSource: router.avatarViewDataSource,
                       urlToShow: urlToShow)
            
            if showAdditionalButton {
                VStack {
                    switch mode {
                    case .mutualScan:
                        Text("SCAN_MUTUAL_CANNOT_MESSAGE")
                        Button(action: userCannotScanAndWantsToInviteContactDifferently) {
                            Text("SCAN_MUTAL_CANNOT_ACTION")
                                .fontWeight(.bold)
                        }
                    case .remoteIdentityScanned:
                        Text("SCAN_MUTUAL_CANNOT_STEP_2_MESSAGE")
                        Button(action: contactCannotScanAndUserWantsToInviteRemotely) {
                            Text("SCAN_MUTAL_CANNOT_STEP_2_ACTION")
                                .fontWeight(.bold)
                        }
                    }
                }
                .font(.callout)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer()

        }
        .padding(.top)
        .padding(.horizontal)
        .onAppear(perform: evaluateButtonAppearance)
        .onChange(of: mode) { _ in evaluateButtonAppearance() }
    }
    
}


// MARK: - Internal view

public struct ObvQRCodeViewViewModel: Equatable, Sendable {
    let ownedIdentityAvatarViewModel: ObvAvatarViewModel

    public init(ownedIdentityAvatarViewModel: ObvAvatarViewModel) {
        self.ownedIdentityAvatarViewModel = ownedIdentityAvatarViewModel
    }
    
}

@MainActor
public protocol ObvQRCodeViewDataSource {
    func getAsyncStreamOfObvQRCodeViewViewModel(_ view: QRCodeView, ownedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvQRCodeViewViewModel>)
    func finishAsyncStreamOfObvQRCodeViewViewModel(_ view: QRCodeView, streamUUID: UUID)
}


public struct QRCodeView: View {
    
    let ownedCryptoId: ObvCryptoId
    let dataSource: ObvQRCodeViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    
    /// A URL used during the mutual scan invitation flow.
    ///
    /// - When the scanner is in **`mutualScan`** mode, this URL represents the **invitation link** (an `ObvURLIdentity`) of the current user's identity.
    /// - When the scanner is in **`remoteIdentityScanned`** mode, this URL is an **`ObvMutualScanUrl`** intended for the contact.
    ///
    /// This URL dynamically changes based on the scanner's mode and is critical for establishing a secure connection between identities.
    let urlToShow: URL
    //let avatarModel: ObvAvatarViewModel
    //let avatarViewDataSource: ObvAvatarViewDataSource
    
    @State private var streamedViewModel: ObvQRCodeViewViewModel?

    @State private var qrCodeImage: Image?
    
    private func generateQRCode(urlToShow: URL) {
        qrCodeImage = nil
        DispatchQueue(label: "Queue for generating QR code").async {
            guard let qrCode = urlToShow.qrCode else { assertionFailure(); return }
            DispatchQueue.main.async {
                withAnimation {
                    qrCodeImage = Image(uiImage: qrCode)
                }
            }
        }
    }
    
    private let circleOffset: CGFloat = 35.0
    private let circleSize: CGFloat = 70.0
    
    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfObvQRCodeViewViewModel(self, ownedCryptoId: ownedCryptoId)
            for await receivedModel in stream {
                withAnimation {
                    self.streamedViewModel = receivedModel
                }
            }
            dataSource.finishAsyncStreamOfObvQRCodeViewViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
    private var avatarModel: ObvAvatarViewModel {
        return streamedViewModel?.ownedIdentityAvatarViewModel ?? .init(characterOrIcon: .icon(.person), colors: ObvAvatarViewModel.Colors.init(foreground: .gray, background: .lightGray), photoURL: nil)
    }
    
    @State var showURLCopiedFeedback = false
    
    private func userPerformedDoubleTapOnQRCode() {
        UIPasteboard.general.string = urlToShow.absoluteString
        withAnimation { showURLCopiedFeedback = true }
        Task {
            try? await Task.sleep(seconds: 2)
            withAnimation { showURLCopiedFeedback = false }
        }
    }
    
    @ViewBuilder
    private var URLCopiedFeedback: some View {
        if #available(iOS 26.0, *) {
            Text("COPIED")
                .padding()
                .glassEffect(in: .capsule)
        } else {
            Text("COPIED")
                .padding()
                .background(in: .capsule)
        }
    }
    
    public var body: some View {
        VStack(alignment: .center, spacing: 0.0) {

            ZStack(alignment: .center) {
                Circle()
                    .foregroundStyle(.white)
                    .frame(width: circleSize)
                ObvAvatarView(model: avatarModel,
                              style: .circle,
                              size: .custom(frameSize: CGSize(width: 60.0, height: 60.0)),
                              dataSource: avatarViewDataSource)
            }
            .zIndex(1)
            .offset(y: circleOffset)
            .padding(.top, -circleOffset)
            
            ZStack(alignment: Alignment(horizontal: .center, vertical: .center)) {
                RoundedRectangle(cornerRadius: 24.0)
                    .foregroundColor(.white)
                    .aspectRatio(1.0, contentMode: .fit)
                    .shadow(color: .black.opacity(0.1), radius: 10)
                if let qrCodeImage = self.qrCodeImage {
                    
                    ZStack(alignment: .center) {
                        qrCodeImage
                            .interpolation(.none)
                            .resizable()
                            .aspectRatio(1.0, contentMode: .fit)
                            .onTapGesture(count: 2, perform: userPerformedDoubleTapOnQRCode)
                        if showURLCopiedFeedback {
                            URLCopiedFeedback
                        }
                    }
                    .padding(16.0)
                    
                } else {
                    ProgressView()
                        .tint(.gray)
                }
            }
        }
        .onAppear(perform: { generateQRCode(urlToShow: self.urlToShow) } )
        .onChange(of: urlToShow) { newURLToShow in generateQRCode(urlToShow: newURLToShow) }
        .task(onTask)
    }
    
}


// MARK: - Internal view

/// A semi-transparent overlay for the QR-code scanner view.
///
/// This view dims the background to focus attention on a central rounded-square cutout,
/// visually guiding the user to align and scan a QR code within the highlighted area.
private struct GraphicalOverlayOverQRCodeScanner: View {
    
    let geometrySize: CGSize
    let geometrySafeAreaInsets: EdgeInsets
    let sheetHeight: CGFloat
    let isURLScanned: Bool
    let animationAmount: CGFloat
    
    let borderGradient = Gradient(
        colors: [
            Color(red: 107.0/255.0, green: 183.0/255.0, blue: 0),
            Color(red: 47.0/255.0, green: 101.0/255.0, blue: 245.0/255.0)
        ]
    )

    @State private var isScaled = false
    
    private func onSymbolImageAppear() {
        withAnimation { isScaled = true }
    }
    
    private var scanYoursTitleWidth: CGFloat {
        #if targetEnvironment(macCatalyst)
        return geometrySize.width / 5
        #else
        return geometrySize.width / 2
        #endif
    }
    
    private var verticalSpacing: CGFloat {
        #if targetEnvironment(macCatalyst)
        return 0
        #else
        return 16
        #endif
    }
    
    @ViewBuilder
    private var validatedView: some View {
        VStack(alignment: .center, spacing: verticalSpacing) {

            Text("SCAN_SUCCESS_MESSAGE")
                .foregroundStyle(.white)
                .font(.callout)
                .fontWeight(.bold)

            Image(systemIcon: .checkmarkCircleFill)
                .foregroundStyle(.green)
                .font(.system(size: 46, weight: .bold))
                .background(Circle().inset(by: 2).fill(.white))
                .padding()
                .opacity(isScaled ? 1.0 : 0.0)
                .scaleEffect(isScaled ? 1.0 : 0.0) // Start small, scale to full size
                .animation(.spring(response: 0.5, dampingFraction: 0.5, blendDuration: 0.3), value: isScaled)
                .onAppear(perform: onSymbolImageAppear)
            Text("SCAN_YOURS_TITLE")
                .foregroundStyle(.white)
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(width: scanYoursTitleWidth)

        }
    }

    var body: some View {
        
        ZStack(alignment: .center) {
            
            ZStack(alignment: .center) {
                
                Rectangle()
                    .foregroundColor(Color(UIColor(white: 0.6, alpha: 1.0)))
                    .ignoresSafeArea()
                
                roundedRectangle(with: geometrySize)
                    .fill(isURLScanned ? Color(UIColor(white: 0.6, alpha: 1.0)) : .black)
                    .offset(x: 0,
                            y: getScannerYOffset(with: geometrySize, geometrySafeAreaInsets: geometrySafeAreaInsets, sheetHeight: sheetHeight))
                    .opacity(animationAmount)
                
                
            }
            .compositingGroup()
            .luminanceToAlpha()
            
            cornerBordered(with: geometrySize)
                .stroke(isURLScanned ?
                        AnyShapeStyle(LinearGradient(gradient: borderGradient,
                                                     startPoint: .topLeading,
                                                     endPoint: .bottomTrailing)) :
                            AnyShapeStyle(Color.white),
                        style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
                .offset(x: 0,
                        y: getScannerYOffset(with: geometrySize, geometrySafeAreaInsets: geometrySafeAreaInsets, sheetHeight: sheetHeight))
                .opacity(animationAmount)
            
            if isURLScanned {
                validatedView
                    .offset(x: 0,
                            y: getScannerYOffset(with: geometrySize, geometrySafeAreaInsets: geometrySafeAreaInsets, sheetHeight: sheetHeight))
                    .opacity(animationAmount)
            }
            
        }

    }
    
}


fileprivate extension CGSize {
    var smallestSide: CGFloat { min(width, height) }
}


// MARK: - View Helpers

fileprivate extension View {
    
    private static var defaultSquareSizeRatio: CGFloat { 1.8 }

    func getRectangleSize(with geometrySize: CGSize, squareSizeRatio: CGFloat = defaultSquareSizeRatio) -> CGSize {
        CGSize(width: geometrySize.smallestSide/squareSizeRatio,
               height: geometrySize.smallestSide/squareSizeRatio)
    }

    
    func roundedRectangle(with geometrySize: CGSize, squareSizeRatio: CGFloat = defaultSquareSizeRatio) -> Path {
        Path { path in
            let center = CGPoint(x: geometrySize.width/2, y: geometrySize.height/2)
            let squareSide = getRectangleSize(with: geometrySize, squareSizeRatio: squareSizeRatio).width
            let squareOffset = getRectangleSize(with: geometrySize, squareSizeRatio: squareSizeRatio).width / 4
            
            path.move(to: CGPoint(x: center.x - squareSide/2,
                                  y: center.y + squareOffset))
            path.addArc(center: CGPoint(x: center.x - 3*squareSide/8, y: center.y - 3*squareSide/8),
                        radius: squareSide/8,
                        startAngle: .degrees(180.0),
                        endAngle: .degrees(270.0),
                        clockwise: false)
            
            path.addLine(to: CGPoint(x: center.x + squareOffset,
                                     y: center.y - squareSide/2))
            
            path.addArc(center: CGPoint(x: center.x + 3*squareSide/8, y: center.y - 3*squareSide/8),
                        radius: squareSide/8,
                        startAngle: .degrees(270.0),
                        endAngle: .degrees(0.0),
                        clockwise: false)
            
            path.addLine(to: CGPoint(x: center.x + squareSide/2,
                                     y: center.y + squareOffset))
            
            path.addArc(center: CGPoint(x: center.x + 3*squareSide/8, y: center.y + 3*squareSide/8),
                        radius: squareSide/8,
                        startAngle: .degrees(0.0),
                        endAngle: .degrees(90.0),
                        clockwise: false)
            path.addLine(to: CGPoint(x: center.x - squareOffset,
                                     y: center.y + squareSide/2))
            path.addArc(center: CGPoint(x: center.x - 3*squareSide/8, y: center.y + 3*squareSide/8),
                        radius: squareSide/8,
                        startAngle: .degrees(90.0),
                        endAngle: .degrees(180.0),
                        clockwise: false)
        }
    }

    
    func cornerBordered(with geometrySize: CGSize, squareSizeRatio: CGFloat = defaultSquareSizeRatio) -> Path {
        Path { path in
            let center = CGPoint(x: geometrySize.width/2, y: geometrySize.height/2)
            let squareSide = getRectangleSize(with: geometrySize, squareSizeRatio: squareSizeRatio).width
            let squareOffset = getRectangleSize(with: geometrySize, squareSizeRatio: squareSizeRatio).width / 4
            
            path.move(to: CGPoint(x: center.x - squareSide/2,
                                  y: center.y - squareOffset))
            path.addArc(center: CGPoint(x: center.x - 3*squareSide/8, y: center.y - 3*squareSide/8),
                        radius: squareSide/8,
                        startAngle: .degrees(180.0),
                        endAngle: .degrees(270.0),
                        clockwise: false)
            path.addLine(to: CGPoint(x: center.x - squareOffset,
                                     y: center.y - squareSide/2))
            
            path.move(to: CGPoint(x: center.x + squareOffset,
                                  y: center.y - squareSide/2))
            path.addArc(center: CGPoint(x: center.x + 3*squareSide/8, y: center.y - 3*squareSide/8),
                        radius: squareSide/8,
                        startAngle: .degrees(270.0),
                        endAngle: .degrees(0.0),
                        clockwise: false)
            path.addLine(to: CGPoint(x: center.x + squareSide/2,
                                     y: center.y - squareOffset))
            
            path.move(to: CGPoint(x: center.x + squareSide/2,
                                  y: center.y + squareOffset))
            
            path.addArc(center: CGPoint(x: center.x + 3*squareSide/8, y: center.y + 3*squareSide/8),
                        radius: squareSide/8,
                        startAngle: .degrees(0.0),
                        endAngle: .degrees(90.0),
                        clockwise: false)
            path.addLine(to: CGPoint(x: center.x + squareOffset,
                                     y: center.y + squareSide/2))
            
            path.move(to: CGPoint(x: center.x - squareOffset,
                                  y: center.y + squareSide/2))
            
            path.addArc(center: CGPoint(x: center.x - 3*squareSide/8, y: center.y + 3*squareSide/8),
                        radius: squareSide/8,
                        startAngle: .degrees(90.0),
                        endAngle: .degrees(180.0),
                        clockwise: false)
            path.addLine(to: CGPoint(x: center.x - squareSide/2,
                                     y: center.y + squareOffset))
        }
    }

    
    func getScannerYOffset(with geometrySize: CGSize, geometrySafeAreaInsets: EdgeInsets, sheetHeight: CGFloat) -> CGFloat {
        if sheetHeight >= geometrySize.height / 2.0 {
            return -(geometrySize.height / 4.0) - (geometrySize.height / 16.0)
        } else {
            return max(-sheetHeight / 2.0, -(geometrySize.height / 4.0)) - geometrySafeAreaInsets.top/2
        }
    }

}



// MARK: - Previews

#if DEBUG

@MainActor
private let minimalDataSourceForPreviews = MinimalDataSourceAndActionsForPreviews()


#Preview("Single scan") {
    NavigationStack {
        NewScannerView(ownedCryptoId: ObvCryptoId.sampleOwnedCryptoId,
                       initialScannerMode: .singleScan(ownedURLIdentity: ObvURLIdentity.sampleDataOwnedIdentity),
                       actions: minimalDataSourceForPreviews,
                       router: InvitationFlowRouter.initForPreviews())
    }
}


#Preview("Double scan") {
    NavigationStack {
        NewScannerView(ownedCryptoId: ObvCryptoId.sampleOwnedCryptoId,
                       initialScannerMode: .mutualScan(ownedURLIdentityToShow: ObvURLIdentity.sampleDataOwnedIdentity),
                       actions: minimalDataSourceForPreviews,
                       router: InvitationFlowRouter.initForPreviews())
    }
}

#Preview("Double scan") {
    NavigationStack {
        NewScannerView(ownedCryptoId: ObvCryptoId.sampleOwnedCryptoId,
                       initialScannerMode: .remoteIdentityScanned(remoteURLIdentity: .sampleDataRemoteIdentity, mutualScanURLToShow: .sampleData),
                       actions: minimalDataSourceForPreviews,
                       router: InvitationFlowRouter.initForPreviews())
    }
}

#endif

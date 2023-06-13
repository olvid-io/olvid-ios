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
import UIKit
import ObvEngine
import AVFoundation
import ObvTypes
import ObvUI
import ObvUICoreData


final class AddContactHostingViewController: UIHostingController<AddContactMainView>, AddContactHostingViewStoreDelegate, KeycloakSearchViewControllerDelegate {
    
    private let store: AddContactHostingViewStore
    private let newAvailableApiKeyElements: APIKeyElements
    private var observationTokens = [NSObjectProtocol]()
    
    /// The `alreadyScannedOrTappedURL` variable is set when scanning or tapping an URL from outside the app
    init?(obvOwnedIdentity: ObvOwnedIdentity, alreadyScannedOrTappedURL: OlvidURL?, dismissAction: @escaping () -> Void, checkSignatureMutualScanUrl: @escaping (ObvMutualScanUrl) -> Bool) {
        assert(Thread.isMainThread)
        guard let store = AddContactHostingViewStore(obvOwnedIdentity: obvOwnedIdentity) else { assertionFailure(); return nil }
        self.store = store
        let newAvailableApiKeyElements = APIKeyElements()
        self.newAvailableApiKeyElements = newAvailableApiKeyElements
        let rootView = AddContactMainView(store: store,
                                          alreadyScannedOrTappedURL: alreadyScannedOrTappedURL,
                                          dismissAction: dismissAction,
                                          checkSignatureMutualScanUrl: checkSignatureMutualScanUrl,
                                          newAvailableApiKeyElements: newAvailableApiKeyElements)
        super.init(rootView: rootView)
        store.delegate = self
        observeNotifications()
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func installedOlvidAppIsOutdated() {
        ObvMessengerInternalNotification.installedOlvidAppIsOutdated(presentingViewController: self)
            .postOnDispatchQueue()
    }
            
    private func observeNotifications() {
        observationTokens.append(ObvEngineNotificationNew.observeNewAPIKeyElementsForAPIKey(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (_, apiKey, apiKeyStatus, _, apiKeyExpirationDate) in
            self?.newAvailableApiKeyElements.set(apiKeyStatus: apiKeyStatus, apiKeyExpirationDate: apiKeyExpirationDate.value, forApiKey: apiKey)
        })
        observationTokens.append(ObvEngineNotificationNew.observeNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(within: NotificationCenter.default, queue: OperationQueue.main, block: { [weak self] (ownedIdentity, apiKeyStatus, apiPermissions, apiKeyExpirationDate) in
            // We assume that this notification is received as a consequence of the activation by the user of a new API Key.
            // Thus, we mark the `newAvailableApiKeyElements` as active (allowing the LicenseActivationView to perform a visual confirmation and to dismiss the whole flow)
            self?.newAvailableApiKeyElements.setActive()
        }))
    }
    
    
    // AddContactHostingViewStoreDelegate
    
    func userWantsToSearchWithinKeycloak() {
        assert(Thread.isMainThread)
        let vc = KeycloakSearchViewController(ownedCryptoId: store.ownedCryptoId, delegate: self)
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }
    
    @MainActor
    func userSuccessfullyAddKeycloakContact(ownedCryptoId: ObvCryptoId, newContactCryptoId: ObvCryptoId) {
        assert(Thread.isMainThread)
        showHUD(type: .spinner)
        // We want to dismiss this vc and to navigate to the details of the contact. Either this contact is not created yet in DB, or it is already.
        // We need to consider both cases here.
        observationTokens.append(ObvMessengerCoreDataNotification.observePersistedContactWasInserted { contactPermanentID in
            OperationQueue.main.addOperation { [weak self] in
                guard let contact = try? PersistedObvContactIdentity.getManagedObject(withPermanentID: contactPermanentID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
                guard contact.cryptoId == newContactCryptoId && contact.ownedIdentity?.cryptoId == ownedCryptoId else { return }
                let deepLink = ObvDeepLink.contactIdentityDetails(ownedCryptoId: ownedCryptoId, objectPermanentID: contactPermanentID)
                self?.showHUD(type: .checkmark) {
                    self?.dismiss(animated: true) {
                        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                            .postOnDispatchQueue()
                    }
                }
            }
        })
        if let persistedContact = try? PersistedObvContactIdentity.get(contactCryptoId: newContactCryptoId, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) {
            let deepLink = ObvDeepLink.contactIdentityDetails(ownedCryptoId: ownedCryptoId, objectPermanentID: persistedContact.objectPermanentID)
            self.showHUD(type: .checkmark) {
                self.dismiss(animated: true) {
                    ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                        .postOnDispatchQueue()
                }
            }
        }
    }
    
    // KeycloakSearchViewControllerDelegate
    
    func showMyIdButtonTappedAction() {
        assert(Thread.isMainThread)
        presentedViewController?.dismiss(animated: true)
    }
    
    func userSelectedContactOnKeycloakSearchView(ownedCryptoId: ObvCryptoId, userDetails: ObvKeycloakUserDetails) {
        assert(Thread.isMainThread)
        presentedViewController?.dismiss(animated: true)
        store.newKeycloakContactToConfirm(userDetails)
    }
    
}


protocol AddContactHostingViewStoreDelegate: UIViewController {
    func userWantsToSearchWithinKeycloak()
    @MainActor func userSuccessfullyAddKeycloakContact(ownedCryptoId: ObvCryptoId, newContactCryptoId: ObvCryptoId)
    func installedOlvidAppIsOutdated()
}

final class AddContactHostingViewStore: ObservableObject {
    
    @Published var singleOwnedIdentity: SingleIdentity
    @Published var userDetailsOfKeycloakContact: ObvKeycloakUserDetails? = nil
    @Published var isConfirmAddingKeycloakViewPushed: Bool = false
    @Published var addingKeycloakContactFailedAlertIsPresented: Bool = false
    let ownedCryptoId: ObvCryptoId
    let urlIdentityRepresentation: URL
    let obvOwnedIdentity: ObvOwnedIdentity
    let viewForSharingIdentity: AnyView
    private(set) var contactIdentity: PersistedObvContactIdentity? // Set when trying to add a contact that is already present in the local contacts directory

    weak var delegate: AddContactHostingViewStoreDelegate?
    
    init?(obvOwnedIdentity: ObvOwnedIdentity) {
        guard let persistedOwnedIdentity = try? PersistedObvOwnedIdentity.get(persisted: obvOwnedIdentity, within: ObvStack.shared.viewContext) else { assertionFailure(); return nil }
        self.singleOwnedIdentity = SingleIdentity(ownedIdentity: persistedOwnedIdentity)
        self.ownedCryptoId = obvOwnedIdentity.cryptoId
        let genericIdentity = obvOwnedIdentity.getGenericIdentity()
        self.urlIdentityRepresentation = genericIdentity.getObvURLIdentity().urlRepresentation
        self.viewForSharingIdentity = AnyView(ActivityViewControllerForSharingIdentity(genericIdentity: genericIdentity))
        self.obvOwnedIdentity = obvOwnedIdentity
    }
    
    fileprivate func installedOlvidAppIsOutdated() {
        delegate?.installedOlvidAppIsOutdated()
    }
    
    fileprivate func userConfirmedSendInvite(_ urlIdentity: ObvURLIdentity) {
        ObvMessengerInternalNotification.userWantsToSendInvite(ownedIdentity: obvOwnedIdentity, urlIdentity: urlIdentity)
            .postOnDispatchQueue()
    }

    fileprivate func requestAPIKeyElements(_ apiKey: UUID) {
        ObvMessengerInternalNotification.userRequestedAPIKeyStatus(ownedCryptoId: ownedCryptoId, apiKey: apiKey)
            .postOnDispatchQueue()
    }

    fileprivate func userRequestedNewAPIKeyActivation(_ apiKey: UUID) {
        ObvMessengerInternalNotification.userRequestedNewAPIKeyActivation(ownedCryptoId: ownedCryptoId, apiKey: apiKey)
            .postOnDispatchQueue()
    }

    fileprivate func userWantsToSearchWithinKeycloak() {
        delegate?.userWantsToSearchWithinKeycloak()
    }

    func newKeycloakContactToConfirm(_ userDetailsOfKeycloakContact: ObvKeycloakUserDetails) {
        assert(Thread.isMainThread)
        self.userDetailsOfKeycloakContact = userDetailsOfKeycloakContact
        guard let contactIdentity = userDetailsOfKeycloakContact.identity else { assertionFailure(); return }
        guard let contactCryptoId = try? ObvCryptoId(identity: contactIdentity) else { assertionFailure(); return }
        self.contactIdentity = try? PersistedObvContactIdentity.get(contactCryptoId: contactCryptoId, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext)
        withAnimation { isConfirmAddingKeycloakViewPushed = true }
    }
 
    /// This is called when the user taps the "Add to contacts" button on the confirmation screen showing the contact about to be added to the local directory
    func confirmAddingKeycloakContactViewAction() {
        assert(Thread.isMainThread)
        guard let userDetailsOfKeycloakContact = self.userDetailsOfKeycloakContact,
              let userIdentity = userDetailsOfKeycloakContact.identity,
              let userCryptoId = try? ObvCryptoId(identity: userIdentity)
        else {
            self.addingKeycloakContactFailedAlertIsPresented = true
            assertionFailure()
            return
        }
        Task {
            do {
                try await KeycloakManagerSingleton.shared.addContact(ownedCryptoId: ownedCryptoId, userId: userDetailsOfKeycloakContact.id, userIdentity: userIdentity)
                await delegate?.userSuccessfullyAddKeycloakContact(ownedCryptoId: ownedCryptoId, newContactCryptoId: userCryptoId)
            } catch let addContactError as KeycloakManager.AddContactError {
                switch addContactError {
                case .authenticationRequired,
                        .ownedIdentityNotManaged,
                        .badResponse,
                        .userHasCancelled,
                        .keycloakApiRequest,
                        .invalidSignature,
                        .unkownError:
                    addingKeycloakContactFailedAlertIsPresented = true
                case .willSyncKeycloakServerSignatureKey:
                    break
                case .ownedIdentityWasRevoked:
                    ObvMessengerInternalNotification.userOwnedIdentityWasRevokedByKeycloak(ownedCryptoId: ownedCryptoId)
                        .postOnDispatchQueue()
                }
                return
            } catch {
                assertionFailure()
                addingKeycloakContactFailedAlertIsPresented = true
                return
            }
        }
    }
}


final class APIKeyElements: ObservableObject {
    
    let id = UUID()
    var apiKey: UUID?
    @Published var apiKeyStatus: APIKeyStatus?
    @Published var apiKeyExpirationDate: Date?
    @Published var activated: Bool

    init() {
        self.apiKey = nil
        self.apiKeyStatus = nil
        self.apiKeyExpirationDate = nil
        self.activated = false
    }
    
    init(apiKey: UUID, apiKeyStatus: APIKeyStatus, apiKeyExpirationDate: Date?) {
        self.apiKey = apiKey
        self.apiKeyStatus = apiKeyStatus
        self.apiKeyExpirationDate = apiKeyExpirationDate
        self.activated = false
    }
    
    func set(apiKeyStatus: APIKeyStatus, apiKeyExpirationDate: Date?, forApiKey: UUID) {
        assert(Thread.isMainThread)
        guard self.apiKey == apiKey else { return }
        withAnimation {
            self.apiKeyStatus = apiKeyStatus
            self.apiKeyExpirationDate = apiKeyExpirationDate
        }
    }
    
    func setActive() {
        self.activated = true
    }
}


/// This struct wrapps the system's `UIActivityViewController` and configures it properly for sharing the user's
/// owned identity. This wrapping conforms to the `UIViewControllerRepresentable` making it possible to
/// to show it within a SwiftUI view.
struct ActivityViewControllerForSharingIdentity: UIViewControllerRepresentable {
    
    private let activityItems: [Any]
    private let applicationActivities: [UIActivity]? = nil
    
    init(genericIdentity: ObvGenericIdentity) {
        activityItems = [ObvGenericIdentityForSharing(genericIdentity: genericIdentity)]
    }
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityViewControllerForSharingIdentity>) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        controller.excludedActivityTypes = [.addToReadingList, .openInIBooks, .markupAsPDF]
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ActivityViewControllerForSharingIdentity>) {}
    
}


struct AddContactMainView: View {
    
    @ObservedObject var store: AddContactHostingViewStore
    let alreadyScannedOrTappedURL: OlvidURL?
    let dismissAction: () -> Void
    let checkSignatureMutualScanUrl: (ObvMutualScanUrl) -> Bool
    @ObservedObject var newAvailableApiKeyElements: APIKeyElements

    var body: some View {
        AddContactMainInnerView(contact: store.singleOwnedIdentity,
                                ownedCryptoId: store.ownedCryptoId,
                                urlIdentityRepresentation: store.urlIdentityRepresentation,
                                alreadyScannedOrTappedURL: alreadyScannedOrTappedURL,
                                viewForSharingIdentity: store.viewForSharingIdentity,
                                confirmInviteAction: store.userConfirmedSendInvite,
                                dismissAction: dismissAction,
                                installedOlvidAppIsOutdated: store.installedOlvidAppIsOutdated,
                                checkSignatureMutualScanUrl: checkSignatureMutualScanUrl,
                                requestNewAvailableApiKeyElements: store.requestAPIKeyElements,
                                userRequestedNewAPIKeyActivation: store.userRequestedNewAPIKeyActivation,
                                newAvailableApiKeyElements: newAvailableApiKeyElements,
                                userWantsToSearchWithinKeycloak: store.userWantsToSearchWithinKeycloak,
                                userDetailsOfKeycloakContact: store.userDetailsOfKeycloakContact,
                                contactIdentity: store.contactIdentity,
                                isConfirmAddingKeycloakViewPushed: $store.isConfirmAddingKeycloakViewPushed,
                                addingKeycloakContactFailedAlertIsPresented: $store.addingKeycloakContactFailedAlertIsPresented,
                                confirmAddingKeycloakContactViewAction: store.confirmAddingKeycloakContactViewAction)
    }
    
}

/// This SwiftUI view is the main view used to display the user's owned Id. It is the starting point of all methods allowing the user
/// to add a contact to her address book.
///
/// There are two starting points for adding a new contact:
/// - sharing the ownedId (either by using the `ActivityViewControllerForSharingIdentity` or by showing the QR code)
/// - scanning the ID of another user.
fileprivate struct AddContactMainInnerView: View {
    
    let ownedCryptoId: ObvCryptoId
    let singleIdentity: SingleIdentity
    let urlIdentityRepresentation: URL
    let viewForSharingIdentity: AnyView
    let dismissAction: () -> Void
    let installedOlvidAppIsOutdated: () -> Void
    let checkSignatureMutualScanUrl: (ObvMutualScanUrl) -> Bool
    let confirmInviteAction: (ObvURLIdentity) -> Void
    let alreadyScannedOrTappedURL: OlvidURL? /// Instead of setting the `scannedUrlIdentity`, we use this intermediary variable as workaround of an Xcode12/SwiftUI bug. See FB7823148.
    let userDetailsOfKeycloakContact: ObvKeycloakUserDetails? /// Only set if the user to invite is a keycloak user
    let contactIdentity: PersistedObvContactIdentity? /// Set when trying to add a contact that is already present in the local contacts directory
    @Binding var isConfirmAddingKeycloakViewPushed: Bool
    @Binding var addingKeycloakContactFailedAlertIsPresented: Bool

    @State private var isViewForScanningIdPresented = false
    @State private var isAlertPresented = false
    @State private var alertType = AlertType.videoDenied
    @State private var scannedUrlIdentity: ObvURLIdentity?
    @State private var scannedMutualScanUrl: ObvMutualScanUrl?
    @State private var scannedPersistedContact: PersistedObvContactIdentity? /// Set when the scanned contact is already a persisted contact
    @State private var isConfirmInviteViewPushed = false
    @State private var shouldPresentQRCodeScanFailedAlert = false
    @State private var isActionSheetAlternateImportShown = false

    // Only used/set when show the LicenseActivationView
    let requestNewAvailableApiKeyElements: (UUID) -> Void
    let userRequestedNewAPIKeyActivation: (UUID) -> Void
    @ObservedObject var newAvailableApiKeyElements: APIKeyElements
    let userWantsToSearchWithinKeycloak: () -> Void
    let confirmAddingKeycloakContactViewAction: () -> Void

    /// Set when scanning a new configuration
    @State private var serverAndAPIKey: ServerAndAPIKey?
    @State private var betaConfiguration: BetaConfiguration?
    @State private var keycloakConfig: KeycloakConfiguration?

    @Environment(\.sizeCategory) private var sizeCategory

    private enum AlertType {
        case videoRestricted
        case videoDenied
        case qrCodeScanFailed
        case ownedIdentityCopied
        case pastingContactIdentityFailed
        case importedIdentityIsTheOneWeOwn
        case badObvURLIdentitySignature(fullDisplayName: String)
    }
    
    private func showRestrictedVideoAlert() {
        alertType = .videoRestricted
        DispatchQueue.main.async { isAlertPresented = true }
    }
    
    private func showDeniedVideoAlert() {
        alertType = .videoDenied
        DispatchQueue.main.async { isAlertPresented = true }
    }
    
    private func showQrCodeScanFailedAlert() {
        alertType = .qrCodeScanFailed
        DispatchQueue.main.async { isAlertPresented = true }
    }
    
    private func showOwnedIdentityCopiedAlert() {
        alertType = .ownedIdentityCopied
        DispatchQueue.main.async { isAlertPresented = true }
    }
    
    private func showPastingContactIdentityFailedAlert() {
        alertType = .pastingContactIdentityFailed
        DispatchQueue.main.async { isAlertPresented = true }
    }
    
    private func showImportedIdentityIsTheOneWeOwnAlert() {
        alertType = .importedIdentityIsTheOneWeOwn
        DispatchQueue.main.async { isAlertPresented = true }
    }
    
    private func showBadObvURLIdentitySignatureAlert(fullDisplayName: String) {
        alertType = .badObvURLIdentitySignature(fullDisplayName: fullDisplayName)
        // The async is required to make sure the QR code scanner is dismissed before we try to present the alert
        DispatchQueue.main.async { isAlertPresented = true }
    }
    
    init(contact: SingleIdentity, ownedCryptoId: ObvCryptoId, urlIdentityRepresentation: URL, alreadyScannedOrTappedURL: OlvidURL?, viewForSharingIdentity: AnyView, confirmInviteAction: @escaping (ObvURLIdentity) -> Void, dismissAction: @escaping () -> Void, installedOlvidAppIsOutdated: @escaping () -> Void, checkSignatureMutualScanUrl: @escaping (ObvMutualScanUrl) -> Bool, requestNewAvailableApiKeyElements: @escaping (UUID) -> Void, userRequestedNewAPIKeyActivation: @escaping (UUID) -> Void, newAvailableApiKeyElements: APIKeyElements, userWantsToSearchWithinKeycloak: @escaping () -> Void, userDetailsOfKeycloakContact: ObvKeycloakUserDetails?, contactIdentity: PersistedObvContactIdentity?, isConfirmAddingKeycloakViewPushed: Binding<Bool>, addingKeycloakContactFailedAlertIsPresented: Binding<Bool>, confirmAddingKeycloakContactViewAction: @escaping () -> Void) {
        self.ownedCryptoId = ownedCryptoId
        self.singleIdentity = contact
        self.urlIdentityRepresentation = urlIdentityRepresentation
        self.viewForSharingIdentity = viewForSharingIdentity
        self.confirmInviteAction = confirmInviteAction
        self.dismissAction = dismissAction
        self.installedOlvidAppIsOutdated = installedOlvidAppIsOutdated
        self.checkSignatureMutualScanUrl = checkSignatureMutualScanUrl
        self.alreadyScannedOrTappedURL = alreadyScannedOrTappedURL
        self.requestNewAvailableApiKeyElements = requestNewAvailableApiKeyElements
        self.userRequestedNewAPIKeyActivation = userRequestedNewAPIKeyActivation
        self.newAvailableApiKeyElements = newAvailableApiKeyElements
        self.userWantsToSearchWithinKeycloak = userWantsToSearchWithinKeycloak
        self.userDetailsOfKeycloakContact = userDetailsOfKeycloakContact
        self.contactIdentity = contactIdentity
        self._isConfirmAddingKeycloakViewPushed = isConfirmAddingKeycloakViewPushed
        self._addingKeycloakContactFailedAlertIsPresented = addingKeycloakContactFailedAlertIsPresented
        self.confirmAddingKeycloakContactViewAction = confirmAddingKeycloakContactViewAction
    }
    
    private func copyOwnedIdentityToClipboard() {
        UIPasteboard.general.string = urlIdentityRepresentation.absoluteString
        showOwnedIdentityCopiedAlert()
    }
    
    private func pasteContactIdentityFromClipboard() {
        guard let pastedText = UIPasteboard.general.string else {
            showPastingContactIdentityFailedAlert()
            return
        }
        
        // Find all the URLs within the pasted text. The first one "wins".
        let urls = pastedText.extractURLs()
        guard let url = urls.first,
              let olvidURL = OlvidURL(urlRepresentation: url) else {
            showPastingContactIdentityFailedAlert()
            return
        }
        
        simulateScanThenDismissOfTheScannerView(olvidURL: olvidURL, type: .pasted)
    }
    
    private func simulateScanThenDismissOfTheScannerView(olvidURL: OlvidURL, type: ImportType) {
        assert(Thread.isMainThread)
        qrCodeImportedAction(olvidURL: olvidURL, type: type)
        qrCodeScannerWasDismissed()
    }
    
    enum ImportType {
        case scanned
        case pasted
        case scannedOrTappedOutsideFromApp
    }
    
    private func qrCodeImportedAction(olvidURL: OlvidURL, type: ImportType) {
        // This block is called when a QR code has been scanned
        isViewForScanningIdPresented = false

        switch olvidURL.category {
        
        case .openIdRedirect:
            assertionFailure("We expect this kind of Olvid URL to be dealt with before")
            return

        case .configuration(serverAndAPIKey: let serverAndAPIKey, betaConfiguration: let betaConfiguration, keycloakConfig: let keycloakConfig):
            
            // For now, we expect exactly one of the possible config types to be non-nil
            assert([serverAndAPIKey as Any?, betaConfiguration as Any?, keycloakConfig as Any?].filter({ $0 != nil }).count == 1)
            if serverAndAPIKey != nil {
                self.serverAndAPIKey = serverAndAPIKey
            } else if betaConfiguration != nil {
                self.betaConfiguration = betaConfiguration
            } else {
                self.keycloakConfig = keycloakConfig
            }
            
        case .invitation(urlIdentity: let urlIdentity):
            
            // We check that the scanned identity is the one we own
            guard urlIdentity.cryptoId != ownedCryptoId else {
                showImportedIdentityIsTheOneWeOwnAlert()
                return
            }
            self.scannedUrlIdentity = urlIdentity
            // We check whether the contact is already known or not
            guard let persistedOwnedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
            do {
                guard let persistedContact = try PersistedObvContactIdentity.get(cryptoId: urlIdentity.cryptoId, ownedIdentity: persistedOwnedIdentity, whereOneToOneStatusIs: .any) else { return }
                // If we reach this point, the contact is already known
                self.scannedPersistedContact = persistedContact
            } catch {
                assertionFailure()
                return
            }

        case .mutualScan(mutualScanURL: let mutualScanURL):

            guard mutualScanURL.cryptoId != ownedCryptoId else {
                showImportedIdentityIsTheOneWeOwnAlert()
                return
            }

            guard checkSignatureMutualScanUrl(mutualScanURL) else {
                showBadObvURLIdentitySignatureAlert(fullDisplayName: mutualScanURL.fullDisplayName)
                return
            }
            
            self.scannedMutualScanUrl = mutualScanURL
            
            // We check whether the contact is already known or not
            guard let persistedOwnedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
            do {
                guard let persistedContact = try PersistedObvContactIdentity.get(cryptoId: mutualScanURL.cryptoId, ownedIdentity: persistedOwnedIdentity, whereOneToOneStatusIs: .any) else { return }
                // If we reach this point, the contact is already known
                self.scannedPersistedContact = persistedContact
            } catch {
                assertionFailure()
                return
            }

        }
        
    }
    
    
    private func qrCodeScannerWasDismissed() {
        if self.scannedUrlIdentity != nil || self.scannedMutualScanUrl != nil || self.serverAndAPIKey != nil || self.betaConfiguration != nil || self.keycloakConfig != nil {
            if #available(iOS 14, *) {
                withAnimation {
                    self.isConfirmInviteViewPushed = true
                }
            } else {
                // The iOS 14 code bugs on iOS 13, which performs the animation by default (which is not the case of iOS 14)
                self.isConfirmInviteViewPushed = true
            }
        } else if self.shouldPresentQRCodeScanFailedAlert {
            self.shouldPresentQRCodeScanFailedAlert = false
            showQrCodeScanFailedAlert()
        }
    }
    
    
    private func useLandscapeMode(for geometry: GeometryProxy) -> Bool {
        geometry.size.height < geometry.size.width
    }

    private func useSmallScreenMode(for geometry: GeometryProxy) -> Bool {
        if #available(iOS 13.4, *) {
            if sizeCategory.isAccessibilityCategory { return true }
        }
        // Small screen mode for iPhone 6, iPhone 6S, iPhone 7, iPhone 8, iPhone SE (2016)
        return max(geometry.size.height, geometry.size.width) < 510
    }
    
    private func typicalPadding(for geometry: GeometryProxy) -> CGFloat {
        useSmallScreenMode(for: geometry) ? 8 : 16
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(AppTheme.shared.colorScheme.systemBackground)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .edgesIgnoringSafeArea(.all)
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        Card(singleIdentity: singleIdentity,
                             urlIdentityRepresentation: urlIdentityRepresentation,
                             viewForSharingIdentity: viewForSharingIdentity,
                             useLandscapeMode: useLandscapeMode(for: geometry),
                             useSmallScreenMode: useSmallScreenMode(for: geometry),
                             typicalPadding: typicalPadding(for: geometry))
                            .padding(.bottom, typicalPadding(for: geometry))
                            .actionSheet(isPresented: $isActionSheetAlternateImportShown) {
                                ActionSheet(title: Text("More invitations methods"),
                                            message: nil,
                                            buttons: [
                                                ActionSheet.Button.default(Text("PASTE_CONTACT_ID_FROM_CLIPBOARD"), action: pasteContactIdentityFromClipboard),
                                                ActionSheet.Button.default(Text("COPY_MY_ID_TO_CLIPBOARD"), action: copyOwnedIdentityToClipboard),
                                                ActionSheet.Button.cancel(),
                                            ])
                            }
                        Spacer(minLength: 0)
                        HStack {
                            Spacer()
                            if !useLandscapeMode(for: geometry) {
                                Text("SCANNING_CONTACT_ID_ALLOWS_YOU_TO_INVITE_THEM_NOW")
                                    .lineLimit(nil)
                                    .multilineTextAlignment(.center)
                                    .font(useSmallScreenMode(for: geometry) ? .system(size: 19) : .body)
                                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, typicalPadding(for: geometry))
                        .padding(.bottom, typicalPadding(for: geometry))
                        AddContactMainInnerViewNavigationLinks(newAvailableApiKeyElements: newAvailableApiKeyElements,
                                                               isConfirmInviteViewPushed: $isConfirmInviteViewPushed,
                                                               isConfirmAddingKeycloakViewPushed: $isConfirmAddingKeycloakViewPushed,
                                                               addingKeycloakContactFailedAlertIsPresented: $addingKeycloakContactFailedAlertIsPresented,
                                                               scannedUrlIdentity: scannedUrlIdentity,
                                                               scannedMutualScanUrl: scannedMutualScanUrl,
                                                               ownedCryptoId: ownedCryptoId,
                                                               scannedPersistedContact: scannedPersistedContact,
                                                               serverAndAPIKey: serverAndAPIKey,
                                                               betaConfiguration: betaConfiguration,
                                                               keycloakConfig: keycloakConfig,
                                                               userDetailsOfKeycloakContact: userDetailsOfKeycloakContact,
                                                               contactIdentity: contactIdentity,
                                                               requestNewAvailableApiKeyElements: requestNewAvailableApiKeyElements,
                                                               userRequestedNewAPIKeyActivation: userRequestedNewAPIKeyActivation,
                                                               dismissAction: dismissAction,
                                                               installedOlvidAppIsOutdated: installedOlvidAppIsOutdated,
                                                               ownedIdentityIsKeycloakManaged: singleIdentity.isKeycloakManaged,
                                                               confirmInviteAction: confirmInviteAction,
                                                               confirmAddingKeycloakContactViewAction: confirmAddingKeycloakContactViewAction)
                        HStack {
                            OlvidButton(style: .blue,
                                        title: Text("SCAN"),
                                        systemIcon: .qrcodeViewfinder,
                                        action: {
                                            self.scannedUrlIdentity = nil
                                            self.scannedMutualScanUrl = nil
                                            self.scannedPersistedContact = nil
                                            self.serverAndAPIKey = nil
                                            self.keycloakConfig = nil
                                            self.isConfirmInviteViewPushed = false
                                            self.isAlertPresented = false
                                            self.shouldPresentQRCodeScanFailedAlert = false
                                            switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
                                            case .authorized:
                                                isViewForScanningIdPresented.toggle()
                                            case .notDetermined:
                                                AVCaptureDevice.requestAccess(for: .video) { granted in
                                                    if granted {
                                                        DispatchQueue.main.async {
                                                            self.isViewForScanningIdPresented.toggle()
                                                        }
                                                    }
                                                }
                                            case .restricted:
                                                self.showRestrictedVideoAlert()
                                            case .denied:
                                                self.showDeniedVideoAlert()
                                            @unknown default:
                                                return
                                            }
                                        })
                            if singleIdentity.isKeycloakManaged {
                                OlvidButton.init(style: .blue,
                                                 title: Text(CommonString.Word.Directory),
                                                 systemIcon: .serverRack) {
                                    userWantsToSearchWithinKeycloak()
                                }
                            }
                        }
                        .padding(.horizontal, typicalPadding(for: geometry))
                        .sheet(isPresented: $isViewForScanningIdPresented, onDismiss: {
                            qrCodeScannerWasDismissed()
                        }, content: {
                            ScannerView(
                                buttonType: .showMyId,
                                buttonAction: {
                                    isViewForScanningIdPresented = false
                                }, qrCodeScannedAction: { olvidURL in
                                    self.qrCodeImportedAction(olvidURL: olvidURL, type: .scanned)
                                }
                            )
                        })
                        .alert(isPresented: $isAlertPresented) {
                            switch self.alertType {
                            case .videoDenied:
                                return Alert(title: Text("Authorization Required"),
                                             message: Text("Olvid is not authorized to access the camera. You can change this setting within the Settings app."),
                                             primaryButton: Alert.Button.default(Text("Open Settings"), action: {
                                                if let appSettings = URL(string: UIApplication.openSettingsURLString) {
                                                    UIApplication.shared.open(appSettings, options: [:])
                                                } else {
                                                    self.isAlertPresented = false
                                                }
                                             }),
                                             secondaryButton: Alert.Button.cancel())
                            case .videoRestricted:
                                return Alert(title: Text("Authorization Required"),
                                             message: Text("Olvid is not authorized to access the camera. Because your settings are restricted, there is nothing we can do about this. Please contact your administrator."),
                                             dismissButton: Alert.Button.cancel())
                            case .qrCodeScanFailed:
                                return Alert(title: Text(MainFlowViewController.Strings.BadScannedQRCodeAlert.title),
                                             message: Text(MainFlowViewController.Strings.BadScannedQRCodeAlert.message),
                                             dismissButton: Alert.Button.cancel())
                            case .ownedIdentityCopied:
                                return Alert(title: Text("YOUR_ID_WAS_COPIED_TO_CLIPBOARD"),
                                             message: nil,
                                             dismissButton: Alert.Button.default(Text("Ok")))
                            case .pastingContactIdentityFailed:
                                return Alert(title: Text("Oops..."),
                                             message: Text("What you pasted doesn't seem to be an Olvid identity 🧐"),
                                             dismissButton: Alert.Button.default(Text("Ok")))
                            case .importedIdentityIsTheOneWeOwn:
                                return Alert(title: Text("THIS_ID_IS_THE_ONE_YOU_OWN"),
                                             message: nil,
                                             dismissButton: Alert.Button.default(Text("Ok")))
                            case .badObvURLIdentitySignature(fullDisplayName: let fullDisplayName):
                                return Alert(title: Text("INVALID_QR_CODE"),
                                             message: Text("IMPOSSIBLE_TO_ADD_\(fullDisplayName)_WITH_THIS_QR_CODE"),
                                             dismissButton: Alert.Button.default(Text("Ok")))
                            }
                        }
                    }
                    .padding(.vertical, typicalPadding(for: geometry))
                }
            }
            .navigationBarTitle(Text("Add new contact"), displayMode: .inline)
            .navigationBarItems(leading:
                                    Button(action: dismissAction,
                                           label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(Font.system(size: 24, weight: .semibold, design: .default))
                                                .foregroundColor(Color(AppTheme.shared.colorScheme.tertiaryLabel))
                                           }),
                                trailing:
                                    Button(action: { isActionSheetAlternateImportShown.toggle() },
                                           label: {
                                            Image(systemName: "ellipsis.circle")
                                                .font(Font.system(size: 24, weight: .semibold, design: .default))
                                                .foregroundColor(Color(AppTheme.shared.colorScheme.tertiaryLabel))
                                           })
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            if let olvidURL = alreadyScannedOrTappedURL {
                // The async fixes an animation glitch
                DispatchQueue.main.async {
                    qrCodeImportedAction(olvidURL: olvidURL, type: .scannedOrTappedOutsideFromApp)
                    qrCodeScannerWasDismissed()
                }
            }
        }
    }

}


fileprivate struct AddContactMainInnerViewNavigationLinks: View {
    
    @ObservedObject var newAvailableApiKeyElements: APIKeyElements
    @Binding var isConfirmInviteViewPushed: Bool
    @Binding var isConfirmAddingKeycloakViewPushed: Bool
    @Binding var addingKeycloakContactFailedAlertIsPresented: Bool
    let scannedUrlIdentity: ObvURLIdentity?
    let scannedMutualScanUrl: ObvMutualScanUrl?
    let ownedCryptoId: ObvCryptoId
    let scannedPersistedContact: PersistedObvContactIdentity?
    let serverAndAPIKey: ServerAndAPIKey?
    let betaConfiguration: BetaConfiguration?
    let keycloakConfig: KeycloakConfiguration?
    let userDetailsOfKeycloakContact: ObvKeycloakUserDetails? /// Only set if the user to invite is a keycloak user
    let contactIdentity: PersistedObvContactIdentity? /// Set when trying to add a keycloak contact that is already present in the local contacts directory
    let requestNewAvailableApiKeyElements: (UUID) -> Void
    let userRequestedNewAPIKeyActivation: (UUID) -> Void
    let dismissAction: () -> Void
    let installedOlvidAppIsOutdated: () -> Void
    let ownedIdentityIsKeycloakManaged: Bool
    let confirmInviteAction: (ObvURLIdentity) -> Void
    let confirmAddingKeycloakContactViewAction: () -> Void
    
    var body: some View {
        if let scannedUrlIdentity = self.scannedUrlIdentity {
            NavigationLink(
                destination: SendInviteOrShowSecondQRCodeView(ownedCryptoId: ownedCryptoId,
                                                              urlIdentity: scannedUrlIdentity,
                                                              contactIdentity: scannedPersistedContact,
                                                              confirmInviteAction: self.confirmInviteAction,
                                                              cancelInviteAction: { self.isConfirmInviteViewPushed = false }),
                isActive: $isConfirmInviteViewPushed,
                label: { EmptyView() }
            )
        } else if let scannedMutualScanUrl = self.scannedMutualScanUrl {
            NavigationLink(
                destination: ConfirmAddContactView(ownedCryptoId: ownedCryptoId,
                                                   mutualScanUrl: scannedMutualScanUrl,
                                                   contactIdentity: scannedPersistedContact),
                isActive: $isConfirmInviteViewPushed,
                label: { EmptyView() }
            )
        } else if let userDetailsOfKeycloakContact = self.userDetailsOfKeycloakContact {
            NavigationLink(
                destination: ConfirmAddingKeycloakContactView(contactUserDetails: userDetailsOfKeycloakContact,
                                                              contactIdentity: contactIdentity,
                                                              addingKeycloakContactFailedAlertIsPresented: $addingKeycloakContactFailedAlertIsPresented,
                                                              confirmAddingKeycloakContactViewAction: self.confirmAddingKeycloakContactViewAction,
                                                              cancelAddingKeycloakContactViewAction: { self.isConfirmAddingKeycloakViewPushed = false }),
                isActive: $isConfirmAddingKeycloakViewPushed,
                label: { EmptyView() }
            )
        } else if let serverAndAPIKey = self.serverAndAPIKey,
                  let persistedOwnedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) {
            NavigationLink(
                destination: LicenseActivationView(ownedCryptoId: ownedCryptoId,
                                                   serverAndAPIKey: serverAndAPIKey,
                                                   currentApiKeyStatus: persistedOwnedIdentity.apiKeyStatus,
                                                   currentApiKeyExpirationDate: persistedOwnedIdentity.apiKeyExpirationDate,
                                                   ownedIdentityIsKeycloakManaged: ownedIdentityIsKeycloakManaged,
                                                   requestNewAvailableApiKeyElements: requestNewAvailableApiKeyElements,
                                                   userRequestedNewAPIKeyActivation: userRequestedNewAPIKeyActivation,
                                                   newAvailableApiKeyElements: newAvailableApiKeyElements,
                                                   dismissAction: dismissAction),
                isActive: $isConfirmInviteViewPushed,
                label: { EmptyView() }
            )
        } else if let betaConfiguration = self.betaConfiguration {
            NavigationLink(destination: BetaConfigurationActivationView(betaConfiguration: betaConfiguration, dismissAction: dismissAction),
                           isActive: $isConfirmInviteViewPushed,
                           label: { EmptyView() })
        } else if let keycloakConfig = self.keycloakConfig {
            NavigationLink(
                destination: BindingUseIdentityProviderView(keycloakConfig: keycloakConfig, ownedCryptoId: ownedCryptoId, dismissAction: dismissAction, installedOlvidAppIsOutdated: installedOlvidAppIsOutdated),
                isActive: $isConfirmInviteViewPushed,
                label: { EmptyView() })
        }
    }
    
}



/// This SwiftUI view is exclusively used within the `AddContactMainInnerView` and shows the owned Id, the button allowing to share it,
/// and the corresponding QR code.
fileprivate struct Card: View {
    
    @Environment(\.horizontalSizeClass) var sizeClass
    
    let singleIdentity: SingleIdentity
    let urlIdentityRepresentation: URL
    let viewForSharingIdentity: AnyView
    let useLandscapeMode: Bool
    let useSmallScreenMode: Bool
    let typicalPadding: CGFloat
    @State private var isShareSheetPresented = false
    @State private var showQRCodeFullScreen = false
    
    private let shadowColor = Color(.displayP3, white: 0.0, opacity: 0.1)
    
    private var colorScheme: AppThemeSemanticColorScheme { AppTheme.shared.colorScheme }
    
    var body: some View {
        HStackOrVStack(useHStack: useLandscapeMode) {
            Group {
                if !showQRCodeFullScreen {
                    IdentityDescriptionBlockView(singleIdentity: singleIdentity,
                                                 isShareSheetPresented: $isShareSheetPresented,
                                                 viewForSharingContact: viewForSharingIdentity,
                                                 smallScreenMode: useSmallScreenMode,
                                                 showHelpText: !useLandscapeMode,
                                                 typicalPadding: typicalPadding)
                } else {
                    Spacer()
                }
                QRCodeBlockView(urlIdentityRepresentation: urlIdentityRepresentation, typicalPadding: typicalPadding)
                    .padding(.horizontal, showQRCodeFullScreen ? 0 : 40)
                    .padding(.bottom, showQRCodeFullScreen ? 0 : typicalPadding)
                    .padding(.top, showQRCodeFullScreen || useLandscapeMode ? typicalPadding : 0)
                    .environment(\.colorScheme, .light)
                if showQRCodeFullScreen {
                    Spacer()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16.0)
                .opacity(showQRCodeFullScreen ? 0 : 1)
                .foregroundColor(Color(colorScheme.secondarySystemBackground))
                .padding(.horizontal, typicalPadding)
                .shadow(color: shadowColor, radius: 10)
        )
        .overlay(
            Image(systemIcon: .handTap)
                .if(useSmallScreenMode) {
                    $0.font(.system(size: 25))
                }
                .foregroundColor(showQRCodeFullScreen ? .clear : .secondary)
                .padding(.trailing, typicalPadding * 2)
                .padding(.bottom, typicalPadding),
            alignment: .bottomTrailing
        )
        .onTapGesture(count: 1, perform: {
            withAnimation(.easeInOut(duration: 0.25)) {
                showQRCodeFullScreen.toggle()
            }
        })
    }
}


fileprivate struct IdentityDescriptionBlockView: View {
    
    let singleIdentity: SingleIdentity
    @Binding var isShareSheetPresented: Bool
    let viewForSharingContact: AnyView
    let smallScreenMode: Bool
    let showHelpText: Bool
    let typicalPadding: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: typicalPadding) {
            HStack {
                IdentityCardContentView(model: singleIdentity)
                Spacer()
            }
            .padding(.horizontal, 8 + 2*typicalPadding)
            .padding(.top, typicalPadding)
            OlvidButton(style: .blue, title: Text("SHARE_MY_ID"), systemIcon: .squareAndArrowUp ) {
                isShareSheetPresented.toggle()
            }
            .fixedSize(horizontal: false, vertical: true)
            .sheet(isPresented: $isShareSheetPresented) {
                viewForSharingContact
                    .edgesIgnoringSafeArea(.all)
            }
            .padding(.horizontal, 8 + 2*typicalPadding)
            HStack {
                Spacer()
                if showHelpText {
                    Text("SHARING_YOUR_ID_ALLOWS_OTHERS_TO_INVITE_YOU_REMOTELY")
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(nil)
                        .multilineTextAlignment(.center)
                        .font(smallScreenMode ? .system(size: 19) : .body)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                }
                Spacer()
            }
            .padding(.horizontal, 8 + 2*typicalPadding)
        }
    }
    
}


struct QRCodeBlockView: View {
    
    let urlIdentityRepresentation: URL? // If nil, this view will never show a QR code (see the technique used in ConfirmInviteView)
    let typicalPadding: CGFloat
    @State private var qrCodeImage: Image?
    
    private let shadowColor = Color(.displayP3, white: 0.0, opacity: 0.1)
    
    private func generateQrCodeUIImage() {
        assert(Thread.isMainThread)
        DispatchQueue(label: "Queue for generating QR code").async {
            guard let url = urlIdentityRepresentation else { return }
            guard let qrCode = url.generateQRCode2() else { assertionFailure(); return }
            DispatchQueue.main.async {
                withAnimation {
                    qrCodeImage = Image(uiImage: qrCode)
                }
            }
        }
    }
    
    var body: some View {
        HStack {
            Spacer()
            ZStack(alignment: Alignment(horizontal: .center, vertical: .center)) {
                RoundedRectangle(cornerRadius: 10.0)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondarySystemBackground))
                    .aspectRatio(1.0, contentMode: .fit)
                if let qrCodeImage = self.qrCodeImage {
                    ZStack(alignment: .center) {
                        qrCodeImage
                            .interpolation(.none)
                            .resizable()
                            .aspectRatio(1.0, contentMode: .fit)
                            .padding(.all, typicalPadding / 2)
                        Image("badge-for-qrcode")
                            .resizable()
                            .frame(width: 28, height: 28, alignment: .center)
                            .shadow(color: shadowColor, radius: 10)
                    }
                } else {
                    ObvProgressView().onAppear {
                        generateQrCodeUIImage()
                    }
                }
            }
            Spacer()
        }
    }
    
}

struct AddContactMainInnerView_Previews: PreviewProvider {
    
    private static let identity1 = SingleIdentity(firstName: "Joyce",
                                                  lastName: "Lathrop",
                                                  position: "Happiness manager",
                                                  company: "Olvid",
                                                  isKeycloakManaged: false,
                                                  showGreenShield: false,
                                                  showRedShield: false,
                                                  identityColors: nil,
                                                  photoURL: nil)
    
    private static let identity2 = SingleIdentity(firstName: "Joyce",
                                                  lastName: "Lathrop",
                                                  position: "Happiness manager",
                                                  company: "Olvid",
                                                  isKeycloakManaged: false,
                                                  showGreenShield: false,
                                                  showRedShield: false,
                                                  identityColors: nil,
                                                  photoURL: nil)
    
    private static let identityAsURL = URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!
    
    private static let identity = ObvURLIdentity(urlRepresentation: identityAsURL)!
    
    static var previews: some View {
        Group {
            AddContactMainInnerView(contact: identity2,
                                    ownedCryptoId: identity.cryptoId,
                                    urlIdentityRepresentation: URL(string: "https://olvid.io")!,
                                    alreadyScannedOrTappedURL: nil,
                                    viewForSharingIdentity: AnyView(Text("Placeholder view for sharing my id")),
                                    confirmInviteAction: { _ in },
                                    dismissAction: {},
                                    installedOlvidAppIsOutdated: {},
                                    checkSignatureMutualScanUrl: { _ in false },
                                    requestNewAvailableApiKeyElements: { _ in },
                                    userRequestedNewAPIKeyActivation: { _ in },
                                    newAvailableApiKeyElements: APIKeyElements(),
                                    userWantsToSearchWithinKeycloak: {},
                                    userDetailsOfKeycloakContact: nil,
                                    contactIdentity: nil,
                                    isConfirmAddingKeycloakViewPushed: .constant(false),
                                    addingKeycloakContactFailedAlertIsPresented: .constant(false),
                                    confirmAddingKeycloakContactViewAction: {})
            AddContactMainInnerView(contact: identity1,
                                    ownedCryptoId: identity.cryptoId,
                                    urlIdentityRepresentation: URL(string: "https://olvid.io")!,
                                    alreadyScannedOrTappedURL: nil,
                                    viewForSharingIdentity: AnyView(Text("Placeholder view for sharing my id")),
                                    confirmInviteAction: { _ in },
                                    dismissAction: {},
                                    installedOlvidAppIsOutdated: {},
                                    checkSignatureMutualScanUrl: { _ in false },
                                    requestNewAvailableApiKeyElements: { _ in },
                                    userRequestedNewAPIKeyActivation: { _ in },
                                    newAvailableApiKeyElements: APIKeyElements(),
                                    userWantsToSearchWithinKeycloak: {},
                                    userDetailsOfKeycloakContact: nil,
                                    contactIdentity: nil,
                                    isConfirmAddingKeycloakViewPushed: .constant(false),
                                    addingKeycloakContactFailedAlertIsPresented: .constant(false),
                                    confirmAddingKeycloakContactViewAction: {})
                .environment(\.colorScheme, .dark)
            AddContactMainInnerView(contact: identity2,
                                    ownedCryptoId: identity.cryptoId,
                                    urlIdentityRepresentation: URL(string: "https://olvid.io")!,
                                    alreadyScannedOrTappedURL: nil,
                                    viewForSharingIdentity: AnyView(Text("Placeholder view for sharing my id")),
                                    confirmInviteAction: { _ in },
                                    dismissAction: {},
                                    installedOlvidAppIsOutdated: {},
                                    checkSignatureMutualScanUrl: { _ in false },
                                    requestNewAvailableApiKeyElements: { _ in },
                                    userRequestedNewAPIKeyActivation: { _ in },
                                    newAvailableApiKeyElements: APIKeyElements(),
                                    userWantsToSearchWithinKeycloak: {},
                                    userDetailsOfKeycloakContact: nil,
                                    contactIdentity: nil,
                                    isConfirmAddingKeycloakViewPushed: .constant(false),
                                    addingKeycloakContactFailedAlertIsPresented: .constant(false),
                                    confirmAddingKeycloakContactViewAction: {})
                .environment(\.colorScheme, .dark)
            AddContactMainInnerView(contact: identity2,
                                    ownedCryptoId: identity.cryptoId,
                                    urlIdentityRepresentation: URL(string: "https://olvid.io")!,
                                    alreadyScannedOrTappedURL: nil,
                                    viewForSharingIdentity: AnyView(Text("Placeholder view for sharing my id")),
                                    confirmInviteAction: { _ in },
                                    dismissAction: {},
                                    installedOlvidAppIsOutdated: {},
                                    checkSignatureMutualScanUrl: { _ in false },
                                    requestNewAvailableApiKeyElements: { _ in },
                                    userRequestedNewAPIKeyActivation: { _ in },
                                    newAvailableApiKeyElements: APIKeyElements(),
                                    userWantsToSearchWithinKeycloak: {},
                                    userDetailsOfKeycloakContact: nil,
                                    contactIdentity: nil,
                                    isConfirmAddingKeycloakViewPushed: .constant(false),
                                    addingKeycloakContactFailedAlertIsPresented: .constant(false),
                                    confirmAddingKeycloakContactViewAction: {})
                .environment(\.colorScheme, .dark)
                .environment(\.locale, .init(identifier: "fr"))
            AddContactMainInnerView(contact: identity2,
                                    ownedCryptoId: identity.cryptoId,
                                    urlIdentityRepresentation: URL(string: "https://olvid.io")!,
                                    alreadyScannedOrTappedURL: nil,
                                    viewForSharingIdentity: AnyView(Text("Placeholder view for sharing my id")),
                                    confirmInviteAction: { _ in },
                                    dismissAction: {},
                                    installedOlvidAppIsOutdated: {},
                                    checkSignatureMutualScanUrl: { _ in false },
                                    requestNewAvailableApiKeyElements: { _ in },
                                    userRequestedNewAPIKeyActivation: { _ in },
                                    newAvailableApiKeyElements: APIKeyElements(),
                                    userWantsToSearchWithinKeycloak: {},
                                    userDetailsOfKeycloakContact: nil,
                                    contactIdentity: nil,
                                    isConfirmAddingKeycloakViewPushed: .constant(false),
                                    addingKeycloakContactFailedAlertIsPresented: .constant(false),
                                    confirmAddingKeycloakContactViewAction: {})
                .environment(\.colorScheme, .dark)
                .environment(\.locale, .init(identifier: "fr"))
                .previewDevice(PreviewDevice(rawValue: "iPhone XS"))
            AddContactMainInnerView(contact: identity2,
                                    ownedCryptoId: identity.cryptoId,
                                    urlIdentityRepresentation: URL(string: "https://olvid.io")!,
                                    alreadyScannedOrTappedURL: nil,
                                    viewForSharingIdentity: AnyView(Text("Placeholder view for sharing my id")),
                                    confirmInviteAction: { _ in },
                                    dismissAction: {},
                                    installedOlvidAppIsOutdated: {},
                                    checkSignatureMutualScanUrl: { _ in false },
                                    requestNewAvailableApiKeyElements: { _ in },
                                    userRequestedNewAPIKeyActivation: { _ in },
                                    newAvailableApiKeyElements: APIKeyElements(),
                                    userWantsToSearchWithinKeycloak: {},
                                    userDetailsOfKeycloakContact: nil,
                                    contactIdentity: nil,
                                    isConfirmAddingKeycloakViewPushed: .constant(false),
                                    addingKeycloakContactFailedAlertIsPresented: .constant(false),
                                    confirmAddingKeycloakContactViewAction: {})
                .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
                .previewLayout(.fixed(width: 320, height: 568))
        }
    }
}

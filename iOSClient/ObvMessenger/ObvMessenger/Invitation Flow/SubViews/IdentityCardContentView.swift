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
import ObvEngine
import CoreData
import ObvTypes
import ObvMetaManager
import Combine

class SingleIdentity: Identifiable, Hashable, ObservableObject {
    
    let id = UUID()
    @Published var firstName: String
    @Published var lastName: String
    @Published var position: String
    @Published var company: String
    @Published var isKeycloakManaged: Bool
    @Published var showGreenShield: Bool
    @Published var showRedShield: Bool
    @Published fileprivate(set) var photoURL: URL?

    fileprivate var initialHash: Int
    let identityColors: (background: UIColor, text: UIColor)?

    /// If set, the configuration will be shown on screen
    let serverAndAPIKeyToShow: ServerAndAPIKey?

    /// This is set when, and only when, using an identity server during onboarding.
    let keycloakDetails: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff)?

    fileprivate var observationTokens = [NSObjectProtocol]()
    fileprivate var keyValueObservations = [NSKeyValueObservation]()

    var hasChanged: Bool { initialHash != hashValue }

    /// This is set only when using the appropriate initializer.
    private let ownedIdentity: PersistedObvOwnedIdentity?
    
    var ownCryptoId: ObvCryptoId? {
        ownedIdentity?.cryptoId
    }
    
    /// This is used when showing an identity we just scanned. In that case, there is not much we can do
    convenience init(urlIdentity: ObvURLIdentity) {
        self.init(firstName: urlIdentity.fullDisplayName,
                  lastName: nil,
                  position: nil,
                  company: nil,
                  isKeycloakManaged: false,
                  showGreenShield: false,
                  showRedShield: false,
                  identityColors: urlIdentity.cryptoId.colors,
                  photoURL: nil)
    }
    
    
    /// This is used after the second QR code is scanned in a mutual scan protocol. Again, like with the initializer
    /// with an ObvURLIdentity, there is not much we can do
    convenience init(mutualScanUrl: ObvMutualScanUrl) {
        self.init(firstName: mutualScanUrl.fullDisplayName,
                  lastName: nil,
                  position: nil,
                  company: nil,
                  isKeycloakManaged: false,
                  showGreenShield: false,
                  showRedShield: false,
                  identityColors: mutualScanUrl.cryptoId.colors,
                  photoURL: nil)
    }
    
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    init(firstName: String?, lastName: String?, position: String?, company: String?, isKeycloakManaged: Bool, showGreenShield: Bool, showRedShield: Bool, identityColors: (background: UIColor, text: UIColor)?, photoURL: URL?, ownedIdentity: PersistedObvOwnedIdentity? = nil, serverAndAPIKeyToShow: ServerAndAPIKey? = nil, keycloakDetails: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff)? = nil) {
        self.firstName = firstName ?? ""
        self.lastName = lastName ?? ""
        self.position = position ?? ""
        self.company = company ?? ""
        self.photoURL = photoURL
        self.isKeycloakManaged = isKeycloakManaged
        self.showGreenShield = showGreenShield
        self.showRedShield = showRedShield
        self.identityColors = identityColors
        self.ownedIdentity = ownedIdentity
        self.serverAndAPIKeyToShow = serverAndAPIKeyToShow
        self.keycloakDetails = keycloakDetails

        self.initialHash = 0
        self.initialHash = hashValue
    }
    
    convenience init(genericIdentity: ObvGenericIdentity) {
        let coreDetails = genericIdentity.currentIdentityDetails.coreDetails
        self.init(firstName: coreDetails.firstName,
                  lastName: coreDetails.lastName,
                  position: coreDetails.position,
                  company: coreDetails.company,
                  isKeycloakManaged: false,
                  showGreenShield: false,
                  showRedShield: false,
                  identityColors: genericIdentity.cryptoId.colors,
                  photoURL: genericIdentity.currentIdentityDetails.photoURL)
    }
    
    convenience init(ownedIdentity: PersistedObvOwnedIdentity) {
        assert(Thread.isMainThread)
        let coreDetails = ownedIdentity.identityCoreDetails
        self.init(firstName: coreDetails.firstName ?? "",
                  lastName: coreDetails.lastName ?? "",
                  position: coreDetails.position ?? "",
                  company: coreDetails.company ?? "",
                  isKeycloakManaged: ownedIdentity.isKeycloakManaged,
                  showGreenShield: ownedIdentity.isKeycloakManaged,
                  showRedShield: false,
                  identityColors: ownedIdentity.cryptoId.colors,
                  photoURL: ownedIdentity.photoURL,
                  ownedIdentity: ownedIdentity)
        observeViewContextDidChange()
        observeNewCachedProfilePictureCandidateNotifications()
    }

    convenience init(contactIdentity: PersistedObvContactIdentity) {
        assert(Thread.isMainThread)
        let coreDetails = contactIdentity.identityCoreDetails
        self.init(firstName: coreDetails.firstName ?? "",
                  lastName: coreDetails.lastName ?? "",
                  position: coreDetails.position ?? "",
                  company: coreDetails.company ?? "",
                  isKeycloakManaged: contactIdentity.isCertifiedByOwnKeycloak,
                  showGreenShield: contactIdentity.isCertifiedByOwnKeycloak,
                  showRedShield: false,
                  identityColors: contactIdentity.cryptoId.colors,
                  photoURL: contactIdentity.photoURL,
                  ownedIdentity: contactIdentity.ownedIdentity)
    }
    
    /// This initializer is used during the standard onboarding procedure, when *no* identity server is used
    convenience init(serverAndAPIKeyToShow: ServerAndAPIKey?, identityDetails: ObvIdentityCoreDetails?) {
        self.init(firstName: identityDetails?.firstName ?? "",
                  lastName: identityDetails?.lastName ?? "",
                  position: identityDetails?.position ?? "",
                  company: identityDetails?.company ?? "",
                  isKeycloakManaged: false,
                  showGreenShield: false,
                  showRedShield: false,
                  identityColors: nil,
                  photoURL: nil,
                  serverAndAPIKeyToShow: serverAndAPIKeyToShow)
        observeNewCachedProfilePictureCandidateNotifications()
    }
    
    /// This initializer is used during the standard onboarding procedure when using an identity server
    convenience init(keycloakDetails: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff)) {
        assert(Thread.isMainThread)
        let keycloakUserDetailsAndStuff = keycloakDetails.keycloakUserDetailsAndStuff
        let apiKey = keycloakUserDetailsAndStuff.apiKey ?? ObvMessengerConstants.hardcodedAPIKey!
        let serverAndAPIKeyToShow = ServerAndAPIKey(server: keycloakUserDetailsAndStuff.server, apiKey: apiKey)
        self.init(firstName: keycloakUserDetailsAndStuff.firstName ?? "",
                  lastName: keycloakUserDetailsAndStuff.lastName ?? "",
                  position: keycloakUserDetailsAndStuff.position ?? "",
                  company: keycloakUserDetailsAndStuff.company ?? "",
                  isKeycloakManaged: true,
                  showGreenShield: true,
                  showRedShield: false,
                  identityColors: nil,
                  photoURL: nil,
                  serverAndAPIKeyToShow: serverAndAPIKeyToShow,
                  keycloakDetails: keycloakDetails)
        observeNewCachedProfilePictureCandidateNotifications()
    }

    var profilePicture: UIImage? {
        guard let photoURL = self.photoURL else { return nil }
        return UIImage(contentsOfFile: photoURL.path)
    }

    var editPictureMode: CircleAndTitlesEditionMode {
        .picture { [weak self] image in self?.setProfilePicture(image) }
    }

    fileprivate func setProfilePicture(_ newValue: UIImage?) {
        assert(Thread.isMainThread)
        guard let value = newValue else {
            withAnimation {
                self.photoURL = nil
            }
            return
        }
        ObvMessengerInternalNotification.newProfilePictureCandidateToCache(requestUUID: id, profilePicture: value)
            .postOnDispatchQueue()
    }

    private func setPublishedVariables(with ownedIdentity: PersistedObvOwnedIdentity) {
        let coreDetails = ownedIdentity.identityCoreDetails
        self.firstName = coreDetails.firstName ?? ""
        self.lastName = coreDetails.lastName ?? ""
        self.position = coreDetails.position ?? ""
        self.company = coreDetails.company ?? ""
        if self.photoURL != ownedIdentity.photoURL {
            self.photoURL = ownedIdentity.photoURL
        }
        self.isKeycloakManaged = ownedIdentity.isKeycloakManaged
        self.showGreenShield = ownedIdentity.isKeycloakManaged
    }
    
    fileprivate func setTrustedVariables(with contact: PersistedObvContactIdentity) {
        let coreDetails = contact.identityCoreDetails
        self.firstName = coreDetails.firstName ?? ""
        self.lastName = coreDetails.lastName ?? ""
        self.position = coreDetails.position ?? ""
        self.company = coreDetails.company ?? ""
        if self.photoURL != contact.photoURL {
            self.photoURL = contact.photoURL
        }
    }

    func circledTextView(_ components: [String?]) -> Text? {
        let component = components
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
            .first
        if let char = component?.first {
            return Text(String(char))
        } else {
            return nil
        }
    }

    fileprivate var imageSystemName: String { "person" }

    private func observeViewContextDidChange() {
        let NotificationName = Notification.Name.NSManagedObjectContextObjectsDidChange
        observationTokens.append(NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { [weak self] (notification) in
            guard Thread.isMainThread else { return }
            guard let context = notification.object as? NSManagedObjectContext else { assertionFailure(); return }
            guard context == ObvStack.shared.viewContext else { return }
            guard let ownedIdentity = self?.ownedIdentity else { assertionFailure(); return }
            self?.setPublishedVariables(with: ownedIdentity)
        })
    }

    var isValid: Bool {
        return isKeycloakManaged || (self.unmanagedIdentityDetails != nil)
    }

    var unmanagedIdentityDetails: ObvIdentityCoreDetails? {
        guard !isKeycloakManaged else { return nil }
        return try? ObvIdentityCoreDetails(firstName: self.firstName, lastName: self.lastName, company: self.company, position: self.position, signedUserDetails: nil)
    }

    fileprivate func equals(other: SingleIdentity) -> Bool {
        return firstName == other.firstName &&
            lastName == other.lastName &&
            position == other.position &&
            company == other.company &&
            photoURL == other.photoURL && // We do not check whether two distinct URLs point to the same file...
            isKeycloakManaged == other.isKeycloakManaged    }

    static func == (lhs: SingleIdentity, rhs: SingleIdentity) -> Bool {
        return type(of: lhs) == type(of: rhs) && lhs.equals(other: rhs)
    }

    var firstNameThenLastName: String {
        (try? ObvIdentityCoreDetails(firstName: firstName, lastName: lastName, company: company, position: position, signedUserDetails: nil).getDisplayNameWithStyle(.firstNameThenLastName)) ?? ""
    }
    
    var shortDisplayableName: String {
        (try? ObvIdentityCoreDetails(firstName: firstName, lastName: lastName, company: company, position: position, signedUserDetails: nil).getDisplayNameWithStyle(.short)) ?? ""
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.firstName)
        hasher.combine(self.lastName)
        hasher.combine(self.position)
        hasher.combine(self.company)
        hasher.combine(self.photoURL)
        // We do not combine the isKeycloakManaged var (this would activate the publish button for no reason)
    }
    
    
    private func observeNewCachedProfilePictureCandidateNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeNewCachedProfilePictureCandidate() { [weak self] (requestUUID, url) in
            guard self?.id == requestUUID else { return }
            DispatchQueue.main.async {
                withAnimation {
                    self?.photoURL = url
                }
            }
        })
    }
    
    
}


protocol SingleContactIdentityDelegate: AnyObject {
    func userWantsToPerformAnIntroduction(forContact: SingleContactIdentity)
    func userWantsToDeleteContact(_ contact: SingleContactIdentity, completion: @escaping (Bool) -> Void)
    func userWantsToUpdateTrustedIdentityDetails(ofContact: SingleContactIdentity, usingPublishedDetails: ObvIdentityDetails)
    func userWantsToNavigateToSingleGroupView(_ group: DisplayedContactGroup)
    func userWantsToDisplay(persistedDiscussion: PersistedDiscussion)
    func userWantsToEditContactNickname()
    func userWantsToInviteContactToOneToOne()
    func userWantsToCancelSentInviteContactToOneToOne()
    func userWantsToSyncOneToOneStatusOfContact()
}


final class SingleContactIdentity: SingleIdentity {

    weak var delegate: SingleContactIdentityDelegate?
    
    /// This is always nil, except for a contact that has published details that are distinct
    /// from the trusted details
    @Published var publishedContactDetails: ObvIdentityDetails?
    @Published var contactStatus: PersistedObvContactIdentity.Status
    @Published var customDisplayName: String?
    @Published var contactHasNoDevice: Bool
    @Published var contactIsOneToOne: Bool
    @Published var isActive: Bool
    @Published var showReblockView: Bool
    @Published var tappedGroup: DisplayedContactGroup? = nil
    @Published var displayedContactGroupFetchRequest: NSFetchRequest<DisplayedContactGroup>
    @Published var oneToOneInvitationSentFetchRequest: NSFetchRequest<PersistedInvitationOneToOneInvitationSent>

    let trustOrigins: [ObvTrustOrigin]

    private var publishedPhotoURL: URL?
    var customPhotoURL: URL? {
        willSet {
            self.objectWillChange.send()
        }
    }

    /// This is set when using the appropriate initializer. In particular, this is non-nil for the detailed contact identity view.
    let persistedContact: PersistedObvContactIdentity?
    
    private var cancellables = [AnyCancellable]()
    private let observeChangesMadeToContact: Bool

    /// For previews only
    init(firstName: String?, lastName: String?, position: String?, company: String?, customDisplayName: String? = nil, publishedContactDetails: ObvIdentityDetails?, contactStatus: PersistedObvContactIdentity.Status, contactHasNoDevice: Bool, contactIsOneToOne: Bool, isActive: Bool, trustOrigins: [ObvTrustOrigin] = []) {
        self.publishedContactDetails = publishedContactDetails
        self.contactStatus = contactStatus
        self.persistedContact = nil
        self.customDisplayName = customDisplayName
        self.contactHasNoDevice = contactHasNoDevice
        self.contactIsOneToOne = contactIsOneToOne
        self.isActive = isActive
        self.showReblockView = false
        self.observeChangesMadeToContact = false
        self.trustOrigins = trustOrigins
        self.displayedContactGroupFetchRequest = DisplayedContactGroup.getFetchRequestWithNoResult()
        self.oneToOneInvitationSentFetchRequest = PersistedInvitationOneToOneInvitationSent.getFetchRequestWithNoResult()
        super.init(firstName: firstName,
                   lastName: lastName,
                   position: position,
                   company: company,
                   isKeycloakManaged: false,
                   showGreenShield: false,
                   showRedShield: false,
                   identityColors: nil,
                   photoURL: nil)
    }
    
    init(persistedContact: PersistedObvContactIdentity, observeChangesMadeToContact: Bool, trustOrigins: [ObvTrustOrigin] = [], fetchGroups: Bool = false, delegate: SingleContactIdentityDelegate? = nil) {
        assert(Thread.isMainThread)
        self.persistedContact = persistedContact
        self.delegate = delegate
        self.contactStatus = persistedContact.status
        self.customDisplayName = persistedContact.customDisplayName
        self.customPhotoURL = persistedContact.customPhotoURL
        self.contactHasNoDevice = persistedContact.devices.isEmpty
        self.contactIsOneToOne = persistedContact.isOneToOne
        self.isActive = persistedContact.isActive
        self.showReblockView = false
        let coreDetails = persistedContact.identityCoreDetails
        self.observeChangesMadeToContact = observeChangesMadeToContact
        self.trustOrigins = trustOrigins
        if let ownedCryptoId = persistedContact.ownedIdentity?.cryptoId, fetchGroups {
            self.displayedContactGroupFetchRequest = DisplayedContactGroup.getFetchRequestForAllDisplayedContactGroup(ownedIdentity: ownedCryptoId, contactIdentity: persistedContact.cryptoId)
        } else {
            self.displayedContactGroupFetchRequest = DisplayedContactGroup.getFetchRequestWithNoResult()
        }
        if let ownedCryptoId = persistedContact.ownedIdentity?.cryptoId {
            self.oneToOneInvitationSentFetchRequest = PersistedInvitationOneToOneInvitationSent.getFetchRequest(fromOwnedIdentity: ownedCryptoId, toContact: persistedContact.cryptoId)
        } else {
            self.oneToOneInvitationSentFetchRequest = PersistedInvitationOneToOneInvitationSent.getFetchRequestWithNoResult()
        }
        super.init(firstName: coreDetails.firstName,
                   lastName: coreDetails.lastName,
                   position: coreDetails.position,
                   company: coreDetails.company,
                   isKeycloakManaged: coreDetails.signedUserDetails != nil,
                   showGreenShield: persistedContact.isCertifiedByOwnKeycloak,
                   showRedShield: !persistedContact.isActive,
                   identityColors: persistedContact.cryptoId.colors,
                   photoURL: persistedContact.photoURL)
        observeUpdateMadesToContactDevices()
        observeChangesOfCustomDisplayName()
        observeChangesOfCustomPhotoURL()
        observeNewSavedCustomContactPictureCandidateNotifications()
        // We request the engine's details about this contact, so as to display new published details if necessary
        if observeChangesMadeToContact {
            observeObvContactAnswerNotifications()
            observeContactStatusChanges()
            observeUpdatedContactIdentityNotifications()
            guard let ownedCryptoId = persistedContact.ownedIdentity?.cryptoId else { assertionFailure(); return }
            ObvMessengerInternalNotification.obvContactRequest(requestUUID: self.id, contactCryptoId: persistedContact.cryptoId, ownedCryptoId: ownedCryptoId)
                .postOnDispatchQueue()
        }
    }

    var publishedProfilePicture: UIImage? {
        guard let publishedPhotoURL = self.publishedPhotoURL else { return nil }
        return UIImage(contentsOfFile: publishedPhotoURL.path)
    }

    var customOrTrustedProfilePicture: UIImage? {
        guard let url = self.customPhotoURL ?? self.photoURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    var editCustomPictureMode: CircleAndTitlesEditionMode {
        .picture { [weak self] image in self?.setCustomProfilePicture(image) }
    }

    private func setCustomProfilePicture(_ newValue: UIImage?) {
        assert(Thread.isMainThread)
        guard let value = newValue else {
            self.customPhotoURL = nil
            return
        }
        ObvMessengerInternalNotification.newCustomContactPictureCandidateToSave(requestUUID: id, profilePicture: value)
            .postOnDispatchQueue()
    }

    var publishedFirstName: String? {
        publishedContactDetails?.coreDetails.firstName
    }

    var publishedLastName: String? {
        publishedContactDetails?.coreDetails.lastName
    }

    var publishedPosition: String? {
        publishedContactDetails?.coreDetails.position
    }

    var publishedCompany: String? {
        publishedContactDetails?.coreDetails.company
    }

    func getFirstName(for details: PreferredDetails) -> String {
        switch details {
        case .trusted:
            return firstName
        case .publishedOrTrusted:
            return publishedFirstName ?? firstName
        case .customOrTrusted:
            return customDisplayName == nil ? firstName : ""
        }
    }

    func getLastName(for details: PreferredDetails) -> String {
        switch details {
        case .trusted:
            return lastName
        case .publishedOrTrusted:
            return publishedLastName ?? lastName
        case .customOrTrusted:
            return customDisplayName ?? lastName
        }
    }

    func getPosition(for details: PreferredDetails) -> String {
        switch details {
        case .trusted, .customOrTrusted:
            return position
        case .publishedOrTrusted:
            return publishedPosition ?? position
        }
    }

    func getCompagny(for details: PreferredDetails) -> String {
        switch details {
        case .trusted, .customOrTrusted:
            return company
        case .publishedOrTrusted:
            return publishedCompany ?? company
        }
    }

    func getProfilPicture(for details: PreferredDetails) -> UIImage? {
        switch details {
        case .trusted:
            return profilePicture
        case .publishedOrTrusted:
            return publishedProfilePicture
        case .customOrTrusted:
            return customOrTrustedProfilePicture
        }
    }


    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    fileprivate override func equals(other: SingleIdentity) -> Bool {
        guard super.equals(other: other) else { return false }
        guard let _other = other as? SingleContactIdentity else { assertionFailure(); return false }
        return customDisplayName == _other.customDisplayName &&
            customPhotoURL == _other.customPhotoURL
    }

    public override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(self.customDisplayName)
        hasher.combine(self.customPhotoURL)
    }

    private func observeChangesOfCustomDisplayName() {
        guard let persistedContact = self.persistedContact else { assertionFailure(); return }
        keyValueObservations.append(persistedContact.observe(\.customDisplayName) { [weak self] (_,_)  in
            assert(Thread.isMainThread)
            guard let _self = self else { return }
            withAnimation {
                _self.customDisplayName = persistedContact.customDisplayName
            }
            _self.initialHash = _self.hashValue
        })
    }

    private func observeChangesOfCustomPhotoURL() {
        guard let persistedContact = self.persistedContact else { assertionFailure(); return }
        keyValueObservations.append(persistedContact.observe(\.customPhotoFilename) { [weak self] (_,_)  in
            assert(Thread.isMainThread)
            guard let _self = self else { return }
            withAnimation {
                _self.customPhotoURL = persistedContact.customPhotoURL
            }
            _self.initialHash = _self.hashValue
        })
    }
        
    /// This method listen for changes to the device list of the contact. When this list changes, and there is no device left, it means (well, we assume) that there is an ongoing channel creation.
    /// When there is at least one device, we assume that a channel exists with the contact.
    private func observeUpdateMadesToContactDevices() {
        guard let persistedContact = self.persistedContact else { assertionFailure(); return }
        observationTokens.append(contentsOf: [
            ObvMessengerCoreDataNotification.observeDeletedPersistedObvContactDevice(queue: OperationQueue.main) { [weak self] (contactCryptoId) in
                guard contactCryptoId == persistedContact.cryptoId else { return }
                self?.setTrustedVariables(with: persistedContact)
            },
            ObvMessengerCoreDataNotification.observeNewPersistedObvContactDevice(queue: OperationQueue.main) { [weak self] (_, contactCryptoId) in
                guard contactCryptoId == persistedContact.cryptoId else { return }
                self?.setTrustedVariables(with: persistedContact)
            },
        ])
    }
    
    
    private func observeObvContactAnswerNotifications() {
        guard let persistedContact = self.persistedContact else { assertionFailure(); return }
        observationTokens.append(ObvMessengerInternalNotification.observeObvContactAnswer(queue: OperationQueue.main) { [weak self] (requestUUID, obvContact) in
            guard self?.id == requestUUID else { return }
            guard persistedContact.cryptoId == obvContact.cryptoId else { return }
            self?.setTrustedVariables(with: persistedContact)
            guard obvContact.trustedIdentityDetails != obvContact.publishedIdentityDetails else { return }
            withAnimation {
                self?.publishedContactDetails = obvContact.publishedIdentityDetails
                if let photoURL = self?.publishedContactDetails?.photoURL {
                    self?.publishedPhotoURL = photoURL
                }
                self?.contactStatus = persistedContact.status
                self?.isActive = persistedContact.isActive
                self?.showReblockView = obvContact.isActive && obvContact.isRevokedAsCompromised
                self?.showRedShield = !obvContact.isActive
            }
        })
    }
    
    
    /// We observe status changes for the contact. When there is one, we do not immediately change the UI. Instead, we query the engine to get the most
    /// recent trusted and published details. They will be received in `observeObvContactAnswerNotifications` where we will sync the UI with the model
    private func observeContactStatusChanges() {
        guard let currentContactCryptoId = persistedContact?.cryptoId else { assertionFailure(); return }
        guard let currentOwnedCryptoId = persistedContact?.ownedIdentity?.cryptoId else { return }
        let id = self.id
        observationTokens.append(ObvMessengerCoreDataNotification.observePersistedContactHasNewStatus(queue: OperationQueue.main) { (contactCryptoId, ownedCryptoId) in
            guard (currentContactCryptoId, currentOwnedCryptoId) == (contactCryptoId, ownedCryptoId) else { return }
            ObvMessengerInternalNotification.obvContactRequest(requestUUID: id, contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
                .postOnDispatchQueue()
        })
    }
    
    
    
    /// We observe notifications sent when the trusted/published details change at the engine level, so as to update the cards making
    /// it possible for the user to accept new published details
    private func observeUpdatedContactIdentityNotifications() {
        guard let currentContactCryptoId = persistedContact?.cryptoId else { assertionFailure(); return }
        guard let currentOwnedCryptoId = persistedContact?.ownedIdentity?.cryptoId else { return }
        let id = self.id
        observationTokens.append(ObvMessengerInternalNotification.observeContactIdentityDetailsWereUpdated(queue: OperationQueue.main) { (contactCryptoId, ownedCryptoId) in
            guard (currentContactCryptoId, currentOwnedCryptoId) == (contactCryptoId, ownedCryptoId) else { return }
            ObvMessengerInternalNotification.obvContactRequest(requestUUID: id, contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
                .postOnDispatchQueue()
        })
    }

    fileprivate func observeNewSavedCustomContactPictureCandidateNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeNewSavedCustomContactPictureCandidate() { [weak self] (requestUUID, url) in
            guard self?.id == requestUUID else { return }
            DispatchQueue.main.async {
                withAnimation {
                    self?.customPhotoURL = url
                }
            }
        })
    }
    
    override func setTrustedVariables(with contact: PersistedObvContactIdentity) {
        assert(Thread.isMainThread)
        assert(self.persistedContact == contact)
        withAnimation {
            super.setTrustedVariables(with: contact)
            self.contactHasNoDevice = contact.devices.isEmpty
            self.isActive = contact.isActive
            self.contactStatus = contact.status
            self.customDisplayName = contact.customDisplayName
            self.contactIsOneToOne = contact.isOneToOne
        }
    }

    
    func introduceToAnotherContact() {
        delegate?.userWantsToPerformAnIntroduction(forContact: self)
    }
    
    func updateDetails() {
        guard let publishedContactDetails = self.publishedContactDetails else { return }
        delegate?.userWantsToUpdateTrustedIdentityDetails(ofContact: self, usingPublishedDetails: publishedContactDetails)
    }
    
    func userWantsToDeleteContact(completion: @escaping (Bool) -> Void) {
        delegate?.userWantsToDeleteContact(self, completion: completion)
    }
    
    func userWantsToRestartChannelCreation() {
        guard let persistedContact = self.persistedContact else { assertionFailure(); return }
        let contactCryptoId = persistedContact.cryptoId
        guard let ownedCryptoId = persistedContact.ownedIdentity?.cryptoId else { return }
        ObvMessengerInternalNotification.userWantsToRestartChannelEstablishmentProtocol(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            .postOnDispatchQueue()
    }
    
    func userWantsToRecreateTheSecureChannel() {
        guard let persistedContact = self.persistedContact else { assertionFailure(); return }
        let contactCryptoId = persistedContact.cryptoId
        guard let ownedCryptoId = persistedContact.ownedIdentity?.cryptoId else { return }
        ObvMessengerInternalNotification.userWantsToReCreateChannelEstablishmentProtocol(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            .postOnDispatchQueue()
    }
    
    func userWantsToNavigateToSingleGroupView(_ group: DisplayedContactGroup) {
        delegate?.userWantsToNavigateToSingleGroupView(group)
    }

    func userWantsToDiscuss() {
        guard contactIsOneToOne else { assertionFailure(); return }
        guard let persistedContact = self.persistedContact else { assertionFailure(); return }
        guard persistedContact.isOneToOne else {
            assertionFailure("Trying to have a one-to-one discussion with a contact that is not OneToOne")
            return
        }
        guard let discussion = persistedContact.oneToOneDiscussion else { assertionFailure(); return }
        
        delegate?.userWantsToDisplay(persistedDiscussion: discussion)
    }
    
    func userWantsToCallContact() {
        guard isActive && !contactHasNoDevice else { return }
        guard let persistedContact = persistedContact else { assertionFailure(); return }
        let contactID = persistedContact.typedObjectID

        ObvMessengerInternalNotification.userWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: [contactID], groupId: nil)
            .postOnDispatchQueue()
    }
    
    func userWantsToEditContactNickname() {
        delegate?.userWantsToEditContactNickname()
    }
    
    func userWantsToInviteContactToOneToOne() {
        delegate?.userWantsToInviteContactToOneToOne()
    }
    
    func userWantsToCancelSentInviteContactToOneToOne() {
        delegate?.userWantsToCancelSentInviteContactToOneToOne()
    }

    enum ContactDeletionType {
        case downgradeToNonOneToOne
        case fullDeletion
        case legacyFullDeletion
    }
    
    var preferredDeletionType: ContactDeletionType {
        guard let persistedContact = self.persistedContact else { return .fullDeletion }
        guard persistedContact.supportsCapability(.oneToOneContacts) else {
            return .legacyFullDeletion
        }
        return persistedContact.isOneToOne ? .downgradeToNonOneToOne : .fullDeletion
    }
    
    func userWantsToSyncOneToOneStatusOfContact() {
        delegate?.userWantsToSyncOneToOneStatusOfContact()
    }
    
}


/// This is a legacy class that we should not use again in the future. Instead, use `DisplayedContactGroup`.
final class ContactGroup: Identifiable, Hashable, ObservableObject {

    let id = UUID()
    @Published var name: String
    @Published var description: String
    @Published var members: [SingleIdentity]
    @Published private(set) var photoURL: URL?
    @Published var groupColors: (background: UIColor, text: UIColor)?
    private var initialHash: Int
    var hasChanged: Bool { initialHash != hashValue }

    private var observationTokens = [NSObjectProtocol]()

    init(name: String, description: String, members: [SingleIdentity], photoURL: URL?, groupColors: (background: UIColor, text: UIColor)?, editionMode: CircleAndTitlesEditionMode = .none) {
        self.name = name
        self.description = description
        self.members = members
        self.groupColors = groupColors
        self.photoURL = photoURL
        self.initialHash = 0
        self.initialHash = hashValue
        observeNewCachedProfilePictureCandidateNotifications()
    }

    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    convenience init(obvContactGroup: ObvContactGroup) {
        let currentGroupMembers = Set(obvContactGroup.groupMembers.map { SingleIdentity(genericIdentity: $0.getGenericIdentity()) })
        let currentPendingMembers = obvContactGroup.pendingGroupMembers.map { SingleIdentity(genericIdentity: $0) }
        let groupMembersAndPendingMembers = currentGroupMembers.union(currentPendingMembers)
        let photoURL: URL?
        let coreDetails: ObvGroupCoreDetails
        switch obvContactGroup.groupType {
        case .joined:
            photoURL = obvContactGroup.trustedOrLatestPhotoURL
            coreDetails = obvContactGroup.trustedOrLatestCoreDetails
        case .owned:
            photoURL = obvContactGroup.publishedPhotoURL
            coreDetails = obvContactGroup.publishedCoreDetails
        }
        self.init(name: coreDetails.name,
                  description: coreDetails.description ?? "",
                  members: Array(groupMembersAndPendingMembers),
                  photoURL: photoURL,
                  groupColors: nil)
    }

    convenience init(persistedContactGroup: PersistedContactGroup) {
        assert(Thread.isMainThread)
        let members = persistedContactGroup.contactIdentities.map({ SingleContactIdentity(persistedContact: $0, observeChangesMadeToContact: false) })
        self.init(name: persistedContactGroup.displayName,
                  description: "",
                  members: members,
                  photoURL: persistedContactGroup.displayPhotoURL,
                  groupColors: AppTheme.shared.groupColors(forGroupUid: persistedContactGroup.groupUid))
    }

    convenience init() {
        assert(Thread.isMainThread)
        self.init(name: "", description: "", members: [], photoURL: nil, groupColors: nil)
    }
    
    fileprivate var imageSystemName: String { "person.3" }

    static func == (lhs: ContactGroup, rhs: ContactGroup) -> Bool {
        return lhs.name == rhs.name &&
            lhs.description == rhs.description &&
            lhs.members == rhs.members &&
            lhs.photoURL == rhs.photoURL // We do not check whether two distinct URLs point to the same file...
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.name)
        hasher.combine(self.description)
        hasher.combine(self.members)
        hasher.combine(self.photoURL)
    }

    var profilePicture: UIImage? {
        guard let photoURL = self.photoURL else { return nil }
        return UIImage(contentsOfFile: photoURL.path)
    }

    var editPictureMode: CircleAndTitlesEditionMode {
        .picture { [weak self] image in self?.setProfilePicture(image) }
    }

    private func setProfilePicture(_ newValue: UIImage?) {
        assert(Thread.isMainThread)
        guard let value = newValue else {
            withAnimation {
                self.photoURL = nil
            }
            return
        }
        ObvMessengerInternalNotification.newProfilePictureCandidateToCache(requestUUID: id, profilePicture: value)
            .postOnDispatchQueue()
    }
    
    fileprivate func observeNewCachedProfilePictureCandidateNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeNewCachedProfilePictureCandidate() { [weak self] (requestUUID, url) in
            guard self?.id == requestUUID else { return }
            DispatchQueue.main.async {
                withAnimation {
                    self?.photoURL = url
                }
            }
        })
    }

}

struct ProfilePictureAction {
    let title: String
    let handler: () -> Void

    var toAction: UIAction {
        UIAction(title: title) { _ in handler() }
    }
}


struct IdentityCardContentView: View {
    
    @ObservedObject var model: SingleIdentity
    var displayMode: CircleAndTitlesDisplayMode = .normal
    var editionMode: CircleAndTitlesEditionMode = .none

    var body: some View {
        CircleAndTitlesView(titlePart1: model.firstName,
                            titlePart2: model.lastName,
                            subtitle: model.position,
                            subsubtitle: model.company,
                            circleBackgroundColor: model.identityColors?.background,
                            circleTextColor: model.identityColors?.text,
                            circledTextView: model.circledTextView([model.firstName, model.lastName]),
                            systemImage: .person,
                            profilePicture: model.profilePicture,
                            showGreenShield: model.showGreenShield,
                            showRedShield: model.showRedShield,
                            editionMode: editionMode,
                            displayMode: displayMode)
    }

}

enum PreferredDetails {
    case trusted
    case publishedOrTrusted
    case customOrTrusted
}

struct ContactIdentityCardContentView: View {

    @ObservedObject var model: SingleContactIdentity
    let preferredDetails: PreferredDetails
    var displayMode: CircleAndTitlesDisplayMode = .normal
    var editionMode: CircleAndTitlesEditionMode = .none

    private var firstName: String {
        model.getFirstName(for: preferredDetails)
    }

    private var lastName: String {
        model.getLastName(for: preferredDetails)
    }

    private var position: String {
        model.getPosition(for: preferredDetails)
    }

    private var company: String {
        model.getCompagny(for: preferredDetails)
    }
    
    private var profilePicture: UIImage? {
        model.getProfilPicture(for: preferredDetails)
    }

    private var titlePart1: String { firstName }

    private var titlePart2: String { lastName }

    var body: some View {
        CircleAndTitlesView(titlePart1: titlePart1,
                            titlePart2: titlePart2,
                            subtitle: position,
                            subsubtitle: company,
                            circleBackgroundColor: model.identityColors?.background,
                            circleTextColor: model.identityColors?.text,
                            circledTextView: model.circledTextView([titlePart1, titlePart2]),
                            systemImage: .person,
                            profilePicture: profilePicture,
                            showGreenShield: model.showGreenShield,
                            showRedShield: model.showRedShield,
                            editionMode: editionMode,
                            displayMode: displayMode)
    }

}


struct GroupCardContentView: View {
    
    @ObservedObject var model: ContactGroup
    var displayMode: CircleAndTitlesDisplayMode = .normal
    var editionMode: CircleAndTitlesEditionMode = .none

    private var circledTextView: Text? {
        let components = [model.name]
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
            .first
        if let char = components?.first {
            return Text(String(char))
        } else {
            return nil
        }
    }

    var body: some View {
        CircleAndTitlesView(titlePart1: model.name,
                            titlePart2: nil,
                            subtitle: model.description,
                            subsubtitle: nil,
                            circleBackgroundColor: model.groupColors?.background,
                            circleTextColor: model.groupColors?.text,
                            circledTextView: circledTextView,
                            systemImage: .person3Fill,
                            profilePicture: model.profilePicture,
                            showGreenShield: false,
                            showRedShield: false,
                            editionMode: editionMode,
                            displayMode: displayMode)
    }

}

struct IdentityCardContentView_Previews: PreviewProvider {
    
    static let contacts = [
        SingleIdentity(firstName: "Joyce",
                       lastName: "Lathrop",
                       position: "Happiness manager",
                       company: "Olvid",
                       isKeycloakManaged: false,
                       showGreenShield: false,
                       showRedShield: false,
                       identityColors: (.red, .black),
                       photoURL: nil),
        SingleIdentity(firstName: "Steve",
                       lastName: "Marcel",
                       position: nil,
                       company: "Olvid",
                       isKeycloakManaged: false,
                       showGreenShield: false,
                       showRedShield: false,
                       identityColors: (.blue, .black),
                       photoURL: nil),
        SingleIdentity(firstName: "Alan",
                       lastName: "Turing",
                       position: nil,
                       company: nil,
                       isKeycloakManaged: false,
                       showGreenShield: false,
                       showRedShield: false,
                       identityColors: nil,
                       photoURL: nil),
        SingleIdentity(firstName: "Galileo",
                       lastName: "Galilei",
                       position: "Inertia",
                       company: "Earth",
                       isKeycloakManaged: true,
                       showGreenShield: true,
                       showRedShield: false,
                       identityColors: nil,
                       photoURL: nil),
    ]
    
    static let contactsWithSpecialName = [
        SingleIdentity(firstName: "Christophe-Alexandre",
                       lastName: "Gaillape",
                       position: nil,
                       company: nil,
                       isKeycloakManaged: false,
                       showGreenShield: false,
                       showRedShield: false,
                       identityColors: nil,
                       photoURL: nil),
    ]
    
    static let groups: [ContactGroup] = [
        ContactGroup(name: "The big group",
                     description: "The big description",
                     members: contacts,
                     photoURL: nil,
                     groupColors: (.blue, .cyan)),
        ContactGroup(name: "The small group",
                     description: "",
                     members: [contacts[0]],
                     photoURL: nil,
                     groupColors: nil),
    ]
    
    static var previews: some View {
        Group {
            Group {
                ForEach(contacts) {
                    IdentityCardContentView(model: $0, displayMode: .normal, editionMode: .none)
                }
                .padding()
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .light)
                ForEach(contacts) {
                    IdentityCardContentView(model: $0, displayMode: .normal, editionMode: .none)
                }
                .padding()
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .light)
                ForEach(contacts) {
                    IdentityCardContentView(model: $0, displayMode: .normal, editionMode: .none)
                }
                .padding()
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
                ForEach(groups) {
                    GroupCardContentView(model: $0, displayMode: .normal, editionMode: .none)
                }
                .padding()
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .light)
                ForEach(groups) {
                    GroupCardContentView(model: $0, displayMode: .normal, editionMode: .none)
                }
                .padding()
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
            }
            .previewLayout(.sizeThatFits)
            IdentityCardContentView(model: contactsWithSpecialName[0], displayMode: .normal, editionMode: .none)
                .previewLayout(.fixed(width: 300, height: 100))
        }
    }

}

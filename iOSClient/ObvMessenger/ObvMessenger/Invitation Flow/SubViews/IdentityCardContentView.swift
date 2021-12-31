/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

@available(iOS 13.0, *)
class SingleIdentity: Identifiable, Hashable, ObservableObject {
    
    let id = UUID()
    @Published var firstName: String
    @Published var lastName: String
    @Published var position: String
    @Published var company: String
    fileprivate(set) var photoURL: URL?
    @Published var isKeycloakManaged: Bool
    @Published var showGreenShield: Bool
    @Published var showRedShield: Bool
    fileprivate var initialHash: Int
    let identityColors: (background: UIColor, text: UIColor)?
    let editionMode: CircleAndTitlesEditionMode

    /// If set, the configuration will be shown on screen
    let serverAndAPIKeyToShow: ServerAndAPIKey?

    /// This is set when, and only when, using an identity server during onboarding.
    let keycloakDetails: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff)?
    
    var profilePicture: Binding<UIImage?>!
    @Published var changed: Bool // This allows to "force" the refresh of the view

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
    
    init(firstName: String?, lastName: String?, position: String?, company: String?, isKeycloakManaged: Bool, showGreenShield: Bool, showRedShield: Bool, identityColors: (background: UIColor, text: UIColor)?, photoURL: URL?, editionMode: CircleAndTitlesEditionMode = .none, serverAndAPIKeyToShow: ServerAndAPIKey? = nil, keycloakDetails: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff)? = nil) {
        self.firstName = firstName ?? ""
        self.lastName = lastName ?? ""
        self.position = position ?? ""
        self.company = company ?? ""
        self.photoURL = photoURL
        self.isKeycloakManaged = isKeycloakManaged
        self.showGreenShield = showGreenShield
        self.showRedShield = showRedShield
        self.initialHash = 0
        self.identityColors = identityColors
        self.ownedIdentity = nil
        self.serverAndAPIKeyToShow = serverAndAPIKeyToShow
        self.keycloakDetails = keycloakDetails
        self.changed = false
        self.editionMode = editionMode
        self.profilePicture = Binding<UIImage?>(get: { [weak self] in self?.getProfilePicture() } , set: { [weak self] newValue in self?.setProfilePicture(newValue) })
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
    
    init(ownedIdentity: PersistedObvOwnedIdentity, editionMode: CircleAndTitlesEditionMode = .none) {
        assert(Thread.isMainThread)
        self.firstName = ""
        self.lastName = ""
        self.position = ""
        self.company = ""
        self.isKeycloakManaged = ownedIdentity.isKeycloakManaged
        self.showGreenShield = ownedIdentity.isKeycloakManaged
        self.showRedShield = false
        self.identityColors = ownedIdentity.cryptoId.colors
        self.ownedIdentity = ownedIdentity
        self.initialHash = 0
        self.changed = false
        self.editionMode = editionMode
        self.serverAndAPIKeyToShow = nil
        self.keycloakDetails = nil
        setPublishedVariables(with: ownedIdentity)
        self.profilePicture = Binding<UIImage?>(get: { [weak self] in self?.getProfilePicture() } , set: { [weak self] newValue in self?.setProfilePicture(newValue) })
        observeViewContextDidChange()
        observeNewCachedProfilePictureCandidateNotifications()
        self.initialHash = hashValue
    }

    /// This initializer is used during the standard onboarding procedure, when *no* identity server is used
    convenience init(serverAndAPIKeyToShow: ServerAndAPIKey?, identityDetails: ObvIdentityCoreDetails?) {
        assert(Thread.isMainThread)
        self.init(firstName: identityDetails?.firstName ?? "",
                  lastName: identityDetails?.lastName ?? "",
                  position: identityDetails?.position ?? "",
                  company: identityDetails?.company ?? "",
                  isKeycloakManaged: false,
                  showGreenShield: false,
                  showRedShield: false,
                  identityColors: nil,
                  photoURL: nil,
                  editionMode: .picture,
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
                  editionMode: .picture,
                  serverAndAPIKeyToShow: serverAndAPIKeyToShow,
                  keycloakDetails: keycloakDetails)
        observeNewCachedProfilePictureCandidateNotifications()
    }

    fileprivate func getProfilePicture() -> UIImage? {
        guard let photoURL = self.photoURL else { return nil }
        return UIImage(contentsOfFile: photoURL.path)
    }
    
    fileprivate func setProfilePicture(_ newValue: UIImage?) {
        assert(Thread.isMainThread)
        guard let value = newValue else {
            self.photoURL = nil
            withAnimation {
                self.changed.toggle()
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
                self?.photoURL = url
                withAnimation {
                    self?.changed.toggle()
                }
            }
        })
    }
    
    
}


@available(iOS 13.0, *)
protocol SingleContactIdentityDelegate: AnyObject {
    func userWantsToPerformAnIntroduction(forContact: SingleContactIdentity)
    func userWantsToDeleteContact(_ contact: SingleContactIdentity, completion: @escaping (Bool) -> Void)
    func userWantsToUpdateTrustedIdentityDetails(ofContact: SingleContactIdentity, usingPublishedDetails: ObvIdentityDetails)
    func userWantsToDisplay(persistedContactGroup: PersistedContactGroup)
    func userWantsToDisplay(persistedDiscussion: PersistedDiscussion)
    func userWantsToEditContactNickname()
}


@available(iOS 13.0, *)
final class SingleContactIdentity: SingleIdentity {

    weak var delegate: SingleContactIdentityDelegate?
    
    /// This is always nil, except for a contact that has published details that are distinct
    /// from the trusted details
    @Published var publishedContactDetails: ObvIdentityDetails?
    @Published var contactStatus: PersistedObvContactIdentity.Status
    @Published var customDisplayName: String?
    @Published var contactHasNoDevice: Bool
    @Published var isActive: Bool
    @Published var showReblockView: Bool
    @Published var tappedGroup: PersistedContactGroup? = nil
    @Published var groupFetchRequest: NSFetchRequest<PersistedContactGroup>?

    let trustOrigins: [ObvTrustOrigin]
    var publishedProfilePicture: Binding<UIImage?>!
    var customOrTrustedProfilePicture: Binding<UIImage?>!

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
    init(firstName: String?, lastName: String?, position: String?, company: String?, customDisplayName: String? = nil, editionMode: CircleAndTitlesEditionMode = .none, publishedContactDetails: ObvIdentityDetails?, contactStatus: PersistedObvContactIdentity.Status, contactHasNoDevice: Bool, isActive: Bool, trustOrigins: [ObvTrustOrigin] = []) {
        self.publishedContactDetails = publishedContactDetails
        self.contactStatus = contactStatus
        self.persistedContact = nil
        self.customDisplayName = customDisplayName
        self.contactHasNoDevice = contactHasNoDevice
        self.isActive = isActive
        self.showReblockView = false
        self.observeChangesMadeToContact = false
        self.trustOrigins = trustOrigins
        self.groupFetchRequest = nil
        super.init(firstName: firstName,
                   lastName: lastName,
                   position: position,
                   company: company,
                   isKeycloakManaged: false,
                   showGreenShield: false,
                   showRedShield: false,
                   identityColors: nil,
                   photoURL: nil,
                   editionMode: editionMode)
        self.publishedProfilePicture = Binding<UIImage?>(get: { [weak self] in self?.getPublishedProfilePicture() } , set: { [weak self] newValue in self?.setPublishedProfilePicture(newValue) })
        self.customOrTrustedProfilePicture = Binding<UIImage?>(get: { [weak self] in self?.getCustomOrTrustedProfilePicture() } , set: { [weak self] newValue in self?.setCustomProfilePicture(newValue) })
    }
    
    init(persistedContact: PersistedObvContactIdentity, observeChangesMadeToContact: Bool, editionMode: CircleAndTitlesEditionMode = .none, trustOrigins: [ObvTrustOrigin] = [], fetchGroups: Bool = false, delegate: SingleContactIdentityDelegate? = nil) {
        assert(Thread.isMainThread)
        self.persistedContact = persistedContact
        self.delegate = delegate
        self.contactStatus = persistedContact.status
        self.customDisplayName = persistedContact.customDisplayName
        self.customPhotoURL = persistedContact.customPhotoURL
        self.contactHasNoDevice = persistedContact.devices.isEmpty
        self.isActive = persistedContact.isActive
        self.showReblockView = false
        let coreDetails = persistedContact.identityCoreDetails
        self.observeChangesMadeToContact = observeChangesMadeToContact
        self.trustOrigins = trustOrigins
        if fetchGroups {
            self.groupFetchRequest = PersistedContactGroup.getFetchRequestForAllContactGroupsOfContact(persistedContact)
        } else {
            self.groupFetchRequest = nil
        }
        super.init(firstName: coreDetails.firstName,
                   lastName: coreDetails.lastName,
                   position: coreDetails.position,
                   company: coreDetails.company,
                   isKeycloakManaged: coreDetails.signedUserDetails != nil,
                   showGreenShield: persistedContact.isCertifiedByOwnKeycloak,
                   showRedShield: !persistedContact.isActive,
                   identityColors: persistedContact.cryptoId.colors,
                   photoURL: persistedContact.photoURL,
                   editionMode: editionMode)
        self.publishedProfilePicture = Binding<UIImage?>(get: { [weak self] in self?.getPublishedProfilePicture() }, set: { [weak self] newValue in self?.setPublishedProfilePicture(newValue) })
        self.customOrTrustedProfilePicture = Binding<UIImage?>(get: { [weak self] in self?.getCustomOrTrustedProfilePicture() }, set: { [weak self] newValue in self?.setCustomProfilePicture(newValue) })
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

    private func getPublishedProfilePicture() -> UIImage? {
        guard let publishedPhotoURL = self.publishedPhotoURL else { return nil }
        return UIImage(contentsOfFile: publishedPhotoURL.path)
    }

    private func setPublishedProfilePicture(_ newValue: UIImage?) {
        // This should never be called. publishedProfilePicture is a binding because this makes is easier in the views
        assertionFailure()
    }

    private func getCustomOrTrustedProfilePicture() -> UIImage? {
        guard let url = self.customPhotoURL ?? self.photoURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func setCustomProfilePicture(_ newValue: UIImage?) {
        assert(Thread.isMainThread)
        guard let value = newValue else {
            self.customPhotoURL = nil
            withAnimation {
                self.changed.toggle()
            }
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

    func getProfilPicture(for details: PreferredDetails) -> Binding<UIImage?> {
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
            _self.customDisplayName = persistedContact.customDisplayName
            _self.changed.toggle()
            _self.initialHash = _self.hashValue
        })
    }

    private func observeChangesOfCustomPhotoURL() {
        guard let persistedContact = self.persistedContact else { assertionFailure(); return }
        keyValueObservations.append(persistedContact.observe(\.customPhotoFilename) { [weak self] (_,_)  in
            assert(Thread.isMainThread)
            guard let _self = self else { return }
            _self.customPhotoURL = persistedContact.customPhotoURL
            _self.changed.toggle()
            _self.initialHash = _self.hashValue
        })
    }
        
    /// This method listen for changes to the device list of the contact. When this list changes, and there is no device left, it means (well, we assume) that there is an ongoing channel creation.
    /// When there is at least one device, we assume that a channel exists with the contact.
    private func observeUpdateMadesToContactDevices() {
        guard let persistedContact = self.persistedContact else { assertionFailure(); return }
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeDeletedPersistedObvContactDevice(queue: OperationQueue.main) { [weak self] (contactCryptoId) in
                guard contactCryptoId == persistedContact.cryptoId else { return }
                self?.setTrustedVariables(with: persistedContact)
            },
            ObvMessengerInternalNotification.observeNewPersistedObvContactDevice(queue: OperationQueue.main) { [weak self] (_, contactCryptoId) in
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
                self?.changed.toggle()
            }
        })
    }
    
    
    /// We observe status changes for the contact. When there is one, we do not immediately change the UI. Instead, we query the engine to get the most
    /// recent trusted and published details. They will be received in `observeObvContactAnswerNotifications` where we will sync the UI with the model
    private func observeContactStatusChanges() {
        guard let currentContactCryptoId = persistedContact?.cryptoId else { assertionFailure(); return }
        guard let currentOwnedCryptoId = persistedContact?.ownedIdentity?.cryptoId else { return }
        let id = self.id
        observationTokens.append(ObvMessengerInternalNotification.observePersistedContactHasNewStatus(queue: OperationQueue.main) { (contactCryptoId, ownedCryptoId) in
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
                self?.customPhotoURL = url
                withAnimation {
                    self?.changed.toggle()
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
            self.changed.toggle()
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
    
    func userWantsToNavigateToSingleGroupView(_ group: PersistedContactGroup) {
        delegate?.userWantsToDisplay(persistedContactGroup: group)
    }

    func userWantsToDiscuss() {
        guard let discussion = persistedContact?.oneToOneDiscussion else { assertionFailure(); return }
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

}


@available(iOS 13.0, *)
final class ContactGroup: Identifiable, Hashable, ObservableObject {

    let id = UUID()
    @Published var name: String
    @Published var description: String
    @Published var members: [SingleIdentity]
    @Published var photoURL: URL?
    @Published var groupColors: (background: UIColor, text: UIColor)?
    private var initialHash: Int
    let editionMode: CircleAndTitlesEditionMode
    var hasChanged: Bool { initialHash != hashValue }

    var profilePicture: Binding<UIImage?>!
    @Published var changed: Bool // This allows to "force" the refresh of the view

    private var observationTokens = [NSObjectProtocol]()

    init(name: String, description: String, members: [SingleIdentity], photoURL: URL?, groupColors: (background: UIColor, text: UIColor)?, editionMode: CircleAndTitlesEditionMode = .none) {
        self.name = name
        self.description = description
        self.members = members
        self.groupColors = groupColors
        self.photoURL = photoURL
        self.initialHash = 0
        self.changed = false
        self.editionMode = editionMode
        self.profilePicture = Binding<UIImage?>(get: { [weak self] in self?.getProfilePicture() } , set: { [weak self] newValue in self?.setProfilePicture(newValue) })
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
                  groupColors: nil,
                  editionMode: .picture)
    }

    init(persistedContactGroup: PersistedContactGroup) {
        assert(Thread.isMainThread)
        self.name = persistedContactGroup.displayName
        self.description = ""
        self.members = persistedContactGroup.contactIdentities.map({ SingleContactIdentity(persistedContact: $0, observeChangesMadeToContact: false) })
        self.photoURL = persistedContactGroup.displayPhotoURL
        self.groupColors = AppTheme.shared.groupColors(forGroupUid: persistedContactGroup.groupUid)
        self.initialHash = 0
        self.editionMode = .none
        self.changed = false
        self.profilePicture = Binding<UIImage?>(get: { [weak self] in self?.getProfilePicture() } , set: { [weak self] newValue in self?.setProfilePicture(newValue) })
        self.initialHash = hashValue
    }

    convenience init() {
        assert(Thread.isMainThread)
        self.init(name: "", description: "", members: [], photoURL: nil, groupColors: nil, editionMode: .picture)
        observeNewCachedProfilePictureCandidateNotifications()
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
    
    private func getProfilePicture() -> UIImage? {
        guard let photoURL = self.photoURL else { return nil }
        return UIImage(contentsOfFile: photoURL.path)
    }
    
    private func setProfilePicture(_ newValue: UIImage?) {
        assert(Thread.isMainThread)
        guard let value = newValue else {
            self.photoURL = nil
            withAnimation {
                self.changed.toggle()
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
                self?.photoURL = url
                withAnimation {
                    self?.changed.toggle()
                }
            }
        })
    }

}

@available(iOS 13.0, *)
struct ProfilePictureView: View {

    let profilePicture: UIImage?
    let circleBackgroundColor: UIColor?
    let circleTextColor: UIColor?
    let circledTextView: Text?
    let imageSystemName: String
    let customCircleDiameter: CGFloat?
    let showGreenShield: Bool
    let showRedShield: Bool

    init(profilePicture: UIImage?,
         circleBackgroundColor: UIColor?,
         circleTextColor: UIColor?,
         circledTextView: Text?,
         imageSystemName: String,
         showGreenShield: Bool,
         showRedShield: Bool,
         customCircleDiameter: CGFloat? = ProfilePictureView.circleDiameter) {
        self.profilePicture = profilePicture
        self.circleBackgroundColor = circleBackgroundColor
        self.circleTextColor = circleTextColor
        self.circledTextView = circledTextView
        self.imageSystemName = imageSystemName
        self.showGreenShield = showGreenShield
        self.showRedShield = showRedShield
        self.customCircleDiameter = customCircleDiameter
    }

    static let circleDiameter: CGFloat = 60.0

    var body : some View {
        Group {
            if let profilePicture = profilePicture {
                Image(uiImage: profilePicture)
                    .resizable()
                    .scaledToFit()
                    .frame(width: customCircleDiameter ?? ProfilePictureView.circleDiameter, height: customCircleDiameter ?? ProfilePictureView.circleDiameter)
                    .clipShape(Circle())
            } else {
                InitialCircleView(circledTextView: circledTextView,
                                  imageSystemName: imageSystemName,
                                  circleBackgroundColor: circleBackgroundColor,
                                  circleTextColor: circleTextColor,
                                  circleDiameter: customCircleDiameter ?? ProfilePictureView.circleDiameter)
            }
        }
        .overlay(Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: (customCircleDiameter ?? ProfilePictureView.circleDiameter) / 4))
                    .foregroundColor(showGreenShield ? Color(AppTheme.shared.colorScheme.green) : .clear),
                 alignment: .topTrailing
        )
        .overlay(Image(systemIcon: .exclamationmarkShieldFill)
                    .font(.system(size: (customCircleDiameter ?? ProfilePictureView.circleDiameter) / 2))
                    .foregroundColor(showRedShield ? .red : .clear),
                 alignment: .center
        )
        
    }
}


@available(iOS 13.0, *)
struct ProfilePictureAction {
    let title: String
    let handler: () -> Void

    var toAction: UIAction {
        UIAction(title: title) { _ in handler() }
    }
}


@available(iOS 13.0, *)
struct IdentityCardContentView: View {
    
    @ObservedObject var model: SingleIdentity
    var displayMode: CircleAndTitlesDisplayMode = .normal

    var body: some View {
        CircleAndTitlesView(titlePart1: model.firstName,
                            titlePart2: model.lastName,
                            subtitle: model.position,
                            subsubtitle: model.company,
                            circleBackgroundColor: model.identityColors?.background,
                            circleTextColor: model.identityColors?.text,
                            circledTextView: model.circledTextView([model.firstName, model.lastName]),
                            imageSystemName: "person",
                            profilePicture: model.profilePicture,
                            changed: $model.changed,
                            showGreenShield: model.showGreenShield,
                            showRedShield: model.showRedShield,
                            editionMode: model.editionMode,
                            displayMode: displayMode)
    }

}

enum PreferredDetails {
    case trusted
    case publishedOrTrusted
    case customOrTrusted
}

@available(iOS 13.0, *)
struct ContactIdentityCardContentView: View {
    
    @ObservedObject var model: SingleContactIdentity
    let preferredDetails: PreferredDetails
    var forceEditionMode: CircleAndTitlesEditionMode? = nil
    var displayMode: CircleAndTitlesDisplayMode = .normal

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
    
    private var profilePicture: Binding<UIImage?> {
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
                            imageSystemName: "person",
                            profilePicture: profilePicture,
                            changed: $model.changed,
                            showGreenShield: model.showGreenShield,
                            showRedShield: model.showRedShield,
                            editionMode: forceEditionMode ?? model.editionMode,
                            displayMode: displayMode)
    }

}

@available(iOS 13.0, *)
struct GroupCardContentView: View {
    
    @ObservedObject var model: ContactGroup

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
                            subsubtitle: model.members.map { $0.firstNameThenLastName }.joined(separator: ", "),
                            circleBackgroundColor: model.groupColors?.background,
                            circleTextColor: model.groupColors?.text,
                            circledTextView: circledTextView,
                            imageSystemName: "person.3.fill",
                            profilePicture: model.profilePicture,
                            changed: $model.changed,
                            showGreenShield: false,
                            showRedShield: false,
                            editionMode: model.editionMode,
                            displayMode: .normal)
    }

}

enum CircleAndTitlesDisplayMode {
    case normal
    case small
    case header(tapToFullscreen: Bool)
}

enum CircleAndTitlesEditionMode {
    case none
    case picture
    case nicknameAndPicture(action: () -> Void)
}

@available(iOS 13.0, *)
struct CircleAndTitlesView: View {
    
    private let titlePart1: String?
    private let titlePart2: String?
    private let subtitle: String?
    private let subsubtitle: String?
    private let circleBackgroundColor: UIColor?
    private let circleTextColor: UIColor?
    private let circledTextView: Text?
    private let imageSystemName: String
    @Binding var profilePicture: UIImage?
    @Binding var changed: Bool
    private let alignment: VerticalAlignment
    private let showGreenShield: Bool
    private let showRedShield: Bool
    private let displayMode: CircleAndTitlesDisplayMode
    private let editionMode: CircleAndTitlesEditionMode

    @State private var profilePictureFullScreenIsPresented = false

    init(titlePart1: String?, titlePart2: String?, subtitle: String?, subsubtitle: String?, circleBackgroundColor: UIColor?, circleTextColor: UIColor?, circledTextView: Text?, imageSystemName: String, profilePicture: Binding<UIImage?>, changed: Binding<Bool>, alignment: VerticalAlignment = .center, showGreenShield: Bool, showRedShield: Bool, editionMode: CircleAndTitlesEditionMode, displayMode: CircleAndTitlesDisplayMode) {
        self.titlePart1 = titlePart1
        self.titlePart2 = titlePart2
        self.subtitle = subtitle
        self.subsubtitle = subsubtitle
        self.circleBackgroundColor = circleBackgroundColor
        self.circleTextColor = circleTextColor
        self.circledTextView = circledTextView
        self.imageSystemName = imageSystemName
        self._profilePicture = profilePicture
        self._changed = changed
        self.alignment = alignment
        self.editionMode = editionMode
        self.displayMode = displayMode
        self.showGreenShield = showGreenShield
        self.showRedShield = showRedShield
    }

    private var circleDiameter: CGFloat {
        switch displayMode {
        case .small:
            return 40.0
        case .normal:
            return ProfilePictureView.circleDiameter
        case .header:
            return 120
        }
    }

    private var pictureViewInner: some View {
        ProfilePictureView(profilePicture: profilePicture, circleBackgroundColor: circleBackgroundColor, circleTextColor: circleTextColor, circledTextView: circledTextView, imageSystemName: imageSystemName, showGreenShield: showGreenShield, showRedShield: showRedShield, customCircleDiameter: circleDiameter)
    }

    private var pictureView: some View {
        ZStack {
            if #available(iOS 14.0, *) {
                pictureViewInner
                    .onTapGesture {
                        guard case .header(let tapToFullscreen) = displayMode else { return }
                        guard tapToFullscreen else { return }
                        guard profilePicture != nil else {
                            profilePictureFullScreenIsPresented = false
                            return
                        }
                        profilePictureFullScreenIsPresented.toggle()
                    }
                    .fullScreenCover(isPresented: $profilePictureFullScreenIsPresented) {
                        FullScreenProfilePictureView(photo: profilePicture)
                            .background(BackgroundBlurView()
                                            .edgesIgnoringSafeArea(.all))
                    }
            } else {
                pictureViewInner
            }
            switch editionMode {
            case .none:
                EmptyView()
            case .picture:
                CircledCameraButtonView(profilePicture: $profilePicture)
                    .offset(CGSize(width: ProfilePictureView.circleDiameter/3, height: ProfilePictureView.circleDiameter/3))
            case .nicknameAndPicture(let action):
                Button(action: action) {
                    CircledPencilView()
                }
                .offset(CGSize(width: circleDiameter/3, height: circleDiameter/3))
            }
        }
    }

    private var displayNameForHeader: String {
        let _titlePart1 = titlePart1 ?? ""
        let _titlePart2 = titlePart2 ?? ""
        return [_titlePart1, _titlePart2].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        switch displayMode {
        case .normal, .small:
            HStack(alignment: self.alignment, spacing: 16) {
                pictureView
                TextView(titlePart1: titlePart1,
                         titlePart2: titlePart2,
                         subtitle: subtitle,
                         subsubtitle: subsubtitle)
            }
        case .header:
            VStack(spacing: 8) {
                pictureView
                Text(displayNameForHeader)
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.semibold)
            }
        }
    }
}

@available(iOS 13.0, *)
fileprivate struct FullScreenProfilePictureView: View {
    @Environment(\.presentationMode) var presentationMode
    var photo: UIImage? // We use a binding here because this is what a SingleIdentity exposes

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.1)
                .edgesIgnoringSafeArea(.all)
            if let photo = photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onTapGesture {
            presentationMode.wrappedValue.dismiss()
        }
    }

}

@available(iOS 13.0, *)
fileprivate struct BackgroundBlurView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let effect = UIBlurEffect(style: .regular)
        let view = UIVisualEffectView(effect: effect)
        DispatchQueue.main.async {
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}


@available(iOS 13, *)
fileprivate struct TextView: View {
    
    let titlePart1: String?
    let titlePart2: String?
    let subtitle: String?
    let subsubtitle: String?
    
    private var titlePart1Count: Int { titlePart1?.count ?? 0 }
    private var titlePart2Count: Int { titlePart2?.count ?? 0 }
    private var subtitleCount: Int { subtitle?.count ?? 0 }
    private var subsubtitleCount: Int { subsubtitle?.count ?? 0 }

    /// This variable allows to control when an animation is performed on `titlePart1`.
    ///
    /// We do not want to animate a text made to the text of `titlePart1`, which is the reason why we cannot simply
    /// set an .animation(...) on the view `Text(titlePart1)`. Instead, we use another version of the animation
    /// modifier where we can provide a `value` that is used to determine when the animation should be active.
    /// We want it to be active when the *other* strings of this view change.
    ///
    /// For example, when the `subtitle` goes from empty to
    /// one character, we want `titlePart1` to move to the top in an animate way. As one can see, in that specific case,
    /// the value of `animateTitlePart1OnChange` will change when `subtitle` (or any of the other strings apart from
    /// `titlePart1`) changes. This is the reason why we use exactly this value for controling the animation of `titlePart1`.
    private var animateTitlePart1OnChange: Int {
        titlePart2Count + subtitleCount + subsubtitleCount
    }

    private var animateTitlePart2OnChange: Int {
        titlePart1Count + subtitleCount + subsubtitleCount
    }

    private var animateSubtitleOnChange: Int {
        titlePart1Count + titlePart2Count + subsubtitleCount
    }

    private var animateSubsubtitleOnChange: Int {
        titlePart1Count + titlePart2Count + subtitleCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if titlePart1 != nil || titlePart2 != nil {
                HStack(spacing: 0) {
                    if let titlePart1 = self.titlePart1, !titlePart1.isEmpty {
                        Group {
                            Text(titlePart1)
                                .font(.system(.headline, design: .rounded))
                                .lineLimit(1)
                                .animation(.spring(), value: animateTitlePart1OnChange)
                        }
                    }
                    if let titlePart1 = self.titlePart1, let titlePart2 = self.titlePart2, !titlePart1.isEmpty, !titlePart2.isEmpty {
                        Text(" ")
                            .font(.system(.headline, design: .rounded))
                            .lineLimit(1)
                    }
                    if let titlePart2 = self.titlePart2, !titlePart2.isEmpty {
                        Text(titlePart2)
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.heavy)
                            .lineLimit(1)
                            .animation(.spring(), value: animateTitlePart2OnChange)
                    }
                }
                .layoutPriority(0)
            }
            if let subtitle = self.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    .lineLimit(1)
                    .animation(.spring(), value: animateSubtitleOnChange)
            }
            if let subsubtitle = self.subsubtitle, !subsubtitle.isEmpty {
                Text(subsubtitle)
                    .font(.footnote)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    .lineLimit(1)
                    .animation(.spring(), value: animateSubsubtitleOnChange)
            }
        }
    }
}








@available(iOS 13.0, *)
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
                    IdentityCardContentView(model: $0)
                }
                .padding()
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .light)
                ForEach(contacts) {
                    IdentityCardContentView(model: $0)
                }
                .padding()
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .light)
                ForEach(contacts) {
                    IdentityCardContentView(model: $0)
                }
                .padding()
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
                ForEach(groups) {
                    GroupCardContentView(model: $0)
                }
                .padding()
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .light)
                ForEach(groups) {
                    GroupCardContentView(model: $0)
                }
                .padding()
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
            }
            .previewLayout(.sizeThatFits)
            IdentityCardContentView(model: contactsWithSpecialName[0])
                .previewLayout(.fixed(width: 300, height: 100))
        }
    }

}

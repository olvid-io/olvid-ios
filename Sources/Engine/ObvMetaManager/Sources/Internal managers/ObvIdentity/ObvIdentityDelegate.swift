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
import ObvCrypto
import ObvTypes
import OlvidUtils
import ObvJWS

public protocol 
ObvIdentityDelegate: ObvBackupableManager, ObvIdentityManagerSnapshotable {
    
    
    // MARK: - API related to owned identities
    
    /// This method returns `true` iff the `ObvCryptoIdentity` passed as a parameter is a longterm owned identity.
    ///
    /// - Parameters:
    ///   - _: the `ObvCryptoIdentity` to check
    ///   - within: the `NSManagedObjectContext` in which we want to perform the test
    /// - Returns: `true` if the identity is a (longterm) owned identity, `false` otherwise.
    func isOwned(_: ObvCryptoIdentity, within: ObvContext) throws -> Bool

    func isOwnedIdentityActive(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) throws -> Bool

    func isOwnedIdentityActive(ownedIdentity identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool
    
    func deactivateOwnedIdentityAndDeleteContactDevices(ownedIdentity: ObvCryptoIdentity, within: ObvContext) throws

    func reactivateOwnedIdentity(ownedIdentity: ObvCryptoIdentity, within: ObvContext) throws

    func generateOwnedIdentity(onServerURL serverURL: URL, with identityDetails: ObvIdentityDetails, accordingTo pkEncryptionImplemByteId: PublicKeyEncryptionImplementationByteId, and authEmplemByteId: AuthenticationImplementationByteId, nameForCurrentDevice: String, keycloakState: ObvKeycloakState?, using prng: PRNGService, within obvContext: ObvContext) -> ObvCryptoIdentity?

    // Implemented within ObvIdentityDelegateExtension.swift
    func generateOwnedIdentity(onServerURL serverURL: URL, with identityDetails: ObvIdentityDetails, nameForCurrentDevice: String, keycloakState: ObvKeycloakState?, using prng: PRNGService, within obvContext: ObvContext) -> ObvCryptoIdentity?
    
    func markOwnedIdentityForDeletion(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws
    func isOwnedIdentityDeletedOrDeletionIsInProgress(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool
    
    func deleteOwnedIdentity(_: ObvCryptoIdentity, within: ObvContext) throws
    
    func waitForOwnedIdentityDeletion(expectedOwnedCryptoId: ObvCryptoId, flowId: FlowIdentifier) async throws

    func getOwnedIdentities(restrictToActive: Bool, within: ObvContext) throws -> Set<ObvCryptoIdentity>
    
    func getActiveOwnedIdentitiesAndCurrentDeviceName(within obvContext: ObvContext) throws -> [ObvCryptoIdentity: String?]
    
    func getActiveOwnedIdentitiesThatAreNotKeycloakManaged(within: ObvContext) throws -> Set<ObvCryptoIdentity>
    
    func saveRegisteredKeycloakAPIKey(ownedCryptoIdentity: ObvCryptoIdentity, apiKey: UUID, within obvContext: ObvContext) throws

    func getRegisteredKeycloakAPIKey(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> UUID?

    func getActiveOwnedIdentitiesAndCurrentDeviceUids(within obvContext: ObvContext) throws -> Set<OwnedCryptoIdentityAndCurrentDeviceUID>

    /// This method throws if the identity is not an owned identity. Otherwise it returns the display name of the owned identity.
    func getIdentityDetailsOfOwnedIdentity(_: ObvCryptoIdentity, within: ObvContext) throws -> (publishedIdentityDetails: ObvIdentityDetails, isActive: Bool)
    
    func getPublishedIdentityDetailsOfOwnedIdentity(_: ObvCryptoIdentity, within: ObvContext) throws -> (ownedIdentityDetailsElements: IdentityDetailsElements, photoURL: URL?)
    
    /// Returns  and updated version of the owned identity `IdentityDetailsElements`
    func setPhotoServerKeyAndLabelForPublishedIdentityDetailsOfOwnedIdentity(_: ObvCryptoIdentity, withPhotoServerKeyAndLabel: PhotoServerKeyAndLabel, within: ObvContext) throws -> IdentityDetailsElements
    
    func updateDownloadedPhotoOfOwnedIdentity(_: ObvCryptoIdentity, version: Int, photo: Data, within: ObvContext) throws

    func updatePublishedIdentityDetailsOfOwnedIdentity(_ identity: ObvCryptoIdentity, with newIdentityDetails: ObvIdentityDetails, within obvContext: ObvContext) throws

    /// Returns `true` iff a new photo needs to be downloaded
    func updateOwnedPublishedDetailsWithOtherDetailsIfNewer(_ ownedIdentity: ObvCryptoIdentity, with otherIdentityDetails: IdentityDetailsElements, within obvContext: ObvContext) throws -> Bool

    func getDeterministicSeedForOwnedIdentity(_: ObvCryptoIdentity, diversifiedUsing: Data, within: ObvContext) throws -> Seed
    
    func getDeterministicSeed(diversifiedUsing data: Data, secretMACKey: MACKey, forProtocol seedProtocol: ObvConstants.SeedProtocol) throws -> Seed

    func getFreshMaskingUIDForPushNotifications(for identity: ObvCryptoIdentity, pushToken: Data, within obvContext: ObvContext) throws -> UID

    func getOwnedIdentityAssociatedToMaskingUID(_ maskingUID: UID, within obvContext: ObvContext) throws -> ObvCryptoIdentity?
    
    func computeTagForOwnedIdentity(_: ObvCryptoIdentity, on: Data, within obvContext: ObvContext) throws -> Data
    
    func verifyKeycloakSignature(ownedCryptoId: ObvCryptoIdentity, keycloakTransferProof: ObvKeycloakTransferProof, keycloakTransferProofElements: ObvKeycloakTransferProofElements, within obvContext: ObvContext) throws
    
    
    // MARK: - API related to contact groups V2

    func getGroupV2PhotoURLAndServerPhotoInfofOwnedIdentityIsUploader(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, within obvContext: ObvContext) throws -> (photoURL: URL, serverPhotoInfo: GroupV2.ServerPhotoInfo)?

    func createContactGroupV2AdministratedByOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, serializedGroupCoreDetails: Data, photoURL: URL?, serializedGroupType: Data, ownRawPermissions: Set<String>, otherGroupMembers: Set<GroupV2.IdentityAndPermissions>, within obvContext: ObvContext) throws -> (groupIdentifier: GroupV2.Identifier, groupAdminServerAuthenticationPublicKey: PublicKeyForAuthentication, serverPhotoInfo: GroupV2.ServerPhotoInfo?, encryptedServerBlob: EncryptedData, photoURL: URL?)
    
    func createContactGroupV2JoinedByOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, serverBlob: GroupV2.ServerBlob, blobKeys: GroupV2.BlobKeys, createdByMeOnOtherDevice: Bool, within obvContext: ObvContext) throws

    func removeOtherMembersOrPendingMembersFromGroupV2(withGroupIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, identitiesToRemove: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws

    func freezeGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws

    func unfreezeGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws

    func getGroupV2BlobKeysOfGroup(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> GroupV2.BlobKeys

    func getPendingMembersAndPermissionsOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<GroupV2.IdentityAndPermissions>

    func getVersionOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Int

    func checkExistenceOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool
    
    func deleteGroupV2(withGroupIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws

    func updateGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, newBlobKeys: GroupV2.BlobKeys, consolidatedServerBlob: GroupV2.ServerBlob, groupUpdatedByOwnedIdentity: Bool, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity>

    func getAllOtherMembersOrPendingMembersOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, memberOrPendingMemberInvitationNonce nonce: Data, within obvContext: ObvContext) throws -> Set<GroupV2.IdentityAndPermissionsAndDetails>

    func getAllOtherMembersOrPendingMembersOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<GroupV2.IdentityAndPermissionsAndDetails>

    func movePendingMemberToMembersOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, pendingMemberCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws

    func getOwnGroupInvitationNonceOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Data

    func setDownloadedPhotoOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, serverPhotoInfo: GroupV2.ServerPhotoInfo, photo: Data, within obvContext: ObvContext) throws

    func photoNeedsToBeDownloadedForGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, serverPhotoInfo: GroupV2.ServerPhotoInfo, within obvContext: ObvContext) throws -> Bool

    func getAllObvGroupV2(of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvGroupV2>
    
    func getObvGroupV2(with identifier: ObvGroupV2Identifier, within obvContext: ObvContext) throws -> ObvGroupV2?

    func getTrustedPhotoURLAndUploaderOfObvGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> (url: URL, uploader: ObvCryptoIdentity)?

    func replaceTrustedDetailsByPublishedDetailsOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws
    
    func getAdministratorChainOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> GroupV2.AdministratorsChain

    func getAllGroupsV2IdentifierVersionAndKeysForContact(_ contactIdentity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> [GroupV2.IdentifierVersionAndKeys]

    func getAllGroupsV2IdentifierVersionAndKeys(ofOwnedIdentity ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> [GroupV2.IdentifierVersionAndKeys]

    func getAllNonPendingAdministratorsIdentitiesOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity>
    
    
    // MARK: - Keycloak pushed groups

    func updateKeycloakGroups(ownedIdentity: ObvCryptoIdentity, signedGroupBlobs: Set<String>, signedGroupDeletions: Set<String>, signedGroupKicks: Set<String>, keycloakCurrentTimestamp: Date, within obvContext: ObvContext) throws -> [KeycloakGroupV2UpdateOutput]

    func getIdentifiersOfAllKeycloakGroups(ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<GroupV2.Identifier>
    
    func getIdentifiersOfAllKeycloakGroupsWhereContactIsPending(ownedCryptoId: ObvCryptoIdentity, contactCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<GroupV2.Identifier>
        
    func getAllKeycloakContactsThatArePendingInSomeKeycloakGroup(within obvContext: ObvContext) throws -> [ObvCryptoIdentity: Set<ObvCryptoIdentity>]

    // MARK: - API related to keycloak management

    func isOwnedIdentityKeycloakManaged(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool

    func isContactCertifiedByOwnKeycloak(contactIdentity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool

    func getSignedContactDetails(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> SignedObvKeycloakUserDetails?

    func getOwnedIdentityKeycloakState(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> (obvKeycloakState: ObvKeycloakState?, signedOwnedDetails: SignedObvKeycloakUserDetails?)

    func saveKeycloakAuthState(ownedIdentity: ObvCryptoIdentity, rawAuthState: Data, within obvContext: ObvContext) throws

    func saveKeycloakJwks(ownedIdentity: ObvCryptoIdentity, jwks: ObvJWKSet, within obvContext: ObvContext) throws

    func getOwnedIdentityKeycloakUserId(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> String?

    func setOwnedIdentityKeycloakUserId(ownedIdentity: ObvCryptoIdentity, keycloakUserId userId: String?, within obvContext: ObvContext) throws

    /// This method binds an owned identity to a keycloak server. Upon context save, it notifies about the set of all the identities that are managed by the same keycloak server than the owned identity.
    func bindOwnedIdentityToKeycloak(ownedCryptoIdentity: ObvCryptoIdentity, keycloakUserId userId: String, keycloakState: ObvKeycloakState, within obvContext: ObvContext) throws

    // This method unbinds the owned identity from any keycloak server and creates new published details for this identity using the currently published details, after removing any signed details.
    func unbindOwnedIdentityFromKeycloak(ownedCryptoIdentity: ObvCryptoIdentity, isUnbindRequestByUser: Bool, within obvContext: ObvContext) throws

    func setOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoIdentity: ObvCryptoIdentity, newSelfRevocationTestNonce: String?, within obvContext: ObvContext) throws

    func getOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> String?
    
    func setOwnedIdentityKeycloakSignatureKey(ownedCryptoIdentity: ObvCryptoIdentity, keycloakServersignatureVerificationKey: ObvJWK?, within obvContext: ObvContext) throws
    
    func getContactsCertifiedByOwnKeycloak(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity>
    
    func verifyAndAddRevocationList(ownedCryptoIdentity: ObvCryptoIdentity, signedRevocations: [String], revocationListTimetamp: Date, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity>
    
    func updateKeycloakPushTopicsIfNeeded(ownedCryptoIdentity: ObvCryptoIdentity, pushTopics: Set<String>, within obvContext: ObvContext) throws -> Bool

    func getKeycloakPushTopics(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<String>

    func getCryptoIdentitiesOfManagedOwnedIdentitiesAssociatedWithThePushTopic(_ pushTopic: String, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity>
    
    func setIsTransferRestricted(to isTransferRestricted: Bool, ownedCryptoId: ObvCryptoId, within obvContext: ObvContext) throws

    // MARK: - API related to owned devices
    
    func getDeviceUidsOfOwnedIdentity(_: ObvCryptoIdentity, within: ObvContext) throws -> Set<UID>

    func getCurrentDeviceUidOfOwnedIdentity(_: ObvCryptoIdentity, within: ObvContext) throws -> UID
    
    func getOtherDeviceUidsOfOwnedIdentity(_: ObvCryptoIdentity, within: ObvContext) throws -> Set<UID>

    /// This method throws if the UID passed is not a current device uid. Otherwise, it returns the crypto identity to whom the current device belongs.
    func getOwnedIdentityOfCurrentDeviceUid(_: UID, within: ObvContext) throws -> ObvCryptoIdentity

    func getOwnedIdentityOfRemoteDeviceUid(_: UID, within: ObvContext) throws -> ObvCryptoIdentity?

    func addOtherDeviceForOwnedIdentity(_: ObvCryptoIdentity, withUid: UID, createdDuringChannelCreation: Bool, within: ObvContext) throws

    func removeOtherDeviceForOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, otherDeviceUid: UID, within obvContext: ObvContext) throws

    /// This method throws if the identity is not an owned identity. Otherwise it returns `true` iff the UID passed corresponds to the UID of a remote device of the owned identity.
    func isDevice(withUid: UID, aRemoteDeviceOfOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> Bool

    func deleteDevicesOfContactIdentity(contactIdentity: ObvCryptoIdentity, contactDeviceUids: Set<UID>, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws

    func deleteAllDevicesOfContactIdentity(contactIdentity: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws

    func processEncryptedOwnedDeviceDiscoveryResult(_ encryptedOwnedDeviceDiscoveryResult: EncryptedData, forOwnedCryptoId ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> OwnedDeviceDiscoveryPostProcessingTask
    
    func decryptEncryptedOwnedDeviceDiscoveryResult(_ encryptedOwnedDeviceDiscoveryResult: EncryptedData, forOwnedCryptoId ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> OwnedDeviceDiscoveryResult
    
    func decryptEncryptedOwnedDeviceDiscoveryResult(_ encryptedOwnedDeviceDiscoveryResult: EncryptedData, forOwnedCryptoIdentity ownedCryptoIdentity: ObvOwnedCryptoIdentity) throws -> OwnedDeviceDiscoveryResult
    
    func decryptProtocolCiphertext(_ ciphertext: EncryptedData, forOwnedCryptoId ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Data

    func getInfosAboutOwnedDevice(withUid uid: UID, ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> (name: String?, expirationDate: Date?, latestRegistrationDate: Date?)
    
    func setCurrentDeviceNameOfOwnedIdentityAfterBackupRestore(ownedCryptoIdentity: ObvCryptoIdentity, nameForCurrentDevice: String, within obvContext: ObvContext) throws

    func getLatestChannelCreationPingTimestampOfRemoteOwnedDevice(withIdentifier ownedDeviceIdentifier: ObvOwnedDeviceIdentifier, within obvContext: ObvContext) throws -> Date?
    
    func setLatestChannelCreationPingTimestampOfRemoteOwnedDevice(withIdentifier ownedDeviceIdentifier: ObvOwnedDeviceIdentifier, to date: Date, within obvContext: ObvContext) throws

    // MARK: - API related to contact identities
    
    func addContactIdentity(_: ObvCryptoIdentity, with: ObvIdentityCoreDetails, andTrustOrigin: TrustOrigin, forOwnedIdentity: ObvCryptoIdentity, isKnownToBeOneToOne: Bool, within: ObvContext) throws

    func addTrustOriginIfTrustWouldBeIncreasedAndSetContactAsOneToOne(_: TrustOrigin, toContactIdentity: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws
    
    func getTrustOrigins(forContactIdentity: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> [TrustOrigin]
    
    func getTrustLevel(forContactIdentity: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> TrustLevel
    
    func getContactsOfOwnedIdentity(_: ObvCryptoIdentity, within: ObvContext) throws -> Set<ObvCryptoIdentity>
    
    func getContactsWithNoDeviceOfOwnedIdentity(_ ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity>
    
    /// This method throws if the second identity is not an owned identity or if the first identity is not a contact of that owned identity. Otherwise it returns the display name of the contact identity.
    func getIdentityDetailsOfContactIdentity(_: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> (publishedIdentityDetails: ObvIdentityDetails?, trustedIdentityDetails: ObvIdentityDetails)

    func getPublishedIdentityDetailsOfContactIdentity(_: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> (contactIdentityDetailsElements: IdentityDetailsElements, photoURL: URL?)?
    
    func getTrustedIdentityDetailsOfContactIdentity(_: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> (contactIdentityDetailsElements: IdentityDetailsElements, photoURL: URL?)

    func updateTrustedIdentityDetailsOfContactIdentity(_ identity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, with newContactIdentityDetails: ObvIdentityDetails, within obvContext: ObvContext) throws

    func updateDownloadedPhotoOfContactIdentity(_: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, version: Int, photo: Data, within: ObvContext) throws

    func updatePublishedIdentityDetailsOfContactIdentity(_ identity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, with newContactIdentityDetailsElements: IdentityDetailsElements, allowVersionDowngrade: Bool, within obvContext: ObvContext) throws

    func isIdentity(_: ObvCryptoIdentity, aContactIdentityOfTheOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> Bool
    
    func deleteContactIdentity(_: ObvCryptoIdentity, forOwnedIdentity: ObvCryptoIdentity, failIfContactIsPartOfACommonGroup: Bool, within: ObvContext) throws
    
    func getDateOfLastBootstrappedContactDeviceDiscovery(forContactCryptoId contactCryptoId: ObvCryptoIdentity, ofOwnedCryptoId ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Date

    func setDateOfLastBootstrappedContactDeviceDiscovery(forContactCryptoId contactCryptoId: ObvCryptoIdentity, ofOwnedCryptoId ownedCryptoId: ObvCryptoIdentity, to newDate: Date, within obvContext: ObvContext) throws
    
    func checkIfContactWasRecentlyOnline(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool
    
    func markContactAsRecentlyOnline(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws

    // MARK: - API related to contact devices
    
    func addDeviceForContactIdentity(_: ObvCryptoIdentity, withUid: UID, ofOwnedIdentity: ObvCryptoIdentity, createdDuringChannelCreation: Bool, within: ObvContext) throws
    
    func getDeviceUidsOfContactIdentity(_: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> Set<UID>

    /// This method throws if the second identity is not an owned identity or if the first identity is not a contact of that owned identity. Otherwise it returns `true` iff the UID passed corresponds to the UID of contact device of the contact identity.
    func isDevice(withUid: UID, aDeviceOfContactIdentity: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> Bool

    /// This method returns a set of all the device uids known within the identity manager. This includes *both* owned device and contact devices.
    func getAllRemoteOwnedDevicesUidsAndContactDeviceUids(within: ObvContext) throws -> Set<ObliviousChannelIdentifier>
    
    /// This method returns a set of all the device uids known within the identity manager, with an "old" `latestChannelCreationPingTimestamp`. This includes *both* owned device and contact devices.
    func getAllRemoteOwnedDevicesUidsAndContactDeviceUidsWithLatestChannelCreationPingTimestamp(earlierThan date: Date, within obvContext: ObvContext) throws -> Set<ObliviousChannelIdentifier>
    
    func processContactDeviceDiscoveryResult(_ contactDeviceDiscoveryResult: ContactDeviceDiscoveryResult, forContactCryptoId contactCryptoId: ObvCryptoIdentity, ofOwnedCryptoId ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws
    
    func getLatestChannelCreationPingTimestampOfContactDevice(withIdentifier contactDeviceIdentifier: ObvContactDeviceIdentifier, within obvContext: ObvContext) throws -> Date?

    func setLatestChannelCreationPingTimestampOfContactDevice(withIdentifier contactDeviceIdentifier: ObvContactDeviceIdentifier, to date: Date, within obvContext: ObvContext) throws
    
    // MARK: - API related to contact groups
    
    func removeContactFromPendingAndGroupMembersOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupOwner: ObvCryptoIdentity, groupUid: UID, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws

    func createContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupInformationWithPhoto: GroupInformationWithPhoto, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, within obvContext: ObvContext) throws -> GroupInformationWithPhoto
    
    func createContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation, groupOwner: ObvCryptoIdentity, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, within obvContext: ObvContext) throws

    func transferPendingMemberToGroupMembersOfContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, pendingMember: ObvCryptoIdentity, within obvContext: ObvContext, groupMembersChangedCallback: () throws -> Void) throws
    
    func transferGroupMemberToPendingMembersOfContactGroupOwnedAndMarkPendingMemberAsDeclined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupMember: ObvCryptoIdentity, within obvContext: ObvContext, groupMembersChangedCallback: () throws -> Void) throws

    func addPendingMembersToContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, newPendingMembers: Set<ObvCryptoIdentity>, within obvContext: ObvContext, groupMembersChangedCallback: () throws -> Void) throws

    func removePendingAndMembersToContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, pendingOrMembersToRemove: Set<ObvCryptoIdentity>, within obvContext: ObvContext, groupMembersChangedCallback: () throws -> Void) throws

    func markPendingMemberAsDeclined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, pendingMember: ObvCryptoIdentity, within obvContext: ObvContext) throws

    func unmarkDeclinedPendingMemberAsDeclined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, pendingMember: ObvCryptoIdentity, within obvContext: ObvContext) throws

    func updatePublishedDetailsOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation, within obvContext: ObvContext) throws

    func updateDownloadedPhotoOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupOwner: ObvCryptoIdentity, groupUid: UID, version: Int, photo: Data, within obvContext: ObvContext) throws

    func updateDownloadedPhotoOfContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, version: Int, photo: Data, within obvContext: ObvContext) throws

    func trustPublishedDetailsOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws

    func updateLatestDetailsOfContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID,  with newGroupDetails: GroupDetailsElementsWithPhoto, within obvContext: ObvContext) throws

    func setPhotoServerKeyAndLabelForContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws -> PhotoServerKeyAndLabel

    func discardLatestDetailsOfContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws

    func publishLatestDetailsOfContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws

    func updatePendingMembersAndGroupMembersOfContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupMembers: Set<CryptoIdentityWithCoreDetails>, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, groupMembersVersion: Int, within obvContext: ObvContext) throws

    func updatePendingMembersAndGroupMembersOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, groupMembers: Set<CryptoIdentityWithCoreDetails>, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, groupMembersVersion: Int, within obvContext: ObvContext) throws

    func getGroupOwnedStructure(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws -> GroupStructure?

    func getGroupJoinedStructure(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> GroupStructure?

    func getAllGroupStructures(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<GroupStructure>

    func getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws -> GroupInformationWithPhoto

    func getGroupJoinedInformationAndPublishedPhoto(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> GroupInformationWithPhoto

    func deleteContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws
    
    func deleteContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, deleteEvenIfGroupMembersStillExist: Bool, within obvContext: ObvContext) throws

    func contactIdentityBelongsToSomeContactGroup(_ contactIdentity: ObvCryptoIdentity, forOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool

    func forceUpdateOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, authoritativeGroupInformation: GroupInformation, within obvContext: ObvContext) throws

    func resetGroupMembersVersionOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws

    func getAllOwnedIdentityWithMissingPhotoUrl(within obvContext: ObvContext) throws -> [(ObvCryptoIdentity, IdentityDetailsElements)]

    func getAllGroupsWithMissingPhotoUrl(within obvContext: ObvContext) throws -> [(ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation)]

    func getAllContactsWithMissingPhotoUrl(within obvContext: ObvContext) throws -> [(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, identityDetailsElements: IdentityDetailsElements)]

    func isContactRevokedAsCompromised(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool
    
    func isContactIdentityActive(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool

    func setContactForcefullyTrustedByUser(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, forcefullyTrustedByUser: Bool, within obvContext: ObvContext) throws

    func getOneToOneStatusOfContactIdentity(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> OneToOneStatusOfContactIdentity
    
    func setOneToOneContactStatus(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, newIsOneToOneStatus: Bool, reasonToLog: String, within obvContext: ObvContext) throws
    
    func getContactsOfAllActiveOwnedIdentitiesRequiringContactDeviceDiscovery(within obvContext: ObvContext) throws -> Set<ObvContactIdentifier>

    // MARK: - API related to contact capabilities

    func getCapabilitiesOfContactIdentity(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvCapability>?
    
    func getCapabilitiesOfContactDevice(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, within obvContext: ObvContext) throws -> Set<ObvCapability>?

    func getCapabilitiesOfAllContactsOfOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> [ObvCryptoIdentity: Set<ObvCapability>]
    
    func setRawCapabilitiesOfContactDevice(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, uid: UID, newRawCapabilities: Set<String>, within obvContext: ObvContext) throws

    // MARK: - API related to own capabilities

    func getCapabilitiesOfOwnedIdentity(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvCapability>?
    
    func getCapabilitiesOfCurrentDeviceOfOwnedIdentity(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvCapability>?
    
    func getCapabilitiesOfOtherOwnedDevice(ownedIdentity: ObvCryptoIdentity, deviceUID: UID, within obvContext: ObvContext) throws -> Set<ObvCapability>?
    
    func setCapabilitiesOfCurrentDeviceOfOwnedIdentity(ownedIdentity: ObvCryptoIdentity, newCapabilities: Set<ObvCapability>, within obvContext: ObvContext) throws
    
    func setRawCapabilitiesOfOtherDeviceOfOwnedIdentity(ownedIdentity: ObvCryptoIdentity, deviceUID: UID, newRawCapabilities: Set<String>, within obvContext: ObvContext) throws
    
    // MARK: - API related to sync between owned devices
    
    func processSyncAtom(_ syncAtom: ObvSyncAtom, ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws

    // MARK: - User Data

    func getAllServerDataToSynchronizeWithServer(within obvContext: ObvContext) throws -> (toDelete: Set<UserData>, toRefresh: Set<UserData>)
    
    func getServerUserData(for ownedIdentity: ObvCryptoIdentity, with label: UID, within obvContext: ObvContext) -> UserData?

    func deleteUserData(for ownedIdentity: ObvCryptoIdentity, with label: UID, flowId: FlowIdentifier) async throws

    func updateUserDataNextRefreshTimestamp(for ownedIdentity: ObvCryptoIdentity, with label: UID, flowId: FlowIdentifier) async throws

    // MARK: - Getting informations about missing photos

    func getInformationsAboutContactsWithMissingContactPictureOnDisk(within obvContext: ObvContext) throws -> [(ownedCryptoId: ObvCryptoIdentity, contactCryptoId: ObvCryptoIdentity, contactIdentityDetailsElements: IdentityDetailsElements)]

    func getInformationsAboutOwnedIdentitiesWithMissingPictureOnDisk(within obvContext: ObvContext) throws -> [(ownedCryptoId: ObvCryptoIdentity, ownedIdentityDetailsElements: IdentityDetailsElements)]

    func getInformationsAboutGroupsV1WithMissingContactPictureOnDisk(within obvContext: ObvContext) throws -> [(ownedIdentity: ObvCryptoIdentity, groupInfo: GroupInformation)]

    func getInformationsAboutGroupsV2WithMissingContactPictureOnDisk(within obvContext: ObvContext) throws -> [(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, serverPhotoInfo: GroupV2.ServerPhotoInfo)]

    // MARK: - Restoring snapshots
    
    func restoreObvSyncSnapshotNode(_ syncSnapshotNode: any ObvSyncSnapshotNode, customDeviceName: String, within obvContext: ObvContext) throws
    
    // MARK: - Other pre-keys related methods
    
    func getUIDsOfRemoteDevicesForWhichHavePreKeys(ownedCryptoId: ObvCryptoIdentity, remoteCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<UID>

    func getUIDsOfRemoteDevicesForWhichHavePreKeys(ownedCryptoId: ObvCryptoIdentity, remoteCryptoIds: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws -> [ObvCryptoIdentity: Set<UID>]
    
    func deleteCurrentDeviceExpiredPreKeysOfOwnedIdentity(ownedCryptoId: ObvCryptoIdentity, downloadTimestampFromServer: Date, within obvContext: ObvContext) throws
    
    // MARK: - New Backups
    
    func getBackupSeedOfOwnedIdentity(ownedCryptoId: ObvCryptoId, restrictToActive: Bool, flowId: FlowIdentifier) async throws -> BackupSeed?

    func getAdditionalInfosFromIdentityManagerForProfileBackup(ownedCryptoId: ObvCryptoId, flowId: FlowIdentifier) async throws -> AdditionalInfosFromIdentityManagerForProfileBackup

    
}

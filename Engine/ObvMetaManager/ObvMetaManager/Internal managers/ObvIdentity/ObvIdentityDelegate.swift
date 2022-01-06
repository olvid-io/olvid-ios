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

import Foundation
import ObvCrypto
import ObvTypes
import OlvidUtils
import JWS

public protocol ObvIdentityDelegate: ObvBackupableManager {
    
    
    // MARK: - API related to owned identities
    
    /// This method returns `true` iff the `ObvCryptoIdentity` passed as a parameter is a longterm owned identity.
    ///
    /// - Parameters:
    ///   - _: the `ObvCryptoIdentity` to check
    ///   - within: the `NSManagedObjectContext` in which we want to perform the test
    /// - Returns: `true` if the identity is a (longterm) owned identity, `false` otherwise.
    func isOwned(_: ObvCryptoIdentity, within: ObvContext) throws -> Bool

    func isOwnedIdentityActive(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) throws -> Bool

    func deactivateOwnedIdentity(ownedIdentity: ObvCryptoIdentity, within: ObvContext) throws

    func reactivateOwnedIdentity(ownedIdentity: ObvCryptoIdentity, within: ObvContext) throws

    func generateOwnedIdentity(withApiKey: UUID, onServerURL: URL, with: ObvIdentityDetails, accordingTo: PublicKeyEncryptionImplementationByteId, and: AuthenticationImplementationByteId, keycloakState: ObvKeycloakState?, using: PRNGService, within: ObvContext) -> ObvCryptoIdentity?
    
    func getApiKeyOfOwnedIdentity(_: ObvCryptoIdentity, within: ObvContext) throws -> UUID

    func setAPIKey(_ apiKey: UUID, forOwnedIdentity identity: ObvCryptoIdentity, keycloakServerURL: URL?, within obvContext: ObvContext) throws

    // Implemented within ObvIdentityDelegateExtension.swift
    func generateOwnedIdentity(withApiKey: UUID, onServerURL: URL, with: ObvIdentityDetails, keycloakState: ObvKeycloakState?, using: PRNGService, within: ObvContext) -> ObvCryptoIdentity?
    
    func deleteOwnedIdentity(_: ObvCryptoIdentity, within: ObvContext) throws

    func getOwnedIdentities(within: ObvContext) throws -> Set<ObvCryptoIdentity>

    /// This method throws if the identity is not an owned identity. Otherwise it returns the display name of the owned identity.
    func getIdentityDetailsOfOwnedIdentity(_: ObvCryptoIdentity, within: ObvContext) throws -> (publishedIdentityDetails: ObvIdentityDetails, isActive: Bool)
    
    func getPublishedIdentityDetailsOfOwnedIdentity(_: ObvCryptoIdentity, within: ObvContext) throws -> (ownedIdentityDetailsElements: IdentityDetailsElements, photoURL: URL?)
    
    /// Returns  and updated version of the owned identity `IdentityDetailsElements`
    func setPhotoServerKeyAndLabelForPublishedIdentityDetailsOfOwnedIdentity(_: ObvCryptoIdentity, withPhotoServerKeyAndLabel: PhotoServerKeyAndLabel, within: ObvContext) throws -> IdentityDetailsElements
    
    func updateDownloadedPhotoOfOwnedIdentity(_: ObvCryptoIdentity, version: Int, photo: Data, within: ObvContext) throws

    func updatePublishedIdentityDetailsOfOwnedIdentity(_ identity: ObvCryptoIdentity, with newIdentityDetails: ObvIdentityDetails, within obvContext: ObvContext) throws

    func getDeterministicSeedForOwnedIdentity(_: ObvCryptoIdentity, diversifiedUsing: Data, within: ObvContext) throws -> Seed
    
    func getFreshMaskingUIDForPushNotifications(for: ObvCryptoIdentity, within: ObvContext) throws -> UID

    func getOwnedIdentityAssociatedToMaskingUID(_ maskingUID: UID, within obvContext: ObvContext) throws -> ObvCryptoIdentity?
    
    func computeTagForOwnedIdentity(_: ObvCryptoIdentity, on: Data, within obvContext: ObvContext) throws -> Data

    // MARK: - API related to keycloak management

    func isOwnedIdentityKeycloakManaged(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool

    func isContactCertifiedByOwnKeycloak(contactIdentity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool

    func getSignedContactDetails(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> SignedUserDetails?

    func getOwnedIdentityKeycloakState(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> (obvKeycloakState: ObvKeycloakState?, signedOwnedDetails: SignedUserDetails?)

    func saveKeycloakAuthState(ownedIdentity: ObvCryptoIdentity, rawAuthState: Data, within obvContext: ObvContext) throws

    func saveKeycloakJwks(ownedIdentity: ObvCryptoIdentity, jwks: ObvJWKSet, within obvContext: ObvContext) throws

    func getOwnedIdentityKeycloakUserId(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> String?

    func setOwnedIdentityKeycloakUserId(ownedIdentity: ObvCryptoIdentity, keycloakUserId userId: String?, within obvContext: ObvContext) throws

    /// This method binds an owned identity to a keycloak server. It returns a set of all the identities that are managed by the same keycloak server than the owned identity.
    func bindOwnedIdentityToKeycloak(ownedCryptoIdentity: ObvCryptoIdentity, keycloakUserId userId: String, keycloakState: ObvKeycloakState, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity>

    // This method unbinds the owned identity from any keycloak server and creates new published details for this identity using the currently published details, after removing any signed details.
    func unbindOwnedIdentityFromKeycloak(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws

    func setOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoIdentity: ObvCryptoIdentity, newSelfRevocationTestNonce: String?, within obvContext: ObvContext) throws

    func getOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> String?
    
    func setOwnedIdentityKeycloakSignatureKey(ownedCryptoIdentity: ObvCryptoIdentity, keycloakServersignatureVerificationKey: ObvJWK?, within obvContext: ObvContext) throws
    
    func getContactsCertifiedByOwnKeycloak(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity>
    
    func verifyAndAddRevocationList(ownedCryptoIdentity: ObvCryptoIdentity, signedRevocations: [String], revocationListTimetamp: Date, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity>
    
    func updateKeycloakPushTopicsIfNeeded(ownedCryptoIdentity: ObvCryptoIdentity, pushTopics: Set<String>, within obvContext: ObvContext) throws -> Bool

    func getKeycloakPushTopics(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<String>

    func getCryptoIdentitiesOfManagedOwnedIdentitiesAssociatedWithThePushTopic(_ pushTopic: String, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity>

    // MARK: - API related to owned devices
    
    func getDeviceUidsOfOwnedIdentity(_: ObvCryptoIdentity, within: ObvContext) throws -> Set<UID>

    /// This method throws if the UID passed is not a current device uid. Otherwise, it returns the crypto identity to whom the current device belongs.
    func getOwnedIdentityOfCurrentDeviceUid(_: UID, within: ObvContext) throws -> ObvCryptoIdentity

    func getOwnedIdentityOfRemoteDeviceUid(_: UID, within: ObvContext) -> ObvCryptoIdentity?

    func getCurrentDeviceUidOfOwnedIdentity(_: ObvCryptoIdentity, within: ObvContext) throws -> UID
    
    func getOtherDeviceUidsOfOwnedIdentity(_: ObvCryptoIdentity, within: ObvContext) throws -> Set<UID>

    func addDeviceForOwnedIdentity(_: ObvCryptoIdentity, withUid: UID, within: ObvContext) throws

    /// This method throws if the identity is not an owned identity. Otherwise it returns `true` iff the UID passed corresponds to the UID of a remote device of the owned identity.
    func isDevice(withUid: UID, aRemoteDeviceOfOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> Bool

    func deleteDevicesOfContactIdentity(contactIdentity: ObvCryptoIdentity, contactDeviceUids: Set<UID>, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws

    func deleteAllDevicesOfContactIdentity(contactIdentity: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws

    
    // MARK: - API related to contact identities
    
    func addContactIdentity(_: ObvCryptoIdentity, with: ObvIdentityCoreDetails, andTrustOrigin: TrustOrigin, forOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws

    func addTrustOrigin(_: TrustOrigin, toContactIdentity: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws
    
    func getTrustOrigins(forContactIdentity: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> [TrustOrigin]
    
    func getTrustLevel(forContactIdentity: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> TrustLevel
    
    func getContactsOfOwnedIdentity(_: ObvCryptoIdentity, within: ObvContext) throws -> Set<ObvCryptoIdentity>
    
    /// This method throws if the second identity is not an owned identity or if the first identity is not a contact of that owned identity. Otherwise it returns the display name of the contact identity.
    func getIdentityDetailsOfContactIdentity(_: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> (publishedIdentityDetails: ObvIdentityDetails?, trustedIdentityDetails: ObvIdentityDetails)

    func getPublishedIdentityDetailsOfContactIdentity(_: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> (contactIdentityDetailsElements: IdentityDetailsElements, photoURL: URL?)?
    
    func getTrustedIdentityDetailsOfContactIdentity(_: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> (contactIdentityDetailsElements: IdentityDetailsElements, photoURL: URL?)

    func updateTrustedIdentityDetailsOfContactIdentity(_ identity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, with newContactIdentityDetails: ObvIdentityDetails, within obvContext: ObvContext) throws

    func updateDownloadedPhotoOfContactIdentity(_: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, version: Int, photo: Data, within: ObvContext) throws

    func updatePublishedIdentityDetailsOfContactIdentity(_ identity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, with newContactIdentityDetailsElements: IdentityDetailsElements, allowVersionDowngrade: Bool, within obvContext: ObvContext) throws

    func isIdentity(_: ObvCryptoIdentity, aContactIdentityOfTheOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> Bool
    
    func deleteContactIdentity(_: ObvCryptoIdentity, forOwnedIdentity: ObvCryptoIdentity, failIfContactIsPartOfAGroupJoined: Bool, within: ObvContext) throws
    
    
    // MARK: - API related to contact devices
    
    func addDeviceForContactIdentity(_: ObvCryptoIdentity, withUid: UID, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws
    
    func removeDeviceForContactIdentity(_: ObvCryptoIdentity, withUid: UID, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws
    
    func getDeviceUidsOfContactIdentity(_: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> Set<UID>

    /// This method throws if the second identity is not an owned identity or if the first identity is not a contact of that owned identity. Otherwise it returns `true` iff the UID passed corresponds to the UID of contact device of the contact identity.
    func isDevice(withUid: UID, aDeviceOfContactIdentity: ObvCryptoIdentity, ofOwnedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> Bool

    /// This method returns an array of all the device uids known within the identity manager. This includes *both* owned device and contact devices.
    func getAllRemoteOwnedDevicesUidsAndContactDeviceUids(within: ObvContext) throws -> Set<ObliviousChannelIdentifier>
    
    // MARK: - API related to contact groups
    
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

    func updatePendingMembersAndGroupMembersOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, groupMembers: Set<CryptoIdentityWithCoreDetails>, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, groupMembersVersion: Int, within obvContext: ObvContext) throws

    func getGroupOwnedStructure(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws -> GroupStructure?

    func getGroupJoinedStructure(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> GroupStructure?

    func getAllGroupStructures(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<GroupStructure>

    func getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws -> GroupInformationWithPhoto

    func getGroupJoinedInformationAndPublishedPhoto(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> GroupInformationWithPhoto

    func leaveContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws
    
    func deleteContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws

    func contactIdentityBelongsToSomeContactGroup(_ contactIdentity: ObvCryptoIdentity, forOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool

    func forceUpdateOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, authoritativeGroupInformation: GroupInformation, within obvContext: ObvContext) throws

    func resetGroupMembersVersionOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws

    func getAllOwnedIdentityWithMissingPhotoUrl(within obvContext: ObvContext) throws -> [(ObvCryptoIdentity, IdentityDetailsElements)]

    func getAllGroupsWithMissingPhotoUrl(within obvContext: ObvContext) throws -> [(ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation)]

    func getAllContactsWithMissingPhotoUrl(within obvContext: ObvContext) throws -> [(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, identityDetailsElements: IdentityDetailsElements)]

    func isContactRevokedAsCompromised(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool
    
    func isContactIdentityActive(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool

    func setContactForcefullyTrustedByUser(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, forcefullyTrustedByUser: Bool, within obvContext: ObvContext) throws
    
    // MARK: - User Data

    func getAllServerDataToSynchronizeWithServer(within obvContext: ObvContext) throws -> (toDelete: Set<UserData>, toRefresh: Set<UserData>)
    
    func getServerUserData(for ownedIdentity: ObvCryptoIdentity, with label: String, within obvContext: ObvContext) -> UserData?

    func deleteUserData(for ownedIdentity: ObvCryptoIdentity, with label: String, within obvContext: ObvContext)

    func updateUserDataNextRefreshTimestamp(for ownedIdentity: ObvCryptoIdentity, with label: String, within obvContext: ObvContext)

}

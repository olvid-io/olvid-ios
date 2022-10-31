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
import CoreData
import os.log
import OlvidUtils
import ObvCrypto
import ObvMetaManager
import ObvEncoder
import ObvTypes
import JWS

public final class ObvIdentityManagerImplementation {
    
    // MARK: Instance variables
    
    public var logSubsystem: String { return delegateManager.logSubsystem }
    
    public func prependLogSubsystem(with prefix: String) {
        delegateManager.prependLogSubsystem(with: prefix)
    }
    
    lazy private var log = OSLog(subsystem: logSubsystem, category: "ObvIdentityManagerImplementation")
    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {
        guard forTheFirstTime else { return }
        deleteUnusedIdentityPhotos(flowId: flowId)
        pruneOldKeycloakRevokedIdentityAndUncertifyExpiredSignedContactDetails(flowId: flowId)
        deleteOrphanedContactGroupV2Details(flowId: flowId)
    }

    let prng: PRNGService
    let identityPhotosDirectory: URL

    private static let errorDomain = String(describing: ObvIdentityManagerImplementation.self)
    
    /// Strong reference to the delegate manager, which keeps strong references to all external and internal delegate requirements.
    let delegateManager: ObvIdentityDelegateManager
    
    // MARK: Initialiser
    public init(sharedContainerIdentifier: String, prng: PRNGService, identityPhotosDirectory: URL) {
        self.prng = prng
        self.identityPhotosDirectory = identityPhotosDirectory
        self.delegateManager = ObvIdentityDelegateManager(sharedContainerIdentifier: sharedContainerIdentifier, identityPhotosDirectory: identityPhotosDirectory, prng: prng)
    }
    
    deinit {
        debugPrint("Deinit of ObvIdentityManagerImplementation")
    }
    
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

}


// MARK: - Implementing ObvIdentityDelegate

extension ObvIdentityManagerImplementation: ObvIdentityDelegate {
    
    public static var backupIdentifier: String {
        return "identity_manager"
    }
    
    public var backupIdentifier: String {
        return ObvIdentityManagerImplementation.backupIdentifier
    }
    
    public var backupSource: ObvBackupableObjectSource { .engine }
    
    public func provideInternalDataForBackup(backupRequestIdentifier: FlowIdentifier) async throws -> (internalJson: String, internalJsonIdentifier: String, source: ObvBackupableObjectSource) {
        let delegateManager = self.delegateManager
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(internalJson: String, internalJsonIdentifier: String, source: ObvBackupableObjectSource), Error>) in
            do {
                try delegateManager.contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: backupRequestIdentifier) { obvContext in
                    let ownedIdentities = try OwnedIdentity.getAll(delegateManager: delegateManager, within: obvContext)
                    guard !ownedIdentities.isEmpty else {
                        throw Self.makeError(message: "No data to backup since we could not find any owned identity")
                    }
                    let ownedIdentitiesBackupItems = Set(ownedIdentities.map { $0.backupItem })
                    let jsonEncoder = JSONEncoder()
                    let data = try jsonEncoder.encode(ownedIdentitiesBackupItems)
                    guard let internalData = String(data: data, encoding: .utf8) else {
                        throw Self.makeError(message: "Could not convert json to UTF8 string during backup")
                    }
                    continuation.resume(returning: (internalData, ObvIdentityManagerImplementation.backupIdentifier, .engine))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    
    public func restoreBackup(backupRequestIdentifier: FlowIdentifier, internalJson: String) async throws {
        let delegateManager = self.delegateManager
        let log = self.log
        let prng = self.prng
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try delegateManager.contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: backupRequestIdentifier) { (obvContext) in
                    let ownedIdentities = try OwnedIdentity.getAll(delegateManager: delegateManager, within: obvContext)
                    guard ownedIdentities.isEmpty else {
                        throw Self.makeError(message: "📲 An owned identity is already present in database. The engine does not support multiple owned identities at this time")
                    }
                    // If we reach this point, we can try to restore the backup
                    let internalJsonData = internalJson.data(using: .utf8)!
                    let jsonDecoder = JSONDecoder()
                    let ownedIdentityBackupItems = try jsonDecoder.decode([OwnedIdentityBackupItem].self, from: internalJsonData)
                    
                    os_log("📲 The identity manager successfully parsed the internal json during the restore of the backup within flow %{public}@", log: log, type: .info, backupRequestIdentifier.debugDescription)
                    
                    guard ownedIdentityBackupItems.count == 1, let ownedIdentityBackupItem = ownedIdentityBackupItems.first else {
                        os_log("📲 Unexpected number of owned identity to restore. We expect exactly one, we got %d", log: log, type: .fault, ownedIdentityBackupItems.count)
                        throw Self.makeError(message: "Unexpected number of owned identity to restore")
                    }
                    
                    os_log("📲 We have exactly one owned identity to restore within flow %{public}@. We restore it now.", log: log, type: .info, backupRequestIdentifier.debugDescription)
                    
                    os_log("📲 Restoring the database owned identity instance within flow %{public}@...", log: log, type: .info, backupRequestIdentifier.debugDescription)
                    
                    let associationsForRelationships: BackupItemObjectAssociations
                    do {
                        var associations = BackupItemObjectAssociations()
                        try ownedIdentityBackupItem.restoreInstance(within: obvContext,
                                                                    associations: &associations,
                                                                    notificationDelegate: delegateManager.notificationDelegate)
                        associationsForRelationships = associations
                    }
                    
                    os_log("📲 The instances were re-created. We now recreate the relationships.", log: log, type: .info)
                    
                    try ownedIdentityBackupItem.restoreRelationships(associations: associationsForRelationships, prng: prng, within: obvContext)
                    
                    os_log("📲 The relationships were recreated. Saving the context.", log: log, type: .info)
                    
                    try obvContext.save(logOnFailure: log)
                    
                    os_log("📲 Context saved. We successfully restored the owned identity. Yepee!", log: log, type: .info, backupRequestIdentifier.debugDescription)
                    
                    continuation.resume()
                    return
                    
                }
            } catch {
                continuation.resume(throwing: error)
                return
            }
        }
    }

    
    public func getAllOwnedIdentityWithMissingPhotoUrl(within obvContext: ObvContext) throws -> [(ObvCryptoIdentity, IdentityDetailsElements)] {
        let details = try OwnedIdentityDetailsPublished.getAllWithMissingPhotoFilename(within: obvContext)
        let results = details.map { ($0.ownedIdentity.cryptoIdentity, $0.getIdentityDetailsElements(identityPhotosDirectory: delegateManager.identityPhotosDirectory)) }
        return results
    }
    
    
    public func getAllGroupsWithMissingPhotoUrl(within obvContext: ObvContext) throws -> [(ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation)] {
        let details = try ContactGroupDetails.getAllWithMissingPhotoURL(within: obvContext)
        let groups = try details.map({ try $0.getContactGroup() })
        var groupInfosPerOwnedIdentity = [ObvCryptoIdentity: Set<GroupInformation>]()
        for group in groups {
            if var currentGroupInformation = groupInfosPerOwnedIdentity[group.ownedIdentity.cryptoIdentity] {
                currentGroupInformation.insert(try group.getPublishedGroupInformation())
                groupInfosPerOwnedIdentity[group.ownedIdentity.cryptoIdentity] = currentGroupInformation
            } else {
                groupInfosPerOwnedIdentity[group.ownedIdentity.cryptoIdentity] = Set([try group.getPublishedGroupInformation()])
            }
        }
        var results = [(ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation)]()
        for (ownedIdentity, groupInfos) in groupInfosPerOwnedIdentity {
            for info in groupInfos {
                results.append((ownedIdentity, info))
            }
        }
        return results
    }
    
    
    public func getAllContactsWithMissingPhotoUrl(within obvContext: ObvContext) throws -> [(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, identityDetailsElements: IdentityDetailsElements)] {
        let details = try ContactIdentityDetails.getAllWithMissingPhotoFilename(within: obvContext)
        let results: [(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, identityDetailsElements: IdentityDetailsElements)] = details.compactMap { contactIdentityDetails in
            guard let identityDetailsElements = contactIdentityDetails.getIdentityDetailsElements(identityPhotosDirectory: delegateManager.identityPhotosDirectory) else {
                assertionFailure()
                return nil
            }
            return (contactIdentityDetails.contactIdentity.ownedIdentity.cryptoIdentity,
                    contactIdentityDetails.contactIdentity.cryptoIdentity,
                    identityDetailsElements)
        }
        return results
    }
    

    // MARK: API related to owned identities

    
    public func isOwned(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        return try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) != nil
    }


    public func isOwnedIdentityActive(ownedIdentity identity: ObvCryptoIdentity, flowId: FlowIdentifier) throws -> Bool {
        var _isActive: Bool?
        try delegateManager.contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
                throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
            }
            _isActive = ownedIdentity.isActive
        }
        guard let isActive = _isActive else {
            assertionFailure()
            throw makeError(message: "Bug in isOwnedIdentityActive. _isActive is not set although it should be.")
        }
        return isActive
    }
    
    
    public func deactivateOwnedIdentity(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        os_log("Deactivating owned identity %{public}@", log: log, type: .info, ownedIdentity.debugDescription)
        guard let ownedIdentityObj = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            assertionFailure()
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        ownedIdentityObj.deactivate()
    }
    
    
    public func reactivateOwnedIdentity(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        os_log("Reactivating owned identity %{public}@", log: log, type: .info, ownedIdentity.debugDescription)
        guard let ownedIdentityObj = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            assertionFailure()
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        ownedIdentityObj.reactivate()
    }

    public func generateOwnedIdentity(withApiKey apiKey: UUID, onServerURL serverURL: URL, with identityDetails: ObvIdentityDetails, accordingTo pkEncryptionImplemByteId: PublicKeyEncryptionImplementationByteId, and authEmplemByteId: AuthenticationImplementationByteId, keycloakState: ObvKeycloakState?, using prng: PRNGService, within obvContext: ObvContext) -> ObvCryptoIdentity? {
        guard let ownedIdentity = OwnedIdentity(apiKey: apiKey,
                                                serverURL: serverURL,
                                                identityDetails: identityDetails,
                                                accordingTo: pkEncryptionImplemByteId,
                                                and: authEmplemByteId,
                                                keycloakState: keycloakState,
                                                using: prng,
                                                delegateManager: delegateManager,
                                                within: obvContext) else { return nil }
        let ownedCryptoIdentity = ownedIdentity.ownedCryptoIdentity.getObvCryptoIdentity()
        return ownedCryptoIdentity
    }

    
    public func getApiKeyOfOwnedIdentity(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> UUID {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        return ownedIdentity.apiKey
    }
    
    public func setAPIKey(_ apiKey: UUID, forOwnedIdentity identity: ObvCryptoIdentity, keycloakServerURL: URL?, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        try ownedIdentity.setAPIKey(to: apiKey, keycloakServerURL: keycloakServerURL)
    }
    
    
    public func deleteOwnedIdentity(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        if let identityObj = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) {
            try identityObj.delete(delegateManager: delegateManager, within: obvContext)
        }
    }

    
    public func getOwnedIdentities(within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity> {
        let ownedIdentities = try OwnedIdentity.getAll(delegateManager: delegateManager, within: obvContext)
        let cryptoIdentities = ownedIdentities.map { $0.ownedCryptoIdentity.getObvCryptoIdentity() }
        return Set(cryptoIdentities)
    }

    
    public func getIdentityDetailsOfOwnedIdentity(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> (publishedIdentityDetails: ObvIdentityDetails, isActive: Bool) {
        guard let ownedIdentityObj = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        return (ownedIdentityObj.publishedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory), ownedIdentityObj.isActive)
    }

    
    // Used within the protocol manager
    public func getPublishedIdentityDetailsOfOwnedIdentity(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> (ownedIdentityDetailsElements: IdentityDetailsElements, photoURL: URL?) {
        
        guard let ownedIdentityObj = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        
        let ownedIdentityDetailsElements = IdentityDetailsElements(
            version: ownedIdentityObj.publishedIdentityDetails.version,
            coreDetails: ownedIdentityObj.publishedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory).coreDetails,
            photoServerKeyAndLabel: ownedIdentityObj.publishedIdentityDetails.photoServerKeyAndLabel)
        return (ownedIdentityDetailsElements, ownedIdentityObj.publishedIdentityDetails.getPhotoURL(identityPhotosDirectory: delegateManager.identityPhotosDirectory))
    }
    
    
    public func setPhotoServerKeyAndLabelForPublishedIdentityDetailsOfOwnedIdentity(_ identity: ObvCryptoIdentity, withPhotoServerKeyAndLabel photoServerKeyAndLabel: PhotoServerKeyAndLabel, within obvContext: ObvContext) throws -> IdentityDetailsElements {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        ownedIdentity.publishedIdentityDetails.set(photoServerKeyAndLabel: photoServerKeyAndLabel)
        _ = IdentityServerUserData.createForOwnedIdentityDetails(ownedIdentity: identity,
                                                                 label: photoServerKeyAndLabel.label,
                                                                 within: obvContext)
        return ownedIdentity.publishedIdentityDetails.getIdentityDetailsElements(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
    }

    
    public func updateDownloadedPhotoOfOwnedIdentity(_ identity: ObvCryptoIdentity, version: Int, photo: Data, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        try ownedIdentity.updatePhoto(withData: photo, version: version, delegateManager: delegateManager, within: obvContext)
    }


    public func updatePublishedIdentityDetailsOfOwnedIdentity(_ identity: ObvCryptoIdentity, with newIdentityDetails: ObvIdentityDetails, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        try ownedIdentity.updatePublishedDetailsWithNewDetails(newIdentityDetails, delegateManager: delegateManager)
    }
    
    
    public func getDeterministicSeedForOwnedIdentity(_ identity: ObvCryptoIdentity, diversifiedUsing data: Data, within obvContext: ObvContext) throws -> Seed {
        guard let ownedIdentityObj = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext)  else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard !data.isEmpty else {
            throw ObvIdentityManagerError.diversificationDataCannotBeEmpty.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        let sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()
        let fixedByte = Data([0x55])
        var hashInput = try MAC.compute(forData: fixedByte, withKey: ownedIdentityObj.ownedCryptoIdentity.secretMACKey)
        hashInput.append(data)
        let r = sha256.hash(hashInput)
        guard let seed = Seed(with: r) else {
            throw ObvIdentityManagerError.failedToTurnRandomIntoSeed.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        return seed
    }
    
    
    public func getFreshMaskingUIDForPushNotifications(for identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> UID {
        guard let ownedIdentityObj = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        let maskingUID = try OwnedIdentityMaskingUID.getOrCreate(for: ownedIdentityObj, prng: self.prng)
        return maskingUID
    }
    
    
    public func getOwnedIdentityAssociatedToMaskingUID(_ maskingUID: UID, within obvContext: ObvContext) throws -> ObvCryptoIdentity? {
        let ownedIdentity = try OwnedIdentityMaskingUID.getOwnedIdentityAssociatedWithMaskingUID(maskingUID, within: obvContext)
        return ownedIdentity?.cryptoIdentity
    }
    
    public func computeTagForOwnedIdentity(_ identity: ObvCryptoIdentity, on data: Data, within obvContext: ObvContext) throws -> Data {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        let mac = ObvCryptoSuite.sharedInstance.mac()
        let dataToMac = "OwnedIdentityTag".data(using: .utf8)! + data
        return try mac.compute(forData: dataToMac, withKey: ownedIdentity.ownedCryptoIdentity.secretMACKey)
    }

    
    // MARK: - API related to contact groups V2
    
    public func createContactGroupV2AdministratedByOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, serializedGroupCoreDetails: Data, photoURL: URL?, ownRawPermissions: Set<String>, otherGroupMembers: Set<GroupV2.IdentityAndPermissions>, within obvContext: ObvContext) throws -> (groupIdentifier: GroupV2.Identifier, groupAdminServerAuthenticationPublicKey: PublicKeyForAuthentication, serverPhotoInfo: GroupV2.ServerPhotoInfo?, encryptedServerBlob: EncryptedData, photoURL: URL?) {

        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }

        let (group, publicKey) = try ContactGroupV2.createContactGroupV2AdministratedByOwnedIdentity(ownedIdentity,
                                                                                                     serializedGroupCoreDetails: serializedGroupCoreDetails,
                                                                                                     photoURL: photoURL,
                                                                                                     ownRawPermissions: ownRawPermissions,
                                                                                                     otherGroupMembers: otherGroupMembers,
                                                                                                     using: prng,
                                                                                                     solveChallengeDelegate: self,
                                                                                                     delegateManager: delegateManager)
        
        guard let groupIdentifier = group.groupIdentifier else { assertionFailure(); throw Self.makeError(message: "Could not extract group identifier") }
        let serverPhotoInfo = try group.getServerBlob().serverPhotoInfo
        let encryptedServerBlob = try group.getEncryptedServerBlob(solveChallengeDelegate: self, using: prng, within: obvContext)
        let photoURL = group.getTrustedPhotoURL(delegateManager: delegateManager)
        
        return (groupIdentifier, publicKey, serverPhotoInfo, encryptedServerBlob, photoURL)
    }
    
    
    public func createContactGroupV2JoinedByOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, serverBlob: GroupV2.ServerBlob, blobKeys: GroupV2.BlobKeys, within obvContext: ObvContext) throws {

        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }

        try ContactGroupV2.createContactGroupV2JoinedByOwnedIdentity(ownedIdentity,
                                                                     groupIdentifier: groupIdentifier,
                                                                     serverBlob: serverBlob,
                                                                     blobKeys: blobKeys,
                                                                     delegateManager: delegateManager)
    }

    
    public func deleteContactGroupV2(withGroupIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { return }
        try group.delete()
    }
    
    
    public func removeOtherMembersOrPendingMembersFromGroupV2(withGroupIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, identitiesToRemove: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { return }
        try group.removeOtherMembersOrPendingMembers(identitiesToRemove)
    }
    
    
    public func freezeGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { return }
        group.freeze()
    }

    
    public func unfreezeGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { return }
        group.unfreeze()
    }
    
    
    public func getGroupV2BlobKeysOfGroup(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> GroupV2.BlobKeys {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        guard let blobKeys = group.blobKeys else { assertionFailure(); throw Self.makeError(message: "Could not extract blob keys from group") }
        return blobKeys
    }
    
    
    public func getPendingMembersAndPermissionsOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<GroupV2.IdentityAndPermissions> {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        let pendingMembersAndPermissions = try group.getPendingMembersAndPermissions()
        return pendingMembersAndPermissions
    }
    
    
    public func getVersionOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Int {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        return group.groupVersion
    }
    
    
    public func checkExistenceOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager)
        return group != nil
    }

    
    public func deleteGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager)
        try group?.delete()
    }


    public func updateGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, newBlobKeys: GroupV2.BlobKeys, consolidatedServerBlob: GroupV2.ServerBlob, groupUpdatedByOwnedIdentity: Bool, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity> {
        // We create a local context that we can discard in case this method should throw
        let localContext = obvContext.createChildObvContext()
        var insertedOrUpdatedIdentities: Set<ObvCryptoIdentity>!
        try localContext.performAndWaitOrThrow {
            guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: localContext) else {
                throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
            }
            guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
            insertedOrUpdatedIdentities = try group.updateGroupV2(newBlobKeys: newBlobKeys,
                                                                  consolidatedServerBlob: consolidatedServerBlob,
                                                                  groupUpdatedByOwnedIdentity: groupUpdatedByOwnedIdentity,
                                                                  delegateManager: delegateManager)
            try localContext.save(logOnFailure: log)
        }
        return insertedOrUpdatedIdentities
    }

    
    public func getAllOtherMembersOrPendingMembersOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, memberOrPendingMemberInvitationNonce nonce: Data, within obvContext: ObvContext) throws -> Set<GroupV2.IdentityAndPermissionsAndDetails> {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        return try group.getAllOtherMembersOrPendingMembersIdentifiedByNonce(nonce)
    }
    
    
    public func movePendingMemberToMembersOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, pendingMemberCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        try group.movePendingMemberToOtherMembers(pendingMemberCryptoIdentity: pendingMemberCryptoIdentity, delegateManager: delegateManager)
    }
    
    
    public func getOwnGroupInvitationNonceOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Data {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        return group.ownGroupInvitationNonce
    }
    
    
    public func setDownloadedPhotoOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, serverPhotoInfo: GroupV2.ServerPhotoInfo, photo: Data, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        try group.updatePhoto(withData: photo, serverPhotoInfo: serverPhotoInfo, delegateManager: delegateManager)
    }
    
    public func photoNeedsToBeDownloadedForGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, serverPhotoInfo: GroupV2.ServerPhotoInfo, within obvContext: ObvContext) throws -> Bool {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        return group.photoNeedsToBeDownloaded(serverPhotoInfo: serverPhotoInfo, delegateManager: delegateManager)
    }

    
    public func getAllObvGroupV2(of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvGroupV2> {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        let groups = try ContactGroupV2.getAllObvGroupV2(of: ownedIdentity, delegateManager: delegateManager)
        return groups
    }
    
    
    public func getTrustedPhotoURLAndUploaderOfObvGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> (url: URL, uploader: ObvCryptoIdentity)? {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        guard let photoURLAndUploader = group.trustedDetails?.getPhotoURLAndUploader(identityPhotosDirectory: delegateManager.identityPhotosDirectory) else { return nil }
        guard FileManager.default.fileExists(atPath: photoURLAndUploader.url.path) else { assertionFailure(); return nil }
        return photoURLAndUploader
    }
    
    
    public func replaceTrustedDetailsByPublishedDetailsOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else {
            throw Self.makeError(message: "Could not find group")
        }
        try group.replaceTrustedDetailsByPublishedDetails(identityPhotosDirectory: identityPhotosDirectory, delegateManager: delegateManager)
    }
    
    
    public func getAdministratorChainOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> GroupV2.AdministratorsChain {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else {
            throw Self.makeError(message: "Could not find group")
        }
        return try group.getServerBlob().administratorsChain
    }
    
    
    public func getAllOtherMembersOrPendingMembersOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<GroupV2.IdentityAndPermissionsAndDetails> {
        
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        return try group.getAllOtherMembersOrPendingMembers()

    }
    

    public func getAllNonPendingAdministratorsIdentitiesOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity> {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        return try group.getAllNonPendingAdministratorsIdentitites()
    }

    
    public func getAllGroupsV2IdentifierVersionAndKeysForContact(_ contactIdentity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> [GroupV2.IdentifierVersionAndKeys] {
        guard let contact = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find contact")
        }
        guard let ownedIdentity_ = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        let identifierVersionAndKeysOfGroupsWhereTheContactIsNotPending = contact.groupMemberships.compactMap { $0.contactGroup?.identifierVersionAndKeys }
        let identifierVersionAndKeysOfGroupsWhereTheContactIsPending = (try ContactGroupV2PendingMember.getPendingMemberEntriesCorrespondingToContactIdentity(contactIdentity, of: ownedIdentity_)).compactMap({ $0.contactGroup?.identifierVersionAndKeys })

        let allIdentifierVersionAndKeys = identifierVersionAndKeysOfGroupsWhereTheContactIsNotPending + identifierVersionAndKeysOfGroupsWhereTheContactIsPending

        return allIdentifierVersionAndKeys
    }
    
    // MARK: - API related to keycloak management

    public func isOwnedIdentityKeycloakManaged(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        guard let ownedIdentity_ = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        return ownedIdentity_.isKeycloakManaged
    }

    public func isContactCertifiedByOwnKeycloak(contactIdentity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        guard let contactObj = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find contact")
        }
        return contactObj.isCertifiedByOwnKeycloak
    }
    
    
    public func getSignedContactDetails(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> SignedUserDetails? {
        guard let contactObj = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find contact")
        }
        return try contactObj.getSignedUserDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
    }


    public func getOwnedIdentityKeycloakState(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> (obvKeycloakState: ObvKeycloakState?, signedOwnedDetails: SignedUserDetails?) {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find Owned Identity in database")
        }
        guard let obvKeycloakState = try ownedIdentity.keycloakServer?.toObvKeycloakState else {
            return (nil, nil)
        }
        let coreDetails = ownedIdentity.publishedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory).coreDetails
        guard let signatureVerificationKey = obvKeycloakState.signatureVerificationKey, let signedDetails = coreDetails.signedUserDetails else {
            return (obvKeycloakState, nil)
        }
        let signedOwnedDetails = try? SignedUserDetails.verifySignedUserDetails(signedDetails, with: signatureVerificationKey)
        assert(signedOwnedDetails != nil, "An invalid signature should not have been stored in the first place")
        return (obvKeycloakState, signedOwnedDetails)
    }

    public func saveKeycloakAuthState(ownedIdentity: ObvCryptoIdentity, rawAuthState: Data, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find Owned Identity in database")
        }
        ownedIdentity.keycloakServer?.setAuthState(authState: rawAuthState)
    }

    public func saveKeycloakJwks(ownedIdentity: ObvCryptoIdentity, jwks: ObvJWKSet, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find Owned Identity in database")
        }
        assert(ownedIdentity.keycloakServer != nil)
        try ownedIdentity.keycloakServer?.setJwks(jwks)
    }
    
    public func getOwnedIdentityKeycloakUserId(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> String? {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find Owned Identity in database")
        }
        return ownedIdentity.keycloakServer?.keycloakUserId
    }

    public func setOwnedIdentityKeycloakUserId(ownedIdentity: ObvCryptoIdentity, keycloakUserId userId: String?, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find Owned Identity in database")
        }
        ownedIdentity.keycloakServer?.setKeycloakUserId(keycloakUserId: userId)
    }

    public func bindOwnedIdentityToKeycloak(ownedCryptoIdentity: ObvCryptoIdentity, keycloakUserId userId: String, keycloakState: ObvKeycloakState, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity> {

        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find Owned Identity in database")
        }

        try ownedIdentity.bindToKeycloak(keycloakState: keycloakState, delegateManager: delegateManager)
        try setOwnedIdentityKeycloakUserId(ownedIdentity: ownedCryptoIdentity, keycloakUserId: userId, within: obvContext)
        assert(ownedIdentity.isKeycloakManaged)

        // Once our owned identity is bind, we create the updated list of the contact that are managed by the same keycloak than ours.
        // This will be cached by the app.
        let contactsCertifiedByOwnKeycloak = Set(ownedIdentity.contactIdentities.filter({ $0.isCertifiedByOwnKeycloak }).map({ $0.cryptoIdentity }))
        
        return contactsCertifiedByOwnKeycloak
        
    }
    
    
    public func getContactsCertifiedByOwnKeycloak(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity> {
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find Owned Identity in database")
        }
        guard ownedIdentity.isKeycloakManaged else { return Set<ObvCryptoIdentity>() }
        let contactsCertifiedByOwnKeycloak = Set(ownedIdentity.contactIdentities.filter({ $0.isCertifiedByOwnKeycloak }).map({ $0.cryptoIdentity }))
        return contactsCertifiedByOwnKeycloak
    }
    
    
    public func unbindOwnedIdentityFromKeycloak(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find Owned Identity in database")
        }
        try ownedIdentity.unbindFromKeycloak(delegateManager: delegateManager)
        assert(!ownedIdentity.isKeycloakManaged)

        let publishedDetails = ownedIdentity.publishedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
        let publishedDetailsWithoutSignedDetails = try publishedDetails.removingSignedUserDetails()

        try updatePublishedIdentityDetailsOfOwnedIdentity(ownedCryptoIdentity, with: publishedDetailsWithoutSignedDetails, within: obvContext)
        
    }
    
    
    public func setOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoIdentity: ObvCryptoIdentity, newSelfRevocationTestNonce: String?, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find Owned Identity in database")
        }
        assert(ownedIdentity.isKeycloakManaged)
        ownedIdentity.keycloakServer?.setSelfRevocationTestNonce(newSelfRevocationTestNonce)
    }
    
    
    public func getOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> String? {
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find Owned Identity in database")
        }
        assert(ownedIdentity.isKeycloakManaged)
        return ownedIdentity.keycloakServer?.selfRevocationTestNonce
    }
    
    
    public func setOwnedIdentityKeycloakSignatureKey(ownedCryptoIdentity: ObvCryptoIdentity, keycloakServersignatureVerificationKey: ObvJWK?, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find Owned Identity in database")
        }
        assert(ownedIdentity.isKeycloakManaged)
        try ownedIdentity.setOwnedIdentityKeycloakSignatureKey(keycloakServersignatureVerificationKey, delegateManager: delegateManager)
    }
    
    
    /// This method will process the signed revocations. In the process, certained contacts may be considered as compromised. This method returns these contacts, which will allow the engine to delete all the channels we have with this contact.
    public func verifyAndAddRevocationList(ownedCryptoIdentity: ObvCryptoIdentity, signedRevocations: [String], revocationListTimetamp: Date, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity> {
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find Owned Identity in database")
        }
        assert(ownedIdentity.isKeycloakManaged)
        let compromisedContacts = try ownedIdentity.verifyAndAddRevocationList(signedRevocations: signedRevocations, revocationListTimetamp: revocationListTimetamp, delegateManager: delegateManager)
        ownedIdentity.pruneOldKeycloakRevokedContacts(delegateManager: delegateManager)
        ownedIdentity.uncertifyExpiredSignedContactDetails(delegateManager: delegateManager)
        return compromisedContacts
    }
    
    
    public func updateKeycloakPushTopicsIfNeeded(ownedCryptoIdentity: ObvCryptoIdentity, pushTopics: Set<String>, within obvContext: ObvContext) throws -> Bool {
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find Owned Identity in database")
        }
        assert(ownedIdentity.isKeycloakManaged)
        let storedPushTopicsUpdated = ownedIdentity.updateKeycloakPushTopicsIfNeeded(pushTopics: pushTopics)
        return storedPushTopicsUpdated
    }
    
    
    public func getKeycloakPushTopics(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<String> {
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find Owned Identity in database")
        }
        return ownedIdentity.keycloakServer?.pushTopics ?? Set<String>()
    }

    
    public func getCryptoIdentitiesOfManagedOwnedIdentitiesAssociatedWithThePushTopic(_ pushTopic: String, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity> {
        let ownedIdentities = try OwnedIdentity.getAll(delegateManager: delegateManager, within: obvContext)
        let appropriateOwnedIdentities = ownedIdentities
            .filter({ $0.isKeycloakManaged })
            .filter({ $0.keycloakServer?.pushTopics.contains(pushTopic) == true })
        return Set(appropriateOwnedIdentities.map { $0.cryptoIdentity })
    }
    
    // MARK: - API related to owned devices

    public func getDeviceUidsOfOwnedIdentity(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<UID> {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        let devices = ownedIdentity.otherDevices.union([ownedIdentity.currentDevice])
        return Set(devices.map { return $0.uid })
    }

    
    public func getOwnedIdentityOfCurrentDeviceUid(_ currentDeviceUid: UID, within obvContext: ObvContext) throws -> ObvCryptoIdentity {
        guard let currentDevice = try OwnedDevice.get(currentDeviceUid: currentDeviceUid, delegateManager: delegateManager, within: obvContext) else { throw NSError() }
        return currentDevice.identity.ownedCryptoIdentity.getObvCryptoIdentity()
    }

    
    public func getOwnedIdentityOfRemoteDeviceUid(_ remoteDeviceUid: UID, within obvContext: ObvContext) throws -> ObvCryptoIdentity? {
        let remoteDevice = try OwnedDevice.get(remoteDeviceUid: remoteDeviceUid, delegateManager: delegateManager, within: obvContext)
        return remoteDevice?.identity.ownedCryptoIdentity.getObvCryptoIdentity()
    }

    
    public func getCurrentDeviceUidOfOwnedIdentity(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> UID {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        return ownedIdentity.currentDevice.uid
    }

    
    public func getOtherDeviceUidsOfOwnedIdentity(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<UID> {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        return Set(ownedIdentity.otherDevices.map { return $0.uid })
    }

    
    public func addDeviceForOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, withUid uid: UID, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        try ownedIdentity.addRemoteDeviceWith(uid: uid)
    }

    
    public func isDevice(withUid deviceUid: UID, aRemoteDeviceOfOwnedIdentity identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        guard let ownedIdentityObj = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        let ownedRemoteDeviceUids = ownedIdentityObj.otherDevices.map { return $0.uid }
        return ownedRemoteDeviceUids.contains(deviceUid)
    }

    
    public func getAllRemoteOwnedDevicesUidsAndContactDeviceUids(within obvContext: ObvContext) throws -> Set<ObliviousChannelIdentifier> {
        let ownedRemoteDevices = try OwnedDevice.getAllOwnedRemoteDeviceUids(within: obvContext)
        let contactDevices = try ContactDevice.getAllContactDeviceUids(within: obvContext)
        return ownedRemoteDevices.union(contactDevices)
    }
    
    
    // MARK: - API related to contact identities

    public func addContactIdentity(_ contactIdentity: ObvCryptoIdentity, with identityCoreDetails: ObvIdentityCoreDetails, andTrustOrigin trustOrigin: TrustOrigin, forOwnedIdentity ownedIdentity: ObvCryptoIdentity, setIsOneToOneTo newOneToOneValue: Bool, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        guard ContactIdentity(cryptoIdentity: contactIdentity, identityCoreDetails: identityCoreDetails, trustOrigin: trustOrigin, ownedIdentity: ownedIdentity, isOneToOne: newOneToOneValue, delegateManager: delegateManager) != nil else {
            throw makeError(message: "Could not create ContactIdentity instance")
        }
    }

    public func addTrustOrigin(_ trustOrigin: TrustOrigin, toContactIdentity contactIdentity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, setIsOneToOneTo newOneToOneValue: Bool, within obvContext: ObvContext) throws {
        guard let contactObj = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { throw NSError() }
        try contactObj.addTrustOrigin(trustOrigin)
        contactObj.setIsOneToOne(to: newOneToOneValue)
    }
    
    public func getTrustOrigins(forContactIdentity contactIdentity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> [TrustOrigin] {
        guard let contactObj = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { throw NSError() }
        return contactObj.trustOrigins
    }
    
    public func getTrustLevel(forContactIdentity contactIdentity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> TrustLevel {
        guard let contactObj = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { throw NSError() }
        return contactObj.trustLevel
    }
    
    public func getContactsOfOwnedIdentity(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity> {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        return Set(ownedIdentity.contactIdentities.map { return $0.cryptoIdentity })
    }


    public func getIdentityDetailsOfContactIdentity(_ contactIdentity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> (publishedIdentityDetails: ObvIdentityDetails?, trustedIdentityDetails: ObvIdentityDetails) {
        guard let contactObj = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { throw makeError(message: "Could not find contact") }
        let publishedIdentityDetails = contactObj.publishedIdentityDetails?.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
        guard let trustedIdentityDetails = contactObj.trustedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory) else {
            throw Self.makeError(message: "Failed to get identity details of contact identity as we failed to get the trusted details")
        }
        return (publishedIdentityDetails, trustedIdentityDetails)
    }

    
    public func getPublishedIdentityDetailsOfContactIdentity(_ identity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> (contactIdentityDetailsElements: IdentityDetailsElements, photoURL: URL?)? {
        
        guard let contactIdentity = try ContactIdentity.get(contactIdentity: identity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { throw makeError(message: "Could not find contact") }
        guard let publishedIdentityDetails = contactIdentity.publishedIdentityDetails else { return nil }
        
        guard let publishedDetails = publishedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory) else {
            throw Self.makeError(message: "Failed to get the published details from the published identity details")
        }
        let publishedCoreDetails = publishedDetails.coreDetails
        let contactIdentityDetailsElements = IdentityDetailsElements(version: publishedIdentityDetails.version,
                                                                     coreDetails: publishedCoreDetails,
                                                                     photoServerKeyAndLabel: publishedIdentityDetails.photoServerKeyAndLabel)
        return (contactIdentityDetailsElements, publishedDetails.photoURL)
    }

    
    public func getTrustedIdentityDetailsOfContactIdentity(_ identity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> (contactIdentityDetailsElements: IdentityDetailsElements, photoURL: URL?) {
        
        guard let contactIdentity = try ContactIdentity.get(contactIdentity: identity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { throw makeError(message: "Could not find contact") }
        let trustedIdentityDetails = contactIdentity.trustedIdentityDetails
        
        guard let trustedDetails = trustedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory) else {
            throw Self.makeError(message: "Failed to get the trusted details from the trusted identity details")
        }
        let trustedCoreDetails = trustedDetails.coreDetails
        let contactIdentityDetailsElements = IdentityDetailsElements(version: trustedIdentityDetails.version,
                                                                     coreDetails: trustedCoreDetails,
                                                                     photoServerKeyAndLabel: trustedIdentityDetails.photoServerKeyAndLabel)
        return (contactIdentityDetailsElements, trustedDetails.photoURL)
    }

    
    public func updateTrustedIdentityDetailsOfContactIdentity(_ identity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, with newContactIdentityDetails: ObvIdentityDetails, within obvContext: ObvContext) throws {
        guard let contactIdentity = try ContactIdentity.get(contactIdentity: identity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { throw makeError(message: "Could not find contact") }
        try contactIdentity.updateTrustedDetailsWithPublishedDetails(newContactIdentityDetails, delegateManager: delegateManager)
    }


    public func updateDownloadedPhotoOfContactIdentity(_ identity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, version: Int, photo: Data, within obvContext: ObvContext) throws {
        guard let contactIdentity = try ContactIdentity.get(contactIdentity: identity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { throw makeError(message: "Could not find contact") }
        try contactIdentity.updateContactPhoto(withData: photo, version: version, delegateManager: delegateManager, within: obvContext)
    }


    public func updatePublishedIdentityDetailsOfContactIdentity(_ identity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, with newContactIdentityDetailsElements: IdentityDetailsElements, allowVersionDowngrade: Bool, within obvContext: ObvContext) throws {
        guard let contactIdentity = try ContactIdentity.get(contactIdentity: identity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { throw makeError(message: "Could not find contact") }
        try contactIdentity.updatePublishedDetailsAndTryToAutoTrustThem(with: newContactIdentityDetailsElements, allowVersionDowngrade: allowVersionDowngrade, delegateManager: delegateManager)
    }

    public func isIdentity(_ contactIdentity: ObvCryptoIdentity, aContactIdentityOfTheOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        return try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) != nil
    }

    
    public func deleteContactIdentity(_ contactIdentity: ObvCryptoIdentity, forOwnedIdentity ownedIdentity: ObvCryptoIdentity, failIfContactIsPartOfACommonGroup: Bool, within obvContext: ObvContext) throws {
        if let contactIdentityObject = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) {
            for device in contactIdentityObject.devices {
                device.delegateManager = delegateManager
                device.prepareForDeletion()
            }
            contactIdentityObject.publishedIdentityDetails?.delegateManager = delegateManager
            contactIdentityObject.trustedIdentityDetails.delegateManager = delegateManager
            try contactIdentityObject.publishedIdentityDetails?.delete(identityPhotosDirectory: delegateManager.identityPhotosDirectory, within: obvContext)
            try contactIdentityObject.trustedIdentityDetails.delete(identityPhotosDirectory: delegateManager.identityPhotosDirectory, within: obvContext)
            try contactIdentityObject.delete(delegateManager: delegateManager, failIfContactIsPartOfACommonGroup: failIfContactIsPartOfACommonGroup, within: obvContext)
        }
    }
    
    
    public func contactIdentityBelongsToSomeContactGroup(_ contactIdentity: ObvCryptoIdentity, forOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        guard let contactIdentityObject = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { throw makeError(message: "Could not find contact identity") }
        let contactGroupsJoined = try ContactGroup.getAllContactGroupWhereGroupMembersContainTheContact(contactIdentityObject, delegateManager: delegateManager)
        return !contactGroupsJoined.isEmpty
    }
    
    
    public func isContactRevokedAsCompromised(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        guard let contactIdentityObject = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { throw makeError(message: "Could not find contact identity") }
        return contactIdentityObject.isRevokedAsCompromised
    }

    
    public func isContactIdentityActive(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        guard let contactIdentityObject = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { throw makeError(message: "Could not find contact identity") }
        return contactIdentityObject.isActive
    }
    
    
    public func setContactForcefullyTrustedByUser(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, forcefullyTrustedByUser: Bool, within obvContext: ObvContext) throws {
        guard let contactIdentityObject = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { throw makeError(message: "Could not find contact identity") }
        contactIdentityObject.setForcefullyTrustedByUser(to: forcefullyTrustedByUser, delegateManager: delegateManager)
    }
    
    public func isOneToOneContact(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        guard let contactIdentityObject = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { return false }
        return contactIdentityObject.isOneToOne
    }
    
    public func resetOneToOneContactStatus(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, newIsOneToOneStatus: Bool, within obvContext: ObvContext) throws {
        guard let contactIdentityObject = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { throw makeError(message: "Could not find contact identity") }
        contactIdentityObject.setIsOneToOne(to: newIsOneToOneStatus)
    }
    
    // MARK: - API related to contact devices
    
    
    public func addDeviceForContactIdentity(_ contactIdentity: ObvCryptoIdentity, withUid uid: UID, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let contactIdentity = try ContactIdentity.get(contactIdentity: contactIdentity,
                                                        ownedIdentity: ownedIdentity,
                                                        delegateManager: delegateManager,
                                                        within: obvContext) else {
            throw ObvIdentityManagerImplementation.makeError(message: "Could not find contact identity")
        }
        try contactIdentity.addIfNotExistDeviceWith(uid: uid, flowId: obvContext.flowId)
    }
    
    
    public func removeDeviceForContactIdentity(_ contactIdentity: ObvCryptoIdentity, withUid uid: UID, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let contactIdentity = try ContactIdentity.get(contactIdentity: contactIdentity,
                                                        ownedIdentity: ownedIdentity,
                                                        delegateManager: delegateManager,
                                                        within: obvContext)
            else {
                throw ObvIdentityManagerImplementation.makeError(message: "Could not get contact identity")
        }
        try contactIdentity.removeIfExistsDeviceWith(uid: uid, flowId: obvContext.flowId)
    }
    
    
    public func getDeviceUidsOfContactIdentity(_ identity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<UID> {
        guard let contactIdentity = try ContactIdentity.get(contactIdentity: identity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerImplementation.makeError(message: "Could not find ContactIdentity object")
        }
        let deviceUids = contactIdentity.devices.map { $0.uid }
        return Set(deviceUids)
    }
    
    
    public func isDevice(withUid deviceUid: UID, aDeviceOfContactIdentity identity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        guard let contactIdentityObj = try ContactIdentity.get(contactIdentity: identity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { throw NSError() }
        let contactDeviceUids = contactIdentityObj.devices.map { return $0.uid }
        return contactDeviceUids.contains(deviceUid)
    }
    
    
    public func deleteDevicesOfContactIdentity(contactIdentity: ObvCryptoIdentity, contactDeviceUids: Set<UID>, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let contactIdentityObj = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerImplementation.makeError(message: "Could not get contact identity of owned identity")
        }
        let contactDevicesToDelete = contactIdentityObj.devices.filter { contactDeviceUids.contains($0.uid) }
        for device in contactDevicesToDelete {
            obvContext.delete(device)
        }
    }
    
    
    public func deleteAllDevicesOfContactIdentity(contactIdentity: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let contactIdentityObj = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerImplementation.makeError(message: "Could not get contact identity of owned identity")
        }
        for device in contactIdentityObj.devices {
            obvContext.delete(device)
        }
    }
    
    // MARK: - API related to contact groups
        
    /// This method returns the group information (and photo) corresponding to the published details of the joined group.
    /// If a photoURL is present in the `GroupInformationWithPhoto`, this method will copy this photo and create server label/key for it.
    public func createContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupInformationWithPhoto: GroupInformationWithPhoto, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, within obvContext: ObvContext) throws -> GroupInformationWithPhoto {
        
        guard groupInformationWithPhoto.groupOwnerIdentity == ownedIdentity else { throw makeError(message: "The group owner is not the owned identity") }
        
        let groupUid = groupInformationWithPhoto.groupUid
        
        // Since we are creating a group, we expect that the GroupInformationWithPhoto does not contain a server key/label
        assert(groupInformationWithPhoto.groupDetailsElementsWithPhoto.photoServerKeyAndLabel == nil)
        
        // If the GroupInformationWithPhoto contains a photo, we need to generate a server key/label for it.
        // We then update the GroupInformationWithPhoto in order for this server key/label to be stored in the created owned group
        let updatedGroupInformationWithPhoto: GroupInformationWithPhoto
        if groupInformationWithPhoto.photoURL == nil {
            updatedGroupInformationWithPhoto = groupInformationWithPhoto
        } else {
            let photoServerKeyAndLabel = PhotoServerKeyAndLabel.generate(with: prng)
            _ = GroupServerUserData.createForOwnedGroupDetails(ownedIdentity: ownedIdentity,
                                                               label: photoServerKeyAndLabel.label,
                                                               groupUid: groupUid,
                                                               within: obvContext)
            updatedGroupInformationWithPhoto = try groupInformationWithPhoto.withPhotoServerKeyAndLabel(photoServerKeyAndLabel)
        }
        
        let groupOwned = try ContactGroupOwned(groupInformationWithPhoto: updatedGroupInformationWithPhoto,
                                               ownedIdentity: ownedIdentity,
                                               pendingGroupMembers: pendingGroupMembers,
                                               delegateManager: delegateManager,
                                               within: obvContext)
        

        
        return try groupOwned.getPublishedOwnedGroupInformationWithPhoto(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
    }


    public func createContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation, groupOwner: ObvCryptoIdentity, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, within obvContext: ObvContext) throws {
        guard groupInformation.groupOwnerIdentity != ownedIdentity else { throw makeError(message: "The group owner is the owned identity") }
        _ = try ContactGroupJoined(groupInformation: groupInformation,
                                   ownedIdentity: ownedIdentity,
                                   groupOwnerCryptoIdentity: groupOwner,
                                   pendingGroupMembers: pendingGroupMembers,
                                   delegateManager: delegateManager,
                                   within: obvContext)
    }
    
    
    public func transferPendingMemberToGroupMembersOfContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, pendingMember: ObvCryptoIdentity, within obvContext: ObvContext, groupMembersChangedCallback: () throws -> Void) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        
        guard let group = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        
        guard try isIdentity(pendingMember, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotContact.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        
        guard try isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: pendingMember, within: obvContext) else {
            throw makeError(message: "Trying to transfer an inactive contact from pending to groups members of a group owned")
        }
        
        guard let contactIdentity = try ContactIdentity.get(contactIdentity: pendingMember, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotContact.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        
        try group.transferPendingMemberToGroupMembersForGroupOwned(contactIdentity: contactIdentity)
        
        try groupMembersChangedCallback()
    }
    
    
    public func transferGroupMemberToPendingMembersOfContactGroupOwnedAndMarkPendingMemberAsDeclined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupMember: ObvCryptoIdentity, within obvContext: ObvContext, groupMembersChangedCallback: () throws -> Void) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        
        guard let group = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        
        guard try isIdentity(groupMember, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotContact.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }

        try group.transferGroupMemberToPendingMembersForGroupOwned(contactCryptoIdentity: groupMember)
        
        try markPendingMemberAsDeclined(ownedIdentity: ownedIdentity, groupUid: groupUid, pendingMember: groupMember, within: obvContext)
        
        try groupMembersChangedCallback()
        
    }
    
    
    public func addPendingMembersToContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, newPendingMembers: Set<ObvCryptoIdentity>, within obvContext: ObvContext, groupMembersChangedCallback: () throws -> Void) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        
        guard let group = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }

        try group.add(newPendingMembers: newPendingMembers, delegateManager: delegateManager)
        
        try groupMembersChangedCallback()

    }
    
    
    public func removePendingAndMembersToContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, pendingOrMembersToRemove: Set<ObvCryptoIdentity>, within obvContext: ObvContext, groupMembersChangedCallback: () throws -> Void) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        
        guard let group = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }

        try group.remove(pendingOrGroupMembers: pendingOrMembersToRemove)
        
        try groupMembersChangedCallback()

    }
    
    
    public func markPendingMemberAsDeclined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, pendingMember: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }

        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }

        try groupOwned.markPendingMemberAsDeclined(pendingGroupMember: pendingMember)
        
    }
    
    
    public func unmarkDeclinedPendingMemberAsDeclined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, pendingMember: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        
        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: ObvIdentityManagerImplementation.errorDomain)
        }
        
        try groupOwned.unmarkDeclinedPendingMemberAsDeclined(pendingGroupMember: pendingMember)
        
    }


    public func updatePublishedDetailsOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation, within obvContext: ObvContext) throws {

        let errorDomain = ObvIdentityManagerImplementation.errorDomain
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }
        
        guard let groupJoined = try ContactGroupJoined.get(groupUid: groupInformation.groupUid,
                                                           groupOwnerCryptoIdentity: groupInformation.groupOwnerIdentity,
                                                           ownedIdentity: ownedIdentityObject,
                                                           delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: errorDomain)
        }

        try groupJoined.updateDetailsPublished(with: groupInformation.groupDetailsElements, delegateManager: delegateManager)
    }

    
    public func updateDownloadedPhotoOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupOwner: ObvCryptoIdentity, groupUid: UID, version: Int, photo: Data, within obvContext: ObvContext) throws {
        let errorDomain = ObvIdentityManagerImplementation.errorDomain
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }
        guard let groupJoined = try ContactGroupJoined.get(groupUid: groupUid, groupOwnerCryptoIdentity: groupOwner, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: errorDomain)
        }
        try groupJoined.updatePhoto(withData: photo, ofDetailsWithVersion: version, delegateManager: delegateManager, within: obvContext)
    }

    
    public func updateDownloadedPhotoOfContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, version: Int, photo: Data, within obvContext: ObvContext) throws {
        let errorDomain = ObvIdentityManagerImplementation.errorDomain
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }
        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: errorDomain)
        }
        try groupOwned.updatePhoto(withData: photo, ofDetailsWithVersion: version, delegateManager: delegateManager, within: obvContext)
    }
    
    
    public func trustPublishedDetailsOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        let errorDomain = ObvIdentityManagerImplementation.errorDomain
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }
        
        guard let groupJoined = try ContactGroupJoined.get(groupUid: groupUid, groupOwnerCryptoIdentity: groupOwner, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: errorDomain)
        }
        
        try groupJoined.trustDetailsPublished(within: obvContext, delegateManager: delegateManager)
        
    }

    
    public func updateLatestDetailsOfContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, with newGroupDetails: GroupDetailsElementsWithPhoto, within obvContext: ObvContext) throws {
        
        let errorDomain = ObvIdentityManagerImplementation.errorDomain
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }

        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: errorDomain)
        }

        try groupOwned.updateDetailsLatest(with: newGroupDetails, delegateManager: delegateManager)
    }
    

    public func setPhotoServerKeyAndLabelForContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws -> PhotoServerKeyAndLabel {

        let errorDomain = ObvIdentityManagerImplementation.errorDomain

        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }

        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: errorDomain)
        }
        
        guard let publishedPhotoURL = groupOwned.publishedDetails.getPhotoURL(identityPhotosDirectory: delegateManager.identityPhotosDirectory) else {
            throw makeError(message: "Cannot create Server key/label for the published details of an owned group if these details have no photoURL")
        }
        
        let photoServerKeyAndLabel = PhotoServerKeyAndLabel.generate(with: prng)
        groupOwned.publishedDetails.photoServerKeyAndLabel = photoServerKeyAndLabel
        
        if let latestPhotoURL = groupOwned.latestDetails.getPhotoURL(identityPhotosDirectory: delegateManager.identityPhotosDirectory) {
            if FileManager.default.contentsEqual(atPath: latestPhotoURL.path, andPath: publishedPhotoURL.path) {
                groupOwned.latestDetails.photoServerKeyAndLabel = photoServerKeyAndLabel
            }
        }
        
        _ = GroupServerUserData.createForOwnedGroupDetails(ownedIdentity: ownedIdentity,
                                                           label: photoServerKeyAndLabel.label,
                                                           groupUid: groupUid,
                                                           within: obvContext)
        
        return photoServerKeyAndLabel
    }

    
    public func discardLatestDetailsOfContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws {
        let errorDomain = ObvIdentityManagerImplementation.errorDomain
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }
        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: errorDomain)
        }
        try groupOwned.discardDetailsLatest(delegateManager: delegateManager)
    }
    
    
    public func publishLatestDetailsOfContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws {
        let errorDomain = ObvIdentityManagerImplementation.errorDomain
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }
        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: errorDomain)
        }
        try groupOwned.publishDetailsLatest(delegateManager: delegateManager)
    }

    
    public func updatePendingMembersAndGroupMembersOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, groupMembers: Set<CryptoIdentityWithCoreDetails>, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, groupMembersVersion: Int, within obvContext: ObvContext) throws {
        
        let errorDomain = ObvIdentityManagerImplementation.errorDomain
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }

        guard let groupJoined = try ContactGroupJoined.get(groupUid: groupUid, groupOwnerCryptoIdentity: groupOwner, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: errorDomain)
        }
        
        try groupJoined.updatePendingMembersAndGroupMembers(groupMembersWithCoreDetails: groupMembers,
                                                            pendingMembersWithCoreDetails: pendingGroupMembers,
                                                            groupMembersVersion: groupMembersVersion,
                                                            delegateManager: delegateManager,
                                                            flowId: obvContext.flowId)

    }
    
    
    public func getGroupOwnedStructure(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws -> GroupStructure? {
        let errorDomain = ObvIdentityManagerImplementation.errorDomain
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }
        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            return nil
        }
        return try groupOwned.getOwnedGroupStructure(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
    }

    
    public func getGroupJoinedStructure(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> GroupStructure? {
        let errorDomain = ObvIdentityManagerImplementation.errorDomain
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }
        guard let groupJoined = try ContactGroupJoined.get(groupUid: groupUid, groupOwnerCryptoIdentity: groupOwner, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            // When the group cannot be found, we return nil to indicate that this is the case.
            return nil
        }
        return try groupJoined.getJoinedGroupStructure(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
    }
    
    
    public func getAllGroupStructures(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<GroupStructure> {
        let errorDomain = ObvIdentityManagerImplementation.errorDomain
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }
        let groups = try ContactGroup.getAll(ownedIdentity: ownedIdentityObject, delegateManager: delegateManager)
        let groupStructures = Set(try groups.map({ try $0.getGroupStructure(identityPhotosDirectory: delegateManager.identityPhotosDirectory) }))
        return groupStructures
    }

    
    public func getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws -> GroupInformationWithPhoto {

        let errorDomain = ObvIdentityManagerImplementation.errorDomain
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }
        
        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: errorDomain)
        }

        let groupInformationWithPhoto = try groupOwned.getPublishedOwnedGroupInformationWithPhoto(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
        return groupInformationWithPhoto
    }

    
    public func getGroupJoinedInformationAndPublishedPhoto(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> GroupInformationWithPhoto {
        
        let errorDomain = ObvIdentityManagerImplementation.errorDomain
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }
        
        guard let groupJoined = try ContactGroupJoined.get(groupUid: groupUid, groupOwnerCryptoIdentity: groupOwner, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: errorDomain)
        }
        
        let groupInformationWithPhoto = try groupJoined.getPublishedJoinedGroupInformationWithPhoto(identityPhotosDirectory: delegateManager.identityPhotosDirectory)

        return groupInformationWithPhoto
        
    }

    public func leaveContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        let errorDomain = ObvIdentityManagerImplementation.errorDomain
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }
        
        guard let groupJoined = try ContactGroupJoined.get(groupUid: groupUid, groupOwnerCryptoIdentity: groupOwner, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: errorDomain)
        }

        try groupJoined.trustedDetails.delete(identityPhotosDirectory: delegateManager.identityPhotosDirectory, within: obvContext)
        try groupJoined.publishedDetails.delete(identityPhotosDirectory: delegateManager.identityPhotosDirectory, within: obvContext)
        obvContext.delete(groupJoined)
        
    }
    
    
    public func deleteContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws {
        
        let errorDomain = ObvIdentityManagerImplementation.errorDomain
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }
        
        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: errorDomain)
        }

        guard groupOwned.groupMembers.isEmpty && groupOwned.pendingGroupMembers.isEmpty else {
            throw ObvIdentityManagerError.ownedContactGroupStillHasMembersOrPendingMembers.error(withDomain: errorDomain)
        }
        
        try groupOwned.latestDetails.delete(identityPhotosDirectory: delegateManager.identityPhotosDirectory, within: obvContext)
        try groupOwned.publishedDetails.delete(identityPhotosDirectory: delegateManager.identityPhotosDirectory, within: obvContext)
        obvContext.delete(groupOwned)
        
    }

    
    /// This method is exclusively called from the ProcessInvitationStep of the GroupInvitationProtocol.
    public func forceUpdateOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, authoritativeGroupInformation: GroupInformation, within obvContext: ObvContext) throws {
        
        let errorDomain = ObvIdentityManagerImplementation.errorDomain
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }

        guard let groupJoined = try ContactGroupJoined.get(groupUid: authoritativeGroupInformation.groupUid,
                                                           groupOwnerCryptoIdentity: authoritativeGroupInformation.groupOwnerIdentity,
                                                           ownedIdentity: ownedIdentityObject,
                                                           delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: errorDomain)
        }

        try groupJoined.resetGroupDetailsWithAuthoritativeDetailsIfRequired(
            authoritativeGroupInformation.groupDetailsElements,
            delegateManager: delegateManager,
            within: obvContext)
        
    }
    
    
    public func resetGroupMembersVersionOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        let errorDomain = ObvIdentityManagerImplementation.errorDomain
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned.error(withDomain: errorDomain)
        }
        
        guard let groupJoined = try ContactGroupJoined.get(groupUid: groupUid, groupOwnerCryptoIdentity: groupOwner, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist.error(withDomain: errorDomain)
        }

        try groupJoined.resetGroupMembersVersionOfContactGroupJoined()
        
    }

    // MARK: - User Data

    public func getAllServerDataToSynchronizeWithServer(within obvContext: ObvContext) throws -> (toDelete: Set<UserData>, toRefresh: Set<UserData>) {
        let ownedIdentities = try OwnedIdentity.getAll(delegateManager: delegateManager, within: obvContext)
        
        let now = Date()
        var toDelete = Set<UserData>()
        var toRefresh = Set<UserData>()

        for ownedIdentity in ownedIdentities {
            let labelsToKeep = try getLabelsOfServerUserDataToKeepOnServer(ownedIdentity: ownedIdentity)
            let serverUserDatas = try IdentityServerUserData.getAllServerUserDatas(for: ownedIdentity.cryptoIdentity, within: obvContext)
            let toKeepForOwnedIdentity = Set(serverUserDatas.filter({
                guard let label = $0.label else { assertionFailure(); return false }
                return labelsToKeep.contains(label)
            }))
            let toDeleteForOwnedIdentity = serverUserDatas.subtracting(toKeepForOwnedIdentity).compactMap({ $0.toUserData() })
            let toRefreshForOwnedIdentity = toKeepForOwnedIdentity.filter({ $0.nextRefreshTimestamp < now }).compactMap({ $0.toUserData() })
            toDelete.formUnion(toDeleteForOwnedIdentity)
            toRefresh.formUnion(toRefreshForOwnedIdentity)
        }
        
        return (toDelete: toDelete, toRefresh: toRefresh)
    }
    
    
    /// This method returns all the labels that should correspond to an uploaded server user data on the server for the given owned identity
    ///
    /// It comprises:
    /// - The labels corresponding to owned identity profile pictures
    /// - The labels corresponding to owned groups published profile pictures
    private func getLabelsOfServerUserDataToKeepOnServer(ownedIdentity: OwnedIdentity) throws -> Set<UID> {
        let ownedIdentityPhotoServerLabels = try OwnedIdentityDetailsPublished.getAllPhotoServerLabels(ownedIdentity: ownedIdentity)
        let ownedGroupPhotoServerLabels = try ContactGroupOwned.getAllContactGroupOwned(ownedIdentity: ownedIdentity, delegateManager: delegateManager)
            .map({ $0.publishedDetails })
            .compactMap({ $0.photoServerKeyAndLabel })
            .map({ $0.label })
        let labelsToKeep = ownedIdentityPhotoServerLabels.union(Set(ownedGroupPhotoServerLabels))
        return labelsToKeep
    }
    
    
    public func getServerUserData(for ownedIdentity: ObvCryptoIdentity, with label: UID, within obvContext: ObvContext) -> UserData? {
        let serverUserData = try? ServerUserData.getServerUserData(for: ownedIdentity, with: label, within: obvContext)
        return serverUserData?.toUserData()
    }

    public func deleteUserData(for ownedIdentity: ObvCryptoIdentity, with label: UID, within obvContext: ObvContext) {
        guard let userData = try? ServerUserData.getServerUserData(for: ownedIdentity, with: label, within: obvContext) else { return }
        obvContext.delete(userData)
    }

    public func updateUserDataNextRefreshTimestamp(for ownedIdentity: ObvCryptoIdentity, with label: UID, within obvContext: ObvContext) {
        let userData = try? ServerUserData.getServerUserData(for: ownedIdentity, with: label, within: obvContext)
        userData?.updateNextRefreshTimestamp()
    }

}


// MARK: - Implementing ObvKeyWrapperForIdentityDelegate


extension ObvIdentityManagerImplementation: ObvKeyWrapperForIdentityDelegate {
    
    public func wrap(_ key: AuthenticatedEncryptionKey, for identity: ObvCryptoIdentity, randomizedWith prng: PRNGService) -> EncryptedData {
        return PublicKeyEncryption.encrypt(key.obvEncode().rawData, for: identity, randomizedWith: prng)
    }
    
    public func unwrap(_ encryptedKey: EncryptedData, for identity: ObvCryptoIdentity, within obvContext: ObvContext) -> AuthenticatedEncryptionKey? {
        
        let ownedCryptoIdentity: ObvOwnedCryptoIdentity
        
        if let ownedIdentity = try? OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) {
            ownedCryptoIdentity = ownedIdentity.ownedCryptoIdentity
        } else {
            os_log("Could not find a matching Owned Identity", log: log, type: .error)
            return nil
        }
        
        guard let rawEncodedKey = PublicKeyEncryption.decrypt(encryptedKey, for: ownedCryptoIdentity) else {
            os_log("Could not decrypt the encrypted key", log: log, type: .error)
            return nil
        }
        guard let encodedKey = ObvEncoded(withRawData: rawEncodedKey) else {
            os_log("Could not parse the decrypted key", log: log, type: .error)
            return nil
        }
        guard let key = try? AuthenticatedEncryptionKeyDecoder.decode(encodedKey) else {
            os_log("Could not decode the decrypted key", log: log, type: .error)
            return nil
        }
        return key
    }
}



// MARK: - ObvSolveChallengeDelegate

extension ObvIdentityManagerImplementation: ObvSolveChallengeDelegate {
    
    public func solveChallenge(_ challengeType: ChallengeType, for identity: ObvCryptoIdentity, using png: PRNGService, within obvContext: ObvContext) throws -> Data {
        
        // Fetch the crypto owned identity from the database
        let ownedCryptoIdentity: ObvOwnedCryptoIdentity
        if let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) {
            ownedCryptoIdentity = ownedIdentity.ownedCryptoIdentity
        } else {
            os_log("Could not find an appropriate owned identity", log: log, type: .fault)
            throw makeError(message: "Could not find an appropriate owned identity")
        }
        
        guard let response = ObvSolveChallengeStruct.solveChallenge(challengeType,
                                                                    with: ownedCryptoIdentity.privateKeyForAuthentication,
                                                                    and: ownedCryptoIdentity.publicKeyForAuthentication,
                                                                    using: prng)
        else {
            os_log("Could not compute the challenge's response", log: log, type: .error)
            throw makeError(message: "Could not compute the challenge's response")
        }
        return response

    }
    

    public func getApiKeyForOwnedIdentity(_ identity: ObvCryptoIdentity) throws -> UUID {
        var apiKey: UUID!
        var getError: Error? = nil
        let randomFlowId = FlowIdentifier()
        delegateManager.contextCreator.performBackgroundTaskAndWait(flowId: randomFlowId) { (obvContext) in
            do {
                apiKey = try OwnedIdentity.getApiKey(identity, within: obvContext)
            } catch {
                getError = error
            }
        }
        guard getError == nil else {
            throw getError!
        }
        return apiKey
    }
    
}


// MARK: - API related to contact capabilities

extension ObvIdentityManagerImplementation {
    
    public func getCapabilitiesOfContactIdentity(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvCapability>? {
        guard let contactIdentity = try ContactIdentity.get(contactIdentity: contactIdentity,
                                                        ownedIdentity: ownedIdentity,
                                                        delegateManager: delegateManager,
                                                        within: obvContext) else {
            throw ObvIdentityManagerImplementation.makeError(message: "Could not find contact identity")
        }
        return contactIdentity.allCapabilities
    }
    
    
    public func getCapabilitiesOfContactDevice(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, within obvContext: ObvContext) throws -> Set<ObvCapability>? {
        guard let contactIdentity = try ContactIdentity.get(contactIdentity: contactIdentity,
                                                        ownedIdentity: ownedIdentity,
                                                        delegateManager: delegateManager,
                                                        within: obvContext) else {
            throw ObvIdentityManagerImplementation.makeError(message: "Could not find contact identity")
        }
        guard let contactDevice = contactIdentity.devices.first(where: { $0.uid == contactDeviceUid }) else {
            throw ObvIdentityManagerImplementation.makeError(message: "Could not find contact device")
        }
        return contactDevice.allCapabilities
    }
    
    
    public func getCapabilitiesOfAllContactsOfOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> [ObvCryptoIdentity: Set<ObvCapability>] {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find owned identity")
        }
        var result = [ObvCryptoIdentity: Set<ObvCapability>]()
        ownedIdentity.contactIdentities.forEach { contact in
            result[contact.cryptoIdentity] = contact.allCapabilities
        }
        return result
    }

    
    public func setRawCapabilitiesOfContactDevice(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, uid: UID, newRawCapabilities: Set<String>, within obvContext: ObvContext) throws {
        guard let contactIdentity = try ContactIdentity.get(contactIdentity: contactIdentity,
                                                        ownedIdentity: ownedIdentity,
                                                        delegateManager: delegateManager,
                                                        within: obvContext) else {
            throw ObvIdentityManagerImplementation.makeError(message: "Could not find contact identity")
        }
        try contactIdentity.setRawCapabilitiesOfDeviceWithUID(uid, newRawCapabilities: newRawCapabilities)
    }

}


// MARK: - API related to own capabilities

extension ObvIdentityManagerImplementation {
    
    public func getCapabilitiesOfOwnedIdentity(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvCapability>? {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity,
                                                        delegateManager: delegateManager,
                                                        within: obvContext) else {
            throw ObvIdentityManagerImplementation.makeError(message: "Could not find owned identity")
        }
        return ownedIdentity.allCapabilities
    }
    
    
    public func getCapabilitiesOfCurrentDeviceOfOwnedIdentity(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvCapability>? {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity,
                                                        delegateManager: delegateManager,
                                                        within: obvContext) else {
            throw ObvIdentityManagerImplementation.makeError(message: "Could not find owned identity")
        }
        return ownedIdentity.currentDevice.allCapabilities
    }
    
    
    public func getCapabilitiesOfOtherOwnedDevice(ownedIdentity: ObvCryptoIdentity, deviceUID: UID, within obvContext: ObvContext) throws -> Set<ObvCapability>? {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity,
                                                        delegateManager: delegateManager,
                                                        within: obvContext) else {
            throw ObvIdentityManagerImplementation.makeError(message: "Could not find owned identity")
        }
        guard let device = ownedIdentity.otherDevices.first(where: { $0.uid == deviceUID }) else {
            throw ObvIdentityManagerImplementation.makeError(message: "Could not find other owned device")
        }
        return device.allCapabilities
    }

    
    public func getCapabilitiesOfOwnedIdentities(within obvContext: ObvContext) throws -> [ObvCryptoIdentity: Set<ObvCapability>] {
        let ownedIdentities = try OwnedIdentity.getAll(delegateManager: delegateManager,
                                                       within: obvContext)
        var result = [ObvCryptoIdentity: Set<ObvCapability>]()
        ownedIdentities.forEach { ownedIdentity in
            result[ownedIdentity.cryptoIdentity] = ownedIdentity.allCapabilities
        }
        return result
    }

    
    public func setCapabilitiesOfCurrentDeviceOfOwnedIdentity(ownedIdentity: ObvCryptoIdentity, newCapabilities: Set<ObvCapability>, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity,
                                                        delegateManager: delegateManager,
                                                        within: obvContext) else {
            throw ObvIdentityManagerImplementation.makeError(message: "Could not find owned identity")
        }
        try ownedIdentity.setCapabilitiesOfCurrentDevice(newCapabilities: newCapabilities)
    }

    
    public func setRawCapabilitiesOfOtherDeviceOfOwnedIdentity(ownedIdentity: ObvCryptoIdentity, deviceUID: UID, newRawCapabilities: Set<String>, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity,
                                                        delegateManager: delegateManager,
                                                        within: obvContext) else {
            throw ObvIdentityManagerImplementation.makeError(message: "Could not find owned identity")
        }
        try ownedIdentity.setRawCapabilitiesOfOtherDeviceWithUID(deviceUID, newRawCapabilities: newRawCapabilities)
    }

}


// MARK: - Implementing ObvManager


extension ObvIdentityManagerImplementation {
    
    public var requiredDelegates: [ObvEngineDelegateType] {
        return [ObvEngineDelegateType.ObvCreateContextDelegate,
                ObvEngineDelegateType.ObvNotificationDelegate,
                ObvEngineDelegateType.ObvNetworkFetchDelegate]
    }
        
    public func fulfill(requiredDelegate delegate: AnyObject, forDelegateType delegateType: ObvEngineDelegateType) throws {
        switch delegateType {
        case .ObvCreateContextDelegate:
            guard let delegate = delegate as? ObvCreateContextDelegate else { throw NSError() }
            delegateManager.contextCreator = delegate
        case .ObvNotificationDelegate:
            guard let delegate = delegate as? ObvNotificationDelegate else { throw NSError() }
            delegateManager.notificationDelegate = delegate
        case .ObvNetworkFetchDelegate:
            guard let delegate = delegate as? ObvNetworkFetchDelegate else { throw NSError() }
            delegateManager.networkFetchDelegate = delegate
        default:
            throw NSError()
        }
    }
        
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {}

}


// MARK: - Bootstrap

extension ObvIdentityManagerImplementation {
    
    private func deleteUnusedIdentityPhotos(flowId: FlowIdentifier) {
        guard let contextCreator = delegateManager.contextCreator else { assertionFailure(); return }
        
        contextCreator.performBackgroundTask(flowId: flowId) { [weak self] (obvContext) in
            
            guard let _self = self else { return }
            
            let photoURLsInDatabase: Set<URL>
            do {
                photoURLsInDatabase = try _self.getAllUsedPhotoURL(within: obvContext)
            } catch let error {
                os_log("Unable to compute the Set of all used photoURL: %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            
            let photoURLsOnDisk: Set<URL>
            do {
                photoURLsOnDisk = try _self.getAllPhotoURLOnDisk()
            } catch let error {
                os_log("Unable to compute the photo on disk: %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            
            let photoURLsToDeleteFromDisk = photoURLsOnDisk.subtracting(photoURLsInDatabase)
            let photoURLsMissingFromDisk = photoURLsInDatabase.subtracting(photoURLsOnDisk)

            for photoURL in photoURLsToDeleteFromDisk {
                do {
                    try FileManager.default.removeItem(at: photoURL)
                } catch {
                    os_log("Cannot delete unused photo: %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
            }
            
            if !photoURLsMissingFromDisk.isEmpty {
                os_log("There are %d photo URLs referenced in database that cannot be found on disk", log: _self.log, type: .fault, photoURLsMissingFromDisk.count)
                assertionFailure()
            }
            
        }
        
    }
    
    
    private func getAllUsedPhotoURL(within obvContext: ObvContext) throws -> Set<URL> {
        let photoURLsOfContacts = Set((try ContactIdentityDetails.getAllPhotoFilenames(within: obvContext)).map({ self.identityPhotosDirectory.appendingPathComponent($0) }))
        let photoURLsOfOwned = try OwnedIdentityDetailsPublished.getAllPhotoURLs(identityPhotosDirectory: delegateManager.identityPhotosDirectory, with: obvContext)
        let photoURLsOfGroupsV1 = try ContactGroupDetails.getAllPhotoURLs(identityPhotosDirectory: delegateManager.identityPhotosDirectory, within: obvContext)
        let photoURLsOfGroupsV2 = try ContactGroupV2Details.getAllPhotoURLs(identityPhotosDirectory: delegateManager.identityPhotosDirectory, within: obvContext)
        return photoURLsOfContacts
            .union(photoURLsOfOwned)
            .union(photoURLsOfGroupsV1)
            .union(photoURLsOfGroupsV2)
    }
    
    
    private func getAllPhotoURLOnDisk() throws  -> Set<URL> {
        Set(try FileManager.default.contentsOfDirectory(at: self.identityPhotosDirectory, includingPropertiesForKeys: nil))
    }
    
    
    private func pruneOldKeycloakRevokedIdentityAndUncertifyExpiredSignedContactDetails(flowId: FlowIdentifier) {
        
        guard let contextCreator = delegateManager.contextCreator else { assertionFailure(); return }
        let log = self.log

        contextCreator.performBackgroundTask(flowId: flowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            do {
                let ownedIdentities = try OwnedIdentity.getAll(delegateManager: _self.delegateManager, within: obvContext)
                let managedOwnedIdentities = ownedIdentities.filter({ $0.isKeycloakManaged })
                managedOwnedIdentities.forEach { ownedIdentity in
                    ownedIdentity.pruneOldKeycloakRevokedContacts(delegateManager: _self.delegateManager)
                    ownedIdentity.uncertifyExpiredSignedContactDetails(delegateManager: _self.delegateManager)
                }
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Core Data error during the bootstrap of the identity manager: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                // In production, continue
            }
            
        }
        
    }

    
    private func deleteOrphanedContactGroupV2Details(flowId: FlowIdentifier) {
        
        guard let contextCreator = delegateManager.contextCreator else { assertionFailure(); return }
        let log = self.log

        contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
            do {
                try ContactGroupV2Details.deleteOrphaned(within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Core Data error during the bootstrap of the identity manager. Could not delete orphaned ContactGroupV2Details: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                // In production, continue anyway
            }
            
        }

    }
    
}

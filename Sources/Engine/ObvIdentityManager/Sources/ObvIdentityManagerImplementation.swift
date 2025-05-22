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
import CoreData
import os.log
import OlvidUtils
import ObvCrypto
import ObvMetaManager
import ObvEncoder
import ObvTypes
import ObvJWS


public protocol ObvIdentityManagerImplementationDelegate: AnyObject {
    func previousBackedUpProfileSnapShotIsObsolete(_ identityManagerImplementation: ObvIdentityManagerImplementation, ownedCryptoId: ObvTypes.ObvCryptoId) async
    func previousBackedUpDeviceSnapShotIsObsolete(_ identityManagerImplementation: ObvIdentityManagerImplementation) async
    func anOwnedIdentityWasDeleted(_ identityManagerImplementation: ObvIdentityManagerImplementation, deletedOwnedCryptoId: ObvCryptoIdentity) async
}


public final class ObvIdentityManagerImplementation {
    
    // MARK: Instance variables
    
    public var logSubsystem: String { return delegateManager.logSubsystem }
    
    public func prependLogSubsystem(with prefix: String) {
        delegateManager.prependLogSubsystem(with: prefix)
    }
    
    lazy private var log = OSLog(subsystem: logSubsystem, category: "ObvIdentityManagerImplementation")
    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {
        assert(self.delegate != nil, "The delegate must be set soon after initialization")
        guard forTheFirstTime else { return }
        createMissingGroupV2ServerUserData(flowId: flowId)
        deleteUnusedIdentityPhotos(flowId: flowId)
        pruneOldKeycloakRevokedIdentityAndUncertifyExpiredSignedContactDetails(flowId: flowId)
        deleteOrphanedContactGroupV2Details(flowId: flowId)
        await OwnedIdentity.addObvObserver(self)
        await KeycloakServer.addObvObserver(self)
        await OwnedIdentityDetailsPublished.addObvObserver(self)
        await ContactIdentity.addObvObserver(self)
        await ContactGroup.addObvObserver(self)
        await ContactGroupV2.addObvObserver(self)
        await ContactIdentityDetails.addObvObserver(self)
        await ContactGroupV2Member.addObvObserver(self)
        await ContactGroupV2PendingMember.addObvObserver(self)
        await ContactGroupV2Details.addObvObserver(self)
    }

    let prng: PRNGService
    let identityPhotosDirectory: URL

    private static let errorDomain = String(describing: ObvIdentityManagerImplementation.self)
    
    private weak var delegate: ObvIdentityManagerImplementationDelegate?
    
    public func setDelegate(to newDelegate: ObvIdentityManagerImplementationDelegate) {
        self.delegate = newDelegate
    }
    
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


// MARK: - Implementing Database observers

extension ObvIdentityManagerImplementation: ContactGroupV2DetailsObserver {
    
    /// Called by the database whenever the changes made to the details of a group v2 imply that the previous profile backup is obsolete
    func previousBackedUpProfileSnapShotIsObsoleteAsContactGroupV2DetailsChanged(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        guard let delegate else { assertionFailure(); return }
        debugPrint("😌 previousBackedUpProfileSnapShotIsObsoleteAsContactGroupV2DetailsChanged")
        await delegate.previousBackedUpProfileSnapShotIsObsolete(self, ownedCryptoId: ownedCryptoId)
    }

}


extension ObvIdentityManagerImplementation: ContactGroupV2PendingMemberObserver {
    
    /// Called by the database whenever the changes made to a group pending member imply that the previous profile backup is obsolete
    func previousBackedUpProfileSnapShotIsObsoleteAsContactGroupV2PendingMemberChanged(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        guard let delegate else { assertionFailure(); return }
        debugPrint("😌 previousBackedUpProfileSnapShotIsObsoleteAsContactGroupV2PendingMemberChanged")
        await delegate.previousBackedUpProfileSnapShotIsObsolete(self, ownedCryptoId: ownedCryptoId)
    }
    
}

extension ObvIdentityManagerImplementation: ContactGroupV2MemberObserver {
    
    /// Called by the database whenever the changes made to a group member imply that the previous profile backup is obsolete
    func previousBackedUpProfileSnapShotIsObsoleteAsContactGroupV2MemberChanged(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        guard let delegate else { assertionFailure(); return }
        debugPrint("😌 previousBackedUpProfileSnapShotIsObsoleteAsContactGroupV2MemberChanged")
        await delegate.previousBackedUpProfileSnapShotIsObsolete(self, ownedCryptoId: ownedCryptoId)
    }
    
}


extension ObvIdentityManagerImplementation: ContactIdentityDetailsObserver {
    
    /// Called by the database whenever the changes made to the published or trust details of a contact imply that the previous profile backup is obsolete
    func previousBackedUpProfileSnapShotIsObsoleteAsContactIdentityDetailsChanged(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        guard let delegate else { assertionFailure(); return }
        debugPrint("😌 previousBackedUpProfileSnapShotIsObsoleteAsContactIdentityDetailsChanged")
        await delegate.previousBackedUpProfileSnapShotIsObsolete(self, ownedCryptoId: ownedCryptoId)
    }
    
}


extension ObvIdentityManagerImplementation: ContactGroupV2Observer {
    
    /// Called by the database whenever the changes made to a group V2 imply that the previous profile backup is obsolete
    func previousBackedUpProfileSnapShotIsObsoleteAsContactGroupV2Changed(ownedCryptoId: ObvCryptoId) async {
        guard let delegate else { assertionFailure(); return }
        debugPrint("😌 previousBackedUpProfileSnapShotIsObsoleteAsContactGroupV2Changed")
        await delegate.previousBackedUpProfileSnapShotIsObsolete(self, ownedCryptoId: ownedCryptoId)
    }
    
}


extension ObvIdentityManagerImplementation: ContactGroupObserver {
    
    /// Called by the database whenever the changes made to a group V1 imply that the previous profile backup is obsolete
    func previousBackedUpProfileSnapShotIsObsoleteAsContactGroupChanged(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        guard let delegate else { assertionFailure(); return }
        debugPrint("😌 previousBackedUpProfileSnapShotIsObsoleteAsContactGroupChanged")
        await delegate.previousBackedUpProfileSnapShotIsObsolete(self, ownedCryptoId: ownedCryptoId)
    }
    
}


extension ObvIdentityManagerImplementation: ContactIdentityObserver {
    
    /// Called by the database whenever the changes made to a contact imply that the previous profile backup is obsolete
    func previousBackedUpProfileSnapShotIsObsoleteAsContactIdentityChanged(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        guard let delegate else { assertionFailure(); return }
        debugPrint("😌 previousBackedUpProfileSnapShotIsObsoleteAsContactIdentityChanged")
        await delegate.previousBackedUpProfileSnapShotIsObsolete(self, ownedCryptoId: ownedCryptoId)
    }
    
}


extension ObvIdentityManagerImplementation: OwnedIdentityObserver {
        
    /// Called by the database whenever the changes made to an owned identity imply that the previous device backup is obsolete
    func previousBackedUpDeviceSnapShotIsObsoleteAsOwnedIdentityChanged() async {
        guard let delegate else { assertionFailure(); return }
        await delegate.previousBackedUpDeviceSnapShotIsObsolete(self)
    }

    
    /// Called by the database whenever the changes made to an owned identity imply that the previous profile backup is obsolete.
    /// This is also called when an owned identity is created.
    func previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityChangedOrWasInserted(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        guard let delegate else { assertionFailure(); return }
        debugPrint("😌 previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityChanged")
        await delegate.previousBackedUpProfileSnapShotIsObsolete(self, ownedCryptoId: ownedCryptoId)
    }
    
    
    func anOwnedIdentityWasDeleted(deletedOwnedCryptoId: ObvCryptoIdentity) async {
        guard let delegate else { assertionFailure(); return }
        await delegate.anOwnedIdentityWasDeleted(self, deletedOwnedCryptoId: deletedOwnedCryptoId)
    }

}


extension ObvIdentityManagerImplementation: KeycloakServerObserver {
    
    /// Called by the database whenever the changes made to a keycloak server  imply that the previous device backup is obsolete
    func previousBackedUpDeviceSnapShotIsObsoleteAsKeycloakServerChanged() async {
        guard let delegate else { assertionFailure(); return }
        await delegate.previousBackedUpDeviceSnapShotIsObsolete(self)
    }
    
    /// Called by the database whenever the changes made to a keycloak server imply that the previous profile backup is obsolete
    func previousBackedUpProfileSnapShotIsObsoleteAsKeycloakServerChanged(ownedCryptoId: ObvCryptoId) async {
        guard let delegate else { assertionFailure(); return }
        debugPrint("😌 previousBackedUpProfileSnapShotIsObsoleteAsKeycloakServerChanged")
        await delegate.previousBackedUpProfileSnapShotIsObsolete(self, ownedCryptoId: ownedCryptoId)
    }
    
}


extension ObvIdentityManagerImplementation: OwnedIdentityDetailsPublishedObServer {
    
    /// Called by the database whenever the changes made to the published details of an owned identity imply that the previous device backup is obsolete
    func previousBackedUpDeviceSnapShotIsObsoleteAsOwnedIdentityDetailsPublishedChanged() async {
        guard let delegate else { assertionFailure(); return }
        await delegate.previousBackedUpDeviceSnapShotIsObsolete(self)
    }
    

    /// Called by the database whenever the changes made to the published details of an owned identity imply that the previous profile backup is obsolete
    func previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityDetailsPublishedChanged(ownedCryptoId: ObvCryptoId) async {
        guard let delegate else { assertionFailure(); return }
        debugPrint("😌 previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityDetailsPublishedChanged")
        await delegate.previousBackedUpProfileSnapShotIsObsolete(self, ownedCryptoId: ownedCryptoId)
    }
    
}


// MARK: - Implementing ObvIdentityManagerSnapshotable

extension ObvIdentityManagerImplementation: ObvIdentityManagerSnapshotable {
    
    public func ownedIdentityExistsOnThisDevice(ownedCryptoId: ObvCryptoId, flowId: FlowIdentifier) async throws -> Bool {
        return try await self.isOwned(ownedCryptoId.cryptoIdentity, flowId: flowId)
    }
    
    
    /// We parse a profile snapshot by simulating a restore, without saving the context. This might be inefficient, but it's certainly ok for now.
    public func parseProfileSnapshotNode(identityNode: any ObvSyncSnapshotNode, flowId: FlowIdentifier) async throws -> ObvProfileBackupFromServer.DataObtainedByParsingIdentityNode {
        let parsedData: ObvProfileBackupFromServer.DataObtainedByParsingIdentityNode = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ObvProfileBackupFromServer.DataObtainedByParsingIdentityNode, any Error>) in
            delegateManager.contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    try self.restoreObvSyncSnapshotNode(identityNode, customDeviceName: "", allowOwnedIdentityToExistInDatabase: true, within: obvContext)
                    let insertedObjects = obvContext.context.insertedObjects
                    let numberOfGroups = insertedObjects.filter({ $0 is ContactGroup || $0 is ContactGroupV2 }).count
                    let numberOfContacts = insertedObjects.filter({ $0 is ContactIdentity }).count
                    let isKeycloakManaged: ObvProfileBackupFromServer.DataObtainedByParsingIdentityNode.IsKeycloakManaged
                    if let keycloakServer = insertedObjects.compactMap({ $0 as? KeycloakServer }).first, let keycloakConfiguration = try? keycloakServer.toObvKeycloakState.keycloakConfiguration {
                        isKeycloakManaged = .yes(keycloakConfiguration: keycloakConfiguration, isTransferRestricted: keycloakServer.isTransferRestricted)
                    } else {
                        isKeycloakManaged = .no
                    }
                    let encodedPhotoServerKeyAndLabel: Data?
                    let ownedCryptoIdentity: ObvOwnedCryptoIdentity
                    let coreDetails: ObvIdentityCoreDetails
                    if insertedObjects.count(where: { $0 is OwnedIdentity }) == 1, let ownedIdentity = insertedObjects.compactMap({ $0 as? OwnedIdentity }).first {
                        encodedPhotoServerKeyAndLabel = try? ownedIdentity.publishedIdentityDetails.photoServerKeyAndLabel?.jsonEncode()
                        ownedCryptoIdentity = ownedIdentity.ownedCryptoIdentity
                        coreDetails = try ownedIdentity.publishedIdentityDetails.coreDetails
                    } else {
                        assertionFailure()
                        throw ObvIdentityManagerError.unexpectedOwnedIdentity
                    }
                    let parsedData = ObvProfileBackupFromServer.DataObtainedByParsingIdentityNode(
                        numberOfGroups: numberOfGroups,
                        numberOfContacts: numberOfContacts,
                        isKeycloakManaged: isKeycloakManaged,
                        encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel,
                        ownedCryptoIdentity: ownedCryptoIdentity,
                        coreDetails: coreDetails)
                    return continuation.resume(returning: parsedData)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
        
        return parsedData
        
    }
    
    
    /// Called when parsing a device backup downloaded from the server
    public func parseDeviceSnapshotNode(identityNode: any ObvTypes.ObvSyncSnapshotNode, version: Int, flowId: OlvidUtils.FlowIdentifier) throws -> ObvTypes.ObvDeviceBackupFromServer {
        
        guard let deviceSnapshotNode = identityNode as? ObvIdentityManagerDeviceSnapshotNode else {
            assertionFailure()
            throw ObvIdentityManagerError.unexpectedSyncSnapshotNode
        }

        let deviceBackupFromServer = try deviceSnapshotNode.toObvDeviceBackupFromServer(version: version)
        
        return deviceBackupFromServer
        
    }
    
    
    public func getSyncSnapshotNode(for context: ObvSyncSnapshot.Context) throws -> any ObvSyncSnapshotNode {
        let flowId = FlowIdentifier()
        return try delegateManager.contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { obvContext in
            return try getSyncSnapshotNode(context: context, within: obvContext)
        }
    }
    
    
    private func getSyncSnapshotNode(context: ObvSyncSnapshot.Context, within obvContext: ObvContext) throws -> any ObvSyncSnapshotNode {
        switch context {
        case .transfer(let ownedCryptoId):
            // We return the exact same snapshot node than in the "backupProfile" case
            let ownedCryptoIdentity = ownedCryptoId.cryptoIdentity
            return try ObvIdentityManagerSyncSnapshotNode(ownedCryptoIdentity: ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext)
        case .backupDevice:
            return try ObvIdentityManagerDeviceSnapshotNode(delegateManager: delegateManager, within: obvContext)
        case .backupProfile(let ownedCryptoId):
            // We return the exact same snapshot node than in the "transfer" case
            let ownedCryptoIdentity = ownedCryptoId.cryptoIdentity
            return try ObvIdentityManagerSyncSnapshotNode(ownedCryptoIdentity: ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext)
        }
    }

    
    public func serializeObvSyncSnapshotNode(_ syncSnapshotNode: any ObvSyncSnapshotNode) throws -> Data {
        let jsonEncoder = JSONEncoder()
        switch syncSnapshotNode {
        case is ObvIdentityManagerSyncSnapshotNode:
            return try jsonEncoder.encode(syncSnapshotNode)
        case is ObvIdentityManagerDeviceSnapshotNode:
            return try jsonEncoder.encode(syncSnapshotNode)
        default:
            assertionFailure()
            throw Self.makeError(message: "Unexpected snapshot type")
        }
    }
 
    
    public func deserializeObvSyncSnapshotNode(_ serializedSyncSnapshotNode: Data, context: ObvTypes.ObvSyncSnapshot.Context) throws -> any ObvSyncSnapshotNode {
        let jsonDecoder = JSONDecoder()
        switch context {
        case .transfer:
            let node = try jsonDecoder.decode(ObvIdentityManagerSyncSnapshotNode.self, from: serializedSyncSnapshotNode)
            return node
        case .backupProfile(ownedCryptoId: let ownedCryptoId):
            let node = try jsonDecoder.decode(ObvIdentityManagerSyncSnapshotNode.self, from: serializedSyncSnapshotNode)
            guard node.ownedCryptoIdentity.getIdentity() == ownedCryptoId.cryptoIdentity.getIdentity() else {
                assertionFailure()
                throw ObvIdentityManagerError.unexpectedOwnedIdentity
            }
            return node
        case .backupDevice:
            return try jsonDecoder.decode(ObvIdentityManagerDeviceSnapshotNode.self, from: serializedSyncSnapshotNode)
        }
    }
    
    
    public func restoreObvSyncSnapshotNode(_ syncSnapshotNode: any ObvSyncSnapshotNode, customDeviceName: String, within obvContext: ObvContext) throws {
        try restoreObvSyncSnapshotNode(syncSnapshotNode, customDeviceName: customDeviceName, allowOwnedIdentityToExistInDatabase: false, within: obvContext)
    }
    
    
    private func restoreObvSyncSnapshotNode(_ syncSnapshotNode: any ObvSyncSnapshotNode, customDeviceName: String, allowOwnedIdentityToExistInDatabase: Bool, within obvContext: ObvContext) throws {
        guard let node = syncSnapshotNode as? ObvIdentityManagerSyncSnapshotNode else {
            assertionFailure()
            throw Self.makeError(message: "Unexpected snapshot type")
        }
        try node.restore(prng: prng, customDeviceName: customDeviceName, delegateManager: delegateManager, allowOwnedIdentityToExistInDatabase: allowOwnedIdentityToExistInDatabase, within: obvContext)
    }

    
}


// MARK: - Other pre-keys related methods

extension ObvIdentityManagerImplementation {
    
    public func getUIDsOfRemoteDevicesForWhichHavePreKeys(ownedCryptoId: ObvCryptoIdentity, remoteCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<UID> {
        
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoId, delegateManager: delegateManager, within: obvContext) else {
            assertionFailure()
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        
        if remoteCryptoId == ownedCryptoId {
            
            let uids = ownedIdentity.otherDevices
                .filter({ $0.remoteOwnedDeviceHasPrekey })
                .map(\.uid)
            
            return Set(uids)
            
        } else {
            
            guard let contactIdentity = try ContactIdentity.get(contactIdentity: remoteCryptoId, ownedIdentity: ownedIdentity, delegateManager: delegateManager) else {
                //assertionFailure()
                return Set<UID>()
            }
            
            let uids = contactIdentity.devices
                .filter({ $0.hasPreKey })
                .map(\.uid)
            
            return Set(uids)
            
        }
        
    }
    
    
    public func getUIDsOfRemoteDevicesForWhichHavePreKeys(ownedCryptoId: ObvCryptoIdentity, remoteCryptoIds: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws -> [ObvCryptoIdentity: Set<UID>] {
        
        return try remoteCryptoIds.reduce(into: [ObvCryptoIdentity: Set<UID>]()) { partialResult, remoteCryptoId in
            partialResult[remoteCryptoId] = try getUIDsOfRemoteDevicesForWhichHavePreKeys(ownedCryptoId: ownedCryptoId, remoteCryptoId: remoteCryptoId, within: obvContext)
        }
                
    }
    
    
    public func deleteCurrentDeviceExpiredPreKeysOfOwnedIdentity(ownedCryptoId: ObvCryptoIdentity, downloadTimestampFromServer: Date, within obvContext: ObvContext) throws {
        
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoId, delegateManager: delegateManager, within: obvContext) else {
            assertionFailure()
            return
        }

        try ownedIdentity.deleteCurrentOwnedDeviceExpiredPreKeys(downloadTimestampFromServer: downloadTimestampFromServer)
        
    }

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
    
    
    public func getAdditionalInfosFromIdentityManagerForProfileBackup(ownedCryptoId: ObvCryptoId, flowId: FlowIdentifier) async throws -> AdditionalInfosFromIdentityManagerForProfileBackup {
        let delegateManager = self.delegateManager
        let defaultDeviceName = await UIDevice.current.preciseModel
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AdditionalInfosFromIdentityManagerForProfileBackup, any Error>) in
            delegateManager.contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoId.cryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
                        assertionFailure()
                        throw ObvIdentityManagerError.ownedIdentityNotFound
                    }
                    let currentDeviceName = ownedIdentity.currentDevice.name ?? defaultDeviceName
                    let additionalInfos = AdditionalInfosFromIdentityManagerForProfileBackup(deviceDisplayName: currentDeviceName)
                    return continuation.resume(returning: additionalInfos)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    public func getBackupSeedOfOwnedIdentity(ownedCryptoId: ObvCryptoId, restrictToActive: Bool, flowId: FlowIdentifier) async throws -> BackupSeed? {
        let delegateManager = self.delegateManager
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<BackupSeed?, any Error>) in
            delegateManager.contextCreator.performBackgroundTask { context in
                do {
                    let backupSeed = try OwnedIdentity.getBackupSeedOfOwnedIdentity(ownedCryptoId: ownedCryptoId, restrictToActive: restrictToActive, within: context)
                    return continuation.resume(returning: backupSeed)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func provideInternalDataForLegacyBackup(backupRequestIdentifier: FlowIdentifier) async throws -> (internalJson: String, internalJsonIdentifier: String, source: ObvBackupableObjectSource) {
        let delegateManager = self.delegateManager
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(internalJson: String, internalJsonIdentifier: String, source: ObvBackupableObjectSource), Error>) in
            do {
                try delegateManager.contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: backupRequestIdentifier) { obvContext in
                    let ownedIdentities = try OwnedIdentity.getAll(restrictToActive: true, delegateManager: delegateManager, within: obvContext)
                    guard !ownedIdentities.isEmpty else {
                        throw Self.makeError(message: "No data to backup since we could not find any owned identity")
                    }
                    let ownedIdentitiesBackupItems = Set(try ownedIdentities.map { try $0.backupItem })
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
    
    
    public func restoreLegacyBackup(backupRequestIdentifier: FlowIdentifier, internalJson: String?) async throws {
        let delegateManager = self.delegateManager
        let log = self.log
        let prng = self.prng
        guard let internalJson else {
            throw Self.makeError(message: "The identity manager requires an internal json to restore a backup but no internal json was provided")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try delegateManager.contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: backupRequestIdentifier) { (obvContext) in
                    let ownedIdentities = try OwnedIdentity.getAll(restrictToActive: false, delegateManager: delegateManager, within: obvContext)
                    guard ownedIdentities.isEmpty else {
                        throw Self.makeError(message: "📲 An owned identity is already present in database.")
                    }
                    // If we reach this point, we can try to restore the backup
                    let internalJsonData = internalJson.data(using: .utf8)!
                    let jsonDecoder = JSONDecoder()
                    let ownedIdentityBackupItems = try jsonDecoder.decode([OwnedIdentityBackupItem].self, from: internalJsonData)
                    
                    os_log("📲 The identity manager successfully parsed the internal json during the restore of the backup within flow %{public}@", log: log, type: .info, backupRequestIdentifier.debugDescription)
                    
                    guard ownedIdentityBackupItems.count > 0 else {
                        os_log("📲 No owned identity to restore, which is unexpected", log: log, type: .fault)
                        throw Self.makeError(message: "No owned identity to restore, which is unexpected")
                    }
                    
                    os_log("📲 We have %d owned identities to restore within flow %{public}@. We restore them now.", log: log, type: .info, ownedIdentityBackupItems.count, backupRequestIdentifier.debugDescription)
                    
                    for (index, ownedIdentityBackupItem) in ownedIdentityBackupItems.enumerated() {
                        
                        os_log("📲 Restoring the database owned identity instances %d out of %d within flow %{public}@...", log: log, type: .info, index+1, ownedIdentityBackupItems.count, backupRequestIdentifier.debugDescription)
                        
                        let associationsForRelationships: BackupItemObjectAssociations
                        do {
                            var associations = BackupItemObjectAssociations()
                            try ownedIdentityBackupItem.restoreInstance(within: obvContext,
                                                                        associations: &associations,
                                                                        delegateManager: delegateManager)
                            associationsForRelationships = associations
                        }
                        
                        os_log("📲 The instances were re-created. We now recreate the relationships.", log: log, type: .info)
                        
                        try ownedIdentityBackupItem.restoreRelationships(associations: associationsForRelationships, prng: prng, within: obvContext)
                        
                        os_log("📲 The relationships were recreated.", log: log, type: .info)
                        
                    }
                    
                    os_log("📲 Saving the context", log: log, type: .info)
                    
                    try obvContext.save(logOnFailure: log)
                    
                    os_log("📲 Context saved. We successfully restored the owned identities. Yepee!", log: log, type: .info, backupRequestIdentifier.debugDescription)
                    
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
        let allDetails = try OwnedIdentityDetailsPublished.getAllWithMissingPhotoFilename(within: obvContext)
        let results: [(ObvCryptoIdentity, IdentityDetailsElements)] = allDetails.compactMap { detailsPublished in
            guard let ownedCryptoIdentity = detailsPublished.ownedIdentity?.cryptoIdentity else { return nil }
            return (ownedCryptoIdentity, detailsPublished.getIdentityDetailsElements(identityPhotosDirectory: delegateManager.identityPhotosDirectory))
        }
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
            guard let ownedIdentity = contactIdentityDetails.contactIdentity.ownedIdentity else {
                assertionFailure()
                return nil
            }
            guard let contactCryptoIdentity = contactIdentityDetails.contactIdentity.cryptoIdentity else {
                assertionFailure()
                return nil
            }
            return (ownedIdentity.cryptoIdentity,
                    contactCryptoIdentity,
                    identityDetailsElements)
        }
        return results
    }
    
    
    // MARK: API related to owned identities
    
    
    public func isOwned(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        return try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) != nil
    }
    
    
    private func isOwned(_ identity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> Bool {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, any Error>) in
            delegateManager.contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let result = try self.isOwned(identity, within: obvContext)
                    return continuation.resume(returning: result)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    public func isOwnedIdentityActive(ownedIdentity identity: ObvCryptoIdentity, flowId: FlowIdentifier) throws -> Bool {
        var _isActive: Bool?
        try delegateManager.contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
                throw ObvIdentityManagerError.ownedIdentityNotFound
            }
            _isActive = ownedIdentity.isActive
        }
        guard let isActive = _isActive else {
            assertionFailure()
            throw makeError(message: "Bug in isOwnedIdentityActive. _isActive is not set although it should be.")
        }
        return isActive
    }
    
    
    public func isOwnedIdentityActive(ownedIdentity identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        return ownedIdentity.isActive
    }
    
    
    public func deactivateOwnedIdentityAndDeleteContactDevices(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        os_log("Deactivating owned identity %{public}@", log: log, type: .info, ownedIdentity.debugDescription)
        guard let ownedIdentityObj = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            assertionFailure()
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        ownedIdentityObj.deactivateAndDeleteAllContactDevices(delegateManager: delegateManager)
    }
    
    
    public func reactivateOwnedIdentity(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        os_log("Reactivating owned identity %{public}@", log: log, type: .info, ownedIdentity.debugDescription)
        guard let ownedIdentityObj = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        ownedIdentityObj.reactivate()
    }
    
    public func generateOwnedIdentity(onServerURL serverURL: URL, with identityDetails: ObvIdentityDetails, accordingTo pkEncryptionImplemByteId: PublicKeyEncryptionImplementationByteId, and authEmplemByteId: AuthenticationImplementationByteId, nameForCurrentDevice: String, keycloakState: ObvKeycloakState?, using prng: PRNGService, within obvContext: ObvContext) -> ObvCryptoIdentity? {
        guard let ownedIdentity = OwnedIdentity(serverURL: serverURL,
                                                identityDetails: identityDetails,
                                                accordingTo: pkEncryptionImplemByteId,
                                                and: authEmplemByteId,
                                                keycloakState: keycloakState,
                                                nameForCurrentDevice: nameForCurrentDevice,
                                                using: prng,
                                                delegateManager: delegateManager,
                                                within: obvContext) else { return nil }
        let ownedCryptoIdentity = ownedIdentity.ownedCryptoIdentity.getObvCryptoIdentity()
        return ownedCryptoIdentity
    }
    
    
    public func markOwnedIdentityForDeletion(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        if let identityObj = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) {
            identityObj.markForDeletion()
        }
    }
    
    
    public func isOwnedIdentityDeletedOrDeletionIsInProgress(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        return try OwnedIdentity.isOwnedIdentityDeletedOrDeletionIsInProgress(identity, within: obvContext.context)
    }
    
    
    public func deleteOwnedIdentity(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        if let identityObj = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) {
            try identityObj.delete(delegateManager: delegateManager, within: obvContext)
        }
    }
    
    
    public func getOwnedIdentities(restrictToActive: Bool, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity> {
        return try OwnedIdentity.getAllCryptoIds(restrictToActive: restrictToActive, within: obvContext.context)
    }
    
    
    public func getActiveOwnedIdentitiesAndCurrentDeviceName(within obvContext: ObvContext) throws -> [ObvCryptoIdentity: String?] {
        let ownedIdentities = try OwnedIdentity.getAll(restrictToActive: true, delegateManager: delegateManager, within: obvContext)
        let cryptoIdentitiesAndNames = ownedIdentities
            .map { ($0.ownedCryptoIdentity.getObvCryptoIdentity(), $0.currentDevice.name) }
        return Dictionary(cryptoIdentitiesAndNames) { cryptoIdentity, _ in
            assertionFailure()
            return cryptoIdentity
        }
    }
    
    
    public func getActiveOwnedIdentitiesThatAreNotKeycloakManaged(within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity> {
        let ownedIdentities = try OwnedIdentity.getAll(restrictToActive: true, delegateManager: delegateManager, within: obvContext)
        let cryptoIdentities = ownedIdentities
            .filter({ !$0.isKeycloakManaged })
            .map { $0.ownedCryptoIdentity.getObvCryptoIdentity() }
        return Set(cryptoIdentities)
    }
    
    
    public func saveRegisteredKeycloakAPIKey(ownedCryptoIdentity: ObvCryptoIdentity, apiKey: UUID, within obvContext: ObvContext) throws {
        guard let ownedIdentityObj = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        try ownedIdentityObj.saveRegisteredKeycloakAPIKey(apiKey: apiKey)
    }
    
    
    public func getRegisteredKeycloakAPIKey(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> UUID? {
        guard let ownedIdentityObj = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        return ownedIdentityObj.keycloakServer?.ownAPIKey
    }
    
    
    public func getActiveOwnedIdentitiesAndCurrentDeviceUids(within obvContext: ObvContext) throws -> Set<OwnedCryptoIdentityAndCurrentDeviceUID> {
        let ownedIdentities = try OwnedIdentity.getAll(restrictToActive: true, delegateManager: delegateManager, within: obvContext)
        let ownedIdentitiesAndCurrentDeviceUids = ownedIdentities.map { OwnedCryptoIdentityAndCurrentDeviceUID(ownedCryptoId: $0.cryptoIdentity, currentDeviceUID: $0.currentDeviceUid) }
        return Set(ownedIdentitiesAndCurrentDeviceUids)
    }
    
    
    public func getIdentityDetailsOfOwnedIdentity(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> (publishedIdentityDetails: ObvIdentityDetails, isActive: Bool) {
        guard let ownedIdentityObj = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        return (ownedIdentityObj.publishedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory), ownedIdentityObj.isActive)
    }
    
    
    // Used within the protocol manager
    public func getPublishedIdentityDetailsOfOwnedIdentity(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> (ownedIdentityDetailsElements: IdentityDetailsElements, photoURL: URL?) {
        
        guard let ownedIdentityObj = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        
        let ownedIdentityDetailsElements = IdentityDetailsElements(
            version: ownedIdentityObj.publishedIdentityDetails.version,
            coreDetails: ownedIdentityObj.publishedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory).coreDetails,
            photoServerKeyAndLabel: ownedIdentityObj.publishedIdentityDetails.photoServerKeyAndLabel)
        return (ownedIdentityDetailsElements, ownedIdentityObj.publishedIdentityDetails.getPhotoURL(identityPhotosDirectory: delegateManager.identityPhotosDirectory))
    }
    
    
    public func setPhotoServerKeyAndLabelForPublishedIdentityDetailsOfOwnedIdentity(_ identity: ObvCryptoIdentity, withPhotoServerKeyAndLabel photoServerKeyAndLabel: PhotoServerKeyAndLabel, within obvContext: ObvContext) throws -> IdentityDetailsElements {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        ownedIdentity.publishedIdentityDetails.set(photoServerKeyAndLabel: photoServerKeyAndLabel)
        _ = IdentityServerUserData.createForOwnedIdentityDetails(ownedIdentity: identity,
                                                                 label: photoServerKeyAndLabel.label,
                                                                 within: obvContext)
        return ownedIdentity.publishedIdentityDetails.getIdentityDetailsElements(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
    }
    
    
    public func updateDownloadedPhotoOfOwnedIdentity(_ identity: ObvCryptoIdentity, version: Int, photo: Data, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        try ownedIdentity.updatePhoto(withData: photo, version: version, delegateManager: delegateManager, within: obvContext)
    }
    
    
    public func updatePublishedIdentityDetailsOfOwnedIdentity(_ identity: ObvCryptoIdentity, with newIdentityDetails: ObvIdentityDetails, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        try ownedIdentity.updatePublishedDetailsWithNewDetails(newIdentityDetails, delegateManager: delegateManager)
    }
    
    
    /// Typically called when creating an oblivious channel with another owned device. In that case, during the protocol, we received the other owned identity details from that remote device. We keep them if they are newer than the one we have locally.
    /// In case we update the local details, we might be in a situation where the owned profile picture must be downloaded.
    public func updateOwnedPublishedDetailsWithOtherDetailsIfNewer(_ ownedIdentity: ObvCryptoIdentity, with otherIdentityDetails: IdentityDetailsElements, within obvContext: ObvContext) throws -> Bool {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        let photoDownloadNeeded = try ownedIdentity.updatePublishedDetailsWithOtherDetailsIfNewer(otherDetails: otherIdentityDetails, delegateManager: delegateManager)
        return photoDownloadNeeded
    }
    
    
    public func getDeterministicSeedForOwnedIdentity(_ identity: ObvCryptoIdentity, diversifiedUsing data: Data, within obvContext: ObvContext) throws -> Seed {
        guard let ownedIdentityObj = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext)  else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        return try ownedIdentityObj.getDeterministicSeed(diversifiedUsing: data, forProtocol: .trustEstablishmentWithSAS)
    }
    
    
    public func getDeterministicSeed(diversifiedUsing data: Data, secretMACKey: any MACKey, forProtocol seedProtocol: ObvConstants.SeedProtocol) throws -> Seed {
        return try OwnedIdentity.getDeterministicSeed(diversifiedUsing: data, secretMACKey: secretMACKey, forProtocol: seedProtocol)
    }

    
    public func getFreshMaskingUIDForPushNotifications(for identity: ObvCryptoIdentity, pushToken: Data, within obvContext: ObvContext) throws -> UID {
        guard let ownedIdentityObj = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        let maskingUID = try OwnedIdentityMaskingUID.getOrCreate(for: ownedIdentityObj, pushToken: pushToken)
        return maskingUID
    }
    
    
    public func getOwnedIdentityAssociatedToMaskingUID(_ maskingUID: UID, within obvContext: ObvContext) throws -> ObvCryptoIdentity? {
        let ownedIdentity = try OwnedIdentityMaskingUID.getOwnedIdentityAssociatedWithMaskingUID(maskingUID, within: obvContext)
        return ownedIdentity?.cryptoIdentity
    }
    
    public func computeTagForOwnedIdentity(_ identity: ObvCryptoIdentity, on data: Data, within obvContext: ObvContext) throws -> Data {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        let mac = ObvCryptoSuite.sharedInstance.mac()
        let dataToMac = "OwnedIdentityTag".data(using: .utf8)! + data
        return try mac.compute(forData: dataToMac, withKey: ownedIdentity.ownedCryptoIdentity.secretMACKey)
    }
    
    
    /// This method is called during a keycloak managed profile transfer, if the keycloak enforces a restriction on the transfer. It is called on the source device, when it receives a proof from the target device that it was able to authenticate against the keycloak server.
    /// This method verifies the signature and checks that the payload contained in the signature contains the elements that we expect.
    public func verifyKeycloakSignature(ownedCryptoId: ObvCryptoIdentity, keycloakTransferProof: ObvKeycloakTransferProof, keycloakTransferProofElements: ObvKeycloakTransferProofElements, within obvContext: ObvContext) throws {
        
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoId, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        
        try ownedIdentity.verifyKeycloakSignature(keycloakTransferProof: keycloakTransferProof, keycloakTransferProofElements: keycloakTransferProofElements, delegateManager: delegateManager)

    }
    
    
    // MARK: - API related to contact groups V2
    
    public func getGroupV2PhotoURLAndServerPhotoInfofOwnedIdentityIsUploader(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, within obvContext: ObvContext) throws -> (photoURL: URL, serverPhotoInfo: GroupV2.ServerPhotoInfo)? {
        
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { return nil }
        
        guard let photoURLAndServerPhotoInfo = try group.trustedDetails?.getPhotoURLAndServerPhotoInfo(identityPhotosDirectory: delegateManager.identityPhotosDirectory) else { return nil }
        
        // Check that the owned identity is the uploader
        guard photoURLAndServerPhotoInfo.serverPhotoInfo.identity == ownedIdentity else { return nil }
        
        return photoURLAndServerPhotoInfo
        
    }
    
    
    public func createContactGroupV2AdministratedByOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, serializedGroupCoreDetails: Data, photoURL: URL?, serializedGroupType: Data, ownRawPermissions: Set<String>, otherGroupMembers: Set<GroupV2.IdentityAndPermissions>, within obvContext: ObvContext) throws -> (groupIdentifier: GroupV2.Identifier, groupAdminServerAuthenticationPublicKey: PublicKeyForAuthentication, serverPhotoInfo: GroupV2.ServerPhotoInfo?, encryptedServerBlob: EncryptedData, photoURL: URL?) {
        
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        
        let (group, publicKey) = try ContactGroupV2.createContactGroupV2AdministratedByOwnedIdentity(ownedIdentity,
                                                                                                     serializedGroupCoreDetails: serializedGroupCoreDetails,
                                                                                                     photoURL: photoURL,
                                                                                                     serializedGroupType: serializedGroupType,
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
    
    
    public func createContactGroupV2JoinedByOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, serverBlob: GroupV2.ServerBlob, blobKeys: GroupV2.BlobKeys, createdByMeOnOtherDevice: Bool, within obvContext: ObvContext) throws {
        
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        
        try ContactGroupV2.createContactGroupV2JoinedByOwnedIdentity(ownedIdentity,
                                                                     groupIdentifier: groupIdentifier,
                                                                     serverBlob: serverBlob,
                                                                     blobKeys: blobKeys,
                                                                     createdByMeOnOtherDevice: createdByMeOnOtherDevice,
                                                                     delegateManager: delegateManager)
    }
    
    
    public func deleteGroupV2(withGroupIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { return }
        try group.delete()
    }
    
    
    public func removeOtherMembersOrPendingMembersFromGroupV2(withGroupIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, identitiesToRemove: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { return }
        try group.removeOtherMembersOrPendingMembers(identitiesToRemove)
    }
    
    
    public func freezeGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { return }
        group.freeze()
    }
    
    
    public func unfreezeGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { return }
        group.unfreeze()
    }
    
    
    public func getGroupV2BlobKeysOfGroup(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> GroupV2.BlobKeys {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        guard let blobKeys = group.blobKeys else { assertionFailure(); throw Self.makeError(message: "Could not extract blob keys from group") }
        return blobKeys
    }
    
    
    public func getPendingMembersAndPermissionsOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<GroupV2.IdentityAndPermissions> {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        let pendingMembersAndPermissions = try group.getPendingMembersAndPermissions()
        return pendingMembersAndPermissions
    }
    
    
    public func getVersionOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Int {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        return group.groupVersion
    }
    
    
    public func checkExistenceOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager)
        return group != nil
    }
    
    
    public func updateGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, newBlobKeys: GroupV2.BlobKeys, consolidatedServerBlob: GroupV2.ServerBlob, groupUpdatedByOwnedIdentity: Bool, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity> {
        // We create a local context that we can discard in case this method should throw
        let localContext = obvContext.createChildObvContext()
        var insertedOrUpdatedIdentities: Set<ObvCryptoIdentity>!
        try localContext.performAndWaitOrThrow {
            guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: localContext) else {
                throw ObvIdentityManagerError.ownedIdentityNotFound
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
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        return try group.getAllOtherMembersOrPendingMembersIdentifiedByNonce(nonce)
    }
    
    
    public func movePendingMemberToMembersOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, pendingMemberCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        try group.movePendingMemberToOtherMembers(pendingMemberCryptoIdentity: pendingMemberCryptoIdentity, delegateManager: delegateManager)
    }
    
    
    public func getOwnGroupInvitationNonceOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Data {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        return group.ownGroupInvitationNonce
    }
    
    
    public func setDownloadedPhotoOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, serverPhotoInfo: GroupV2.ServerPhotoInfo, photo: Data, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        try group.updatePhoto(withData: photo, serverPhotoInfo: serverPhotoInfo, delegateManager: delegateManager)
    }
    
    public func photoNeedsToBeDownloadedForGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, serverPhotoInfo: GroupV2.ServerPhotoInfo, within obvContext: ObvContext) throws -> Bool {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        return group.photoNeedsToBeDownloaded(serverPhotoInfo: serverPhotoInfo, delegateManager: delegateManager)
    }
    
    
    public func getAllObvGroupV2(of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvGroupV2> {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        let groups = try ContactGroupV2.getAllObvGroupV2(of: ownedIdentity, delegateManager: delegateManager)
        return groups
    }
    
    
    public func getObvGroupV2(with identifier: ObvGroupV2Identifier, within obvContext: ObvContext) throws -> ObvGroupV2? {
        guard let ownedIdentity = try OwnedIdentity.get(identifier.ownedCryptoId.cryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        let groupIdentifier = GroupV2.Identifier(obvGroupV2Identifier: identifier.identifier)
        let group = try ContactGroupV2.getObvGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager)
        return group
    }
    
    public func getTrustedPhotoURLAndUploaderOfObvGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> (url: URL, uploader: ObvCryptoIdentity)? {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        guard let photoURLAndUploader = group.trustedDetails?.getPhotoURLAndUploader(identityPhotosDirectory: delegateManager.identityPhotosDirectory) else { return nil }
        guard FileManager.default.fileExists(atPath: photoURLAndUploader.url.path) else { assertionFailure(); return nil }
        return photoURLAndUploader
    }
    
    
    public func replaceTrustedDetailsByPublishedDetailsOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else {
            throw Self.makeError(message: "Could not find group")
        }
        try group.replaceTrustedDetailsByPublishedDetails(identityPhotosDirectory: identityPhotosDirectory, delegateManager: delegateManager)
    }
    
    
    public func getAdministratorChainOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> GroupV2.AdministratorsChain {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else {
            throw Self.makeError(message: "Could not find group")
        }
        return try group.getServerBlob().administratorsChain
    }
    
    
    public func getAllOtherMembersOrPendingMembersOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<GroupV2.IdentityAndPermissionsAndDetails> {
        
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        return try group.getAllOtherMembersOrPendingMembers()
        
    }
    
    
    public func getAllNonPendingAdministratorsIdentitiesOfGroupV2(withGroupWithIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity> {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard let group = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) else { throw Self.makeError(message: "Could not find group") }
        return try group.getAllNonPendingAdministratorsIdentitites()
    }
    
    
    public func getAllGroupsV2IdentifierVersionAndKeysForContact(_ contactIdentity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> [GroupV2.IdentifierVersionAndKeys] {
        guard let contact = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find contact")
        }
        guard let ownedIdentity_ = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        let identifierVersionAndKeysOfGroupsWhereTheContactIsNotPending = contact.groupMemberships.compactMap { $0.contactGroup?.identifierVersionAndKeys }
        let identifierVersionAndKeysOfGroupsWhereTheContactIsPending = (try ContactGroupV2PendingMember.getPendingMemberEntriesCorrespondingToContactIdentity(contactIdentity, of: ownedIdentity_)).compactMap({ $0.contactGroup?.identifierVersionAndKeys })
        
        let allIdentifierVersionAndKeys = identifierVersionAndKeysOfGroupsWhereTheContactIsNotPending + identifierVersionAndKeysOfGroupsWhereTheContactIsPending
        
        return allIdentifierVersionAndKeys
    }
    
    
    public func getAllGroupsV2IdentifierVersionAndKeys(ofOwnedIdentity ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> [GroupV2.IdentifierVersionAndKeys] {
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoId, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        return ownedIdentity.contactGroupsV2.compactMap { $0.identifierVersionAndKeys }
    }
    
    
    // MARK: - Keycloak pushed groups
    
    public func updateKeycloakGroups(ownedIdentity: ObvCryptoIdentity, signedGroupBlobs: Set<String>, signedGroupDeletions: Set<String>, signedGroupKicks: Set<String>, keycloakCurrentTimestamp: Date, within obvContext: ObvContext) throws -> [KeycloakGroupV2UpdateOutput] {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        
        let keycloakGroupV2UpdateOutputs = try ownedIdentityObject.updateKeycloakGroups(signedGroupBlobs: signedGroupBlobs,
                                                                                        signedGroupDeletions: signedGroupDeletions,
                                                                                        signedGroupKicks: signedGroupKicks,
                                                                                        keycloakCurrentTimestamp: keycloakCurrentTimestamp,
                                                                                        delegateManager: delegateManager,
                                                                                        within: obvContext)
        
        return keycloakGroupV2UpdateOutputs
        
    }
    
    
    public func getIdentifiersOfAllKeycloakGroups(ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<GroupV2.Identifier> {
        let groupIdentifiers = try ContactGroupV2.getAllIdentifiersOfKeycloakGroups(of: ownedCryptoId, within: obvContext)
        return groupIdentifiers
    }
    
    
    public func getIdentifiersOfAllKeycloakGroupsWhereContactIsPending(ownedCryptoId: ObvCryptoIdentity, contactCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<GroupV2.Identifier> {
        let groupIdentifiers = try ContactGroupV2.getIdentifiersOfAllKeycloakGroupsWhereContactIsPending(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId, within: obvContext)
        return groupIdentifiers
    }
    
    
    public func getAllKeycloakContactsThatArePendingInSomeKeycloakGroup(within obvContext: ObvContext) throws -> [ObvCryptoIdentity: Set<ObvCryptoIdentity>] {
        
        var returnValues = [ObvCryptoIdentity: Set<ObvCryptoIdentity>]()
        
        let ownedCryptoIds = Set(try OwnedIdentity.getAllKeycloakManaged(delegateManager: delegateManager, within: obvContext)
            .map(\.cryptoIdentity))
        
        for ownedCryptoId in ownedCryptoIds {
            let pendingMembers = try ContactGroupV2PendingMember.getAllPendingMembersCorrespondingToOwnedIdentity(ownedCryptoId, groupCategory: .keycloak, within: obvContext.context)
            let pendingContactMembers = try pendingMembers.filter { pendingMember in
                guard try isIdentity(pendingMember, aContactIdentityOfTheOwnedIdentity: ownedCryptoId, within: obvContext) else { return false }
                guard try isContactCertifiedByOwnKeycloak(contactIdentity: pendingMember, ofOwnedIdentity: ownedCryptoId, within: obvContext) else { return false }
                // The pending member is a contact and is keycloak managed, we keep her in the returned list
                return true
            }
            returnValues[ownedCryptoId] = pendingContactMembers
        }
        
        return returnValues
        
    }
    
    
    // MARK: - API related to keycloak management
    
    public func isOwnedIdentityKeycloakManaged(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        guard let ownedIdentity_ = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        return ownedIdentity_.isKeycloakManaged
    }
    
    public func isContactCertifiedByOwnKeycloak(contactIdentity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        guard let contactObj = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find contact")
        }
        return contactObj.isCertifiedByOwnKeycloak
    }
    
    
    public func getSignedContactDetails(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> SignedObvKeycloakUserDetails? {
        guard let contactObj = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find contact")
        }
        return try contactObj.getSignedUserDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
    }
    
    
    public func getOwnedIdentityKeycloakState(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> (obvKeycloakState: ObvKeycloakState?, signedOwnedDetails: SignedObvKeycloakUserDetails?) {
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
        let signedOwnedDetails = try? SignedObvKeycloakUserDetails.verifySignedUserDetails(signedDetails, with: signatureVerificationKey)
        assert(signedOwnedDetails != nil, "An invalid signature should not have been stored in the first place")
        return (obvKeycloakState, signedOwnedDetails)
    }
    
    public func saveKeycloakAuthState(ownedIdentity: ObvCryptoIdentity, rawAuthState: Data, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        ownedIdentity.keycloakServer?.setAuthState(authState: rawAuthState)
    }
    
    public func saveKeycloakJwks(ownedIdentity: ObvCryptoIdentity, jwks: ObvJWKSet, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        assert(ownedIdentity.keycloakServer != nil)
        try ownedIdentity.keycloakServer?.setJwks(jwks)
    }
    
    public func getOwnedIdentityKeycloakUserId(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> String? {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        return ownedIdentity.keycloakServer?.keycloakUserId
    }
    
    public func setOwnedIdentityKeycloakUserId(ownedIdentity: ObvCryptoIdentity, keycloakUserId userId: String?, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        ownedIdentity.keycloakServer?.setKeycloakUserId(keycloakUserId: userId)
    }
    
    
    public func bindOwnedIdentityToKeycloak(ownedCryptoIdentity: ObvCryptoIdentity, keycloakUserId userId: String, keycloakState: ObvKeycloakState, within obvContext: ObvContext) throws {
        
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        
        try ownedIdentity.bindToKeycloak(keycloakState: keycloakState, delegateManager: delegateManager)
        try setOwnedIdentityKeycloakUserId(ownedIdentity: ownedCryptoIdentity, keycloakUserId: userId, within: obvContext)
        assert(ownedIdentity.isKeycloakManaged)
        
    }
    
    
    public func getContactsCertifiedByOwnKeycloak(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity> {
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard ownedIdentity.isKeycloakManaged else { return Set<ObvCryptoIdentity>() }
        let contactsCertifiedByOwnKeycloak = Set(ownedIdentity.contactIdentities.filter({ $0.isCertifiedByOwnKeycloak }).compactMap({ $0.cryptoIdentity }))
        return contactsCertifiedByOwnKeycloak
    }
    
    
    public func unbindOwnedIdentityFromKeycloak(ownedCryptoIdentity: ObvCryptoIdentity, isUnbindRequestByUser: Bool, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find Owned Identity in database")
        }
        try ownedIdentity.unbindFromKeycloak(delegateManager: delegateManager, isUnbindRequestByUser: isUnbindRequestByUser)
        assert(!ownedIdentity.isKeycloakManaged)
        
        let publishedDetails = ownedIdentity.publishedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
        let publishedDetailsWithoutSignedDetails = try publishedDetails.removingSignedUserDetailsAndPositionAndCompany()
        
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
    
    
    /// Returns the registered push topics for both the keycloak server and the keycloak managed groups
    public func getKeycloakPushTopics(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<String> {
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find Owned Identity in database")
        }
        return try ownedIdentity.getPushTopicsForKeycloakServerAndForKeycloakManagedGroups()
    }
    
    
    public func getCryptoIdentitiesOfManagedOwnedIdentitiesAssociatedWithThePushTopic(_ pushTopic: String, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity> {
        let ownedIdentities = try OwnedIdentity.getAll(restrictToActive: true, delegateManager: delegateManager, within: obvContext)
        let appropriateOwnedIdentities = try ownedIdentities
            .filter({ $0.isKeycloakManaged })
            .filter({ try $0.getPushTopicsForKeycloakServerAndForKeycloakManagedGroups().contains(pushTopic) == true })
        return Set(appropriateOwnedIdentities.map { $0.cryptoIdentity })
    }
    
    
    public func setIsTransferRestricted(to isTransferRestricted: Bool, ownedCryptoId: ObvCryptoId, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoId.cryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        try ownedIdentity.setIsTransferRestricted(to: isTransferRestricted)
    }
    
    
    // MARK: - API related to owned devices
    
    public func getLatestChannelCreationPingTimestampOfRemoteOwnedDevice(withIdentifier ownedDeviceIdentifier: ObvOwnedDeviceIdentifier, within obvContext: ObvContext) throws -> Date? {
        guard let ownedIdentity = try OwnedIdentity.get(ownedDeviceIdentifier.ownedCryptoId.cryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        return try ownedIdentity.getLatestChannelCreationPingTimestampOfRemoteOwnedDevice(withUID: ownedDeviceIdentifier.deviceUID)
    }

    
    public func setLatestChannelCreationPingTimestampOfRemoteOwnedDevice(withIdentifier ownedDeviceIdentifier: ObvOwnedDeviceIdentifier, to date: Date, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedDeviceIdentifier.ownedCryptoId.cryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        try ownedIdentity.setLatestChannelCreationPingTimestampOfRemoteOwnedDevice(withUID: ownedDeviceIdentifier.deviceUID, to: date)
    }
    

    public func getDeviceUidsOfOwnedIdentity(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<UID> {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        let devices = ownedIdentity.otherDevices.union([ownedIdentity.currentDevice])
        return Set(devices.map { return $0.uid })
    }
    
    
    public func getOwnedIdentityOfCurrentDeviceUid(_ currentDeviceUid: UID, within obvContext: ObvContext) throws -> ObvCryptoIdentity {
        guard let currentDevice = try OwnedDevice.get(currentDeviceUid: currentDeviceUid, delegateManager: delegateManager, within: obvContext) else {
            throw Self.makeError(message: "Could not find OwnedDevice")
        }
        guard let identity = currentDevice.identity else {
            assertionFailure()
            throw Self.makeError(message: "Could not find Owned identity")
        }
        return identity.ownedCryptoIdentity.getObvCryptoIdentity()
    }
    
    
    public func getOwnedIdentityOfRemoteDeviceUid(_ remoteDeviceUid: UID, within obvContext: ObvContext) throws -> ObvCryptoIdentity? {
        let remoteDevice = try OwnedDevice.get(remoteDeviceUid: remoteDeviceUid, delegateManager: delegateManager, within: obvContext)
        return remoteDevice?.identity?.ownedCryptoIdentity.getObvCryptoIdentity()
    }
    
    
    public func getCurrentDeviceUidOfOwnedIdentity(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> UID {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        return ownedIdentity.currentDevice.uid
    }
    
    
    public func getOtherDeviceUidsOfOwnedIdentity(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<UID> {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        return Set(ownedIdentity.otherDevices.map { return $0.uid })
    }
    
    
    public func addOtherDeviceForOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, withUid uid: UID, createdDuringChannelCreation: Bool, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        try ownedIdentity.addIfNotExistRemoteDeviceWith(uid: uid, createdDuringChannelCreation: createdDuringChannelCreation)
    }
    
    public func removeOtherDeviceForOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, otherDeviceUid: UID, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        try ownedIdentity.removeIfExistsOtherDeviceWith(uid: otherDeviceUid, delegateManager: delegateManager, flowId: obvContext.flowId)
    }
    
    public func isDevice(withUid deviceUid: UID, aRemoteDeviceOfOwnedIdentity identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        guard let ownedIdentityObj = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        let ownedRemoteDeviceUids = ownedIdentityObj.otherDevices.map { return $0.uid }
        return ownedRemoteDeviceUids.contains(deviceUid)
    }
    
    
    public func getAllRemoteOwnedDevicesUidsAndContactDeviceUids(within obvContext: ObvContext) throws -> Set<ObliviousChannelIdentifier> {
        let ownedRemoteDevices = try OwnedDevice.getAllOwnedRemoteDeviceUids(within: obvContext)
        let contactDevices = try ContactDevice.getAllContactDeviceUids(within: obvContext)
        return ownedRemoteDevices.union(contactDevices)
    }
    
    
    /// Method used when determining which channel creation protocol should be re-started
    public func getAllRemoteOwnedDevicesUidsAndContactDeviceUidsWithLatestChannelCreationPingTimestamp(earlierThan date: Date, within obvContext: ObvContext) throws -> Set<ObliviousChannelIdentifier> {
        let ownedRemoteDevices = try OwnedDevice.getAllOwnedRemoteDeviceUidsWithLatestChannelCreationPingTimestamp(earlierThan: date, within: obvContext.context)
        let contactDevices = try ContactDevice.getAllContactDeviceUidsWithLatestChannelCreationPingTimestamp(earlierThan: date, within: obvContext.context)
        return ownedRemoteDevices.union(contactDevices)
    }

    
    public func processContactDeviceDiscoveryResult(_ contactDeviceDiscoveryResult: ContactDeviceDiscoveryResult, forContactCryptoId contactCryptoId: ObvCryptoIdentity, ofOwnedCryptoId ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let contact = try ContactIdentity.get(contactIdentity: contactCryptoId, ownedIdentity: ownedCryptoId, delegateManager: delegateManager, within: obvContext) else {
            // The contact cannot be found, there is nothing to process
            return
        }
        try contact.processContactDeviceDiscoveryResult(contactDeviceDiscoveryResult, log: log, flowId: obvContext.flowId)
    }
    
    
    /// Returns a Boolean indicating whether the current device is part of the owned device discovery results.
    public func processEncryptedOwnedDeviceDiscoveryResult(_ encryptedOwnedDeviceDiscoveryResult: EncryptedData, forOwnedCryptoId ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> OwnedDeviceDiscoveryPostProcessingTask {
        guard let ownedIdentityObj = try OwnedIdentity.get(ownedCryptoId, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        let currentDeviceIsPartOfOwnedDeviceDiscoveryResult = try ownedIdentityObj.processEncryptedOwnedDeviceDiscoveryResult(encryptedOwnedDeviceDiscoveryResult,
                                                                                                                              prng: prng,
                                                                                                                              solveChallengeDelegate: self,
                                                                                                                              delegateManager: delegateManager,
                                                                                                                              within: obvContext)
        return currentDeviceIsPartOfOwnedDeviceDiscoveryResult
    }
    
    
    public func decryptEncryptedOwnedDeviceDiscoveryResult(_ encryptedOwnedDeviceDiscoveryResult: EncryptedData, forOwnedCryptoId ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> OwnedDeviceDiscoveryResult {
        
        guard let ownedIdentityObj = try OwnedIdentity.get(ownedCryptoId, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        
        let ownedDeviceDiscoveryResult = try ownedIdentityObj.decryptEncryptedOwnedDeviceDiscoveryResult(encryptedOwnedDeviceDiscoveryResult)
        
        return ownedDeviceDiscoveryResult
        
    }
    
    
    /// Used when the user requests the restoration of a (new) backup, to decide whether older owned devices would be deactivated or not.
    public func decryptEncryptedOwnedDeviceDiscoveryResult(_ encryptedOwnedDeviceDiscoveryResult: EncryptedData, forOwnedCryptoIdentity ownedCryptoIdentity: ObvOwnedCryptoIdentity) throws -> OwnedDeviceDiscoveryResult {
        
        let ownedDeviceDiscoveryResult = try OwnedDeviceDiscoveryResult.decrypt(encryptedOwnedDeviceDiscoveryResult: encryptedOwnedDeviceDiscoveryResult, for: ownedCryptoIdentity)
        return ownedDeviceDiscoveryResult

    }
    
    
    public func decryptProtocolCiphertext(_ ciphertext: EncryptedData, forOwnedCryptoId ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Data {

        guard let ownedIdentityObj = try OwnedIdentity.get(ownedCryptoId, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        
        let cleartext = try ownedIdentityObj.decryptProtocolCiphertext(ciphertext)
        
        return cleartext

    }

    
    public func getInfosAboutOwnedDevice(withUid uid: UID, ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> (name: String?, expirationDate: Date?, latestRegistrationDate: Date?) {
        
        guard let ownedIdentityObj = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        
        let infos = try ownedIdentityObj.getInfosAboutOwnedDevice(withUid: uid)
        
        return infos
        
    }
    
    
    public func setCurrentDeviceNameOfOwnedIdentityAfterBackupRestore(ownedCryptoIdentity: ObvCryptoIdentity, nameForCurrentDevice: String, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        ownedIdentity.setCurrentDeviceNameAfterBackupRestore(newName: nameForCurrentDevice)
    }
    
    
    // MARK: - API related to contact identities
    
    
    public func getDateOfLastBootstrappedContactDeviceDiscovery(forContactCryptoId contactCryptoId: ObvCryptoIdentity, ofOwnedCryptoId ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Date {
        return try ContactIdentity.getDateOfLastBootstrappedContactDeviceDiscovery(contactIdentity: contactCryptoId, ownedIdentity: ownedCryptoId, within: obvContext.context)
    }
    
    
    public func setDateOfLastBootstrappedContactDeviceDiscovery(forContactCryptoId contactCryptoId: ObvCryptoIdentity, ofOwnedCryptoId ownedCryptoId: ObvCryptoIdentity, to newDate: Date, within obvContext: ObvContext) throws {
        guard let contact = try ContactIdentity.get(contactIdentity: contactCryptoId, ownedIdentity: ownedCryptoId, delegateManager: delegateManager, within: obvContext) else {
            throw Self.makeError(message: "Could not find contact")
        }
        contact.setDateOfLastBootstrappedContactDeviceDiscovery(to: newDate)
    }
    
    
    public func addContactIdentity(_ contactIdentity: ObvCryptoIdentity, with identityCoreDetails: ObvIdentityCoreDetails, andTrustOrigin trustOrigin: TrustOrigin, forOwnedIdentity ownedIdentity: ObvCryptoIdentity, isKnownToBeOneToOne: Bool, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        guard ContactIdentity(cryptoIdentity: contactIdentity, identityCoreDetails: identityCoreDetails, trustOrigin: trustOrigin, ownedIdentity: ownedIdentity, isKnownToBeOneToOne: isKnownToBeOneToOne, delegateManager: delegateManager) != nil else {
            throw makeError(message: "Could not create ContactIdentity instance")
        }
    }
    

    public func addTrustOriginIfTrustWouldBeIncreasedAndSetContactAsOneToOne(_ trustOrigin: TrustOrigin, toContactIdentity contactIdentity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let contactObj = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            assertionFailure()
            throw Self.makeError(message: "Could not find ContactIdentity")
        }
        try contactObj.addTrustOriginIfTrustWouldBeIncreased(trustOrigin, delegateManager: delegateManager)
        contactObj.setIsOneToOne(to: true, reasonToLog: "Call to ObvIdentityManagerImplementation.addTrustOriginIfTrustWouldBeIncreasedAndSetContactAsOneToOne(_:toContactIdentity:ofOwnedIdentity:within:)")
    }
    
    public func getTrustOrigins(forContactIdentity contactIdentity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> [TrustOrigin] {
        guard let contactObj = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            assertionFailure()
            throw Self.makeError(message: "Could not find ContactIdentity")
        }
        return contactObj.trustOrigins
    }
    
    public func getTrustLevel(forContactIdentity contactIdentity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> TrustLevel {
        guard let contactObj = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            assertionFailure()
            throw Self.makeError(message: "Could not find ContactIdentity")
        }
        return contactObj.trustLevel
    }
    
    public func getContactsOfOwnedIdentity(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity> {
        guard let ownedIdentity = try OwnedIdentity.get(identity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        return Set(ownedIdentity.contactIdentities.compactMap { return $0.cryptoIdentity })
    }
    
    
    public func getContactsWithNoDeviceOfOwnedIdentity(_ ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<ObvCryptoIdentity> {
        return try ContactIdentity.getCryptoIdentitiesOfContactsWithoutDevice(ownedCryptoId: ownedCryptoId, within: obvContext.context)
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
        return contactIdentityObject.isRevokedAsCompromisedAndNotForcefullyTrustedByUser
    }
    
    
    public func setContactForcefullyTrustedByUser(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, forcefullyTrustedByUser: Bool, within obvContext: ObvContext) throws {
        guard let contactIdentityObject = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { throw makeError(message: "Could not find contact identity") }
        contactIdentityObject.setForcefullyTrustedByUser(to: forcefullyTrustedByUser, delegateManager: delegateManager)
    }
    
    public func getOneToOneStatusOfContactIdentity(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> OneToOneStatusOfContactIdentity {
        guard let contactIdentityObject = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { return .notOneToOne }
        return contactIdentityObject.oneToOneStatus
    }
    
    public func setOneToOneContactStatus(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, newIsOneToOneStatus: Bool, reasonToLog: String, within obvContext: ObvContext) throws {
        guard let contactIdentityObject = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else { throw makeError(message: "Could not find contact identity") }
        contactIdentityObject.setIsOneToOne(to: newIsOneToOneStatus, reasonToLog: reasonToLog)
    }
    
    
    public func getContactsOfAllActiveOwnedIdentitiesRequiringContactDeviceDiscovery(within obvContext: ObvContext) throws -> Set<ObvContactIdentifier> {
        return try ContactIdentity.getContactsOfAllActiveOwnedIdentitiesRequiringContactDeviceDiscovery(within: obvContext.context)
    }
    
    
    public func checkIfContactWasRecentlyOnline(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        guard let contact = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find contact identity")
        }
        return contact.wasContactRecentlyOnline
    }
    
    
    public func markContactAsRecentlyOnline(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let contact = try ContactIdentity.get(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find contact identity")
        }
        contact.markAsRecentlyOnline()
    }
    

    // MARK: - API related to contact devices
    
    public func getLatestChannelCreationPingTimestampOfContactDevice(withIdentifier contactDeviceIdentifier: ObvContactDeviceIdentifier, within obvContext: ObvContext) throws -> Date? {
        guard let contact = try ContactIdentity.get(contactIdentity: contactDeviceIdentifier.contactCryptoId.cryptoIdentity, ownedIdentity: contactDeviceIdentifier.ownedCryptoId.cryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find contact identity")
        }
        return try contact.getLatestChannelCreationPingTimestampOfContactDevice(withUID: contactDeviceIdentifier.deviceUID)
    }

    
    public func setLatestChannelCreationPingTimestampOfContactDevice(withIdentifier contactDeviceIdentifier: ObvContactDeviceIdentifier, to date: Date, within obvContext: ObvContext) throws {
        guard let contact = try ContactIdentity.get(contactIdentity: contactDeviceIdentifier.contactCryptoId.cryptoIdentity, ownedIdentity: contactDeviceIdentifier.ownedCryptoId.cryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw makeError(message: "Could not find contact identity")
        }
        try contact.setLatestChannelCreationPingTimestampOfContactDevice(withUID: contactDeviceIdentifier.deviceUID, to: date)
    }

    
    public func addDeviceForContactIdentity(_ contactIdentity: ObvCryptoIdentity, withUid uid: UID, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, createdDuringChannelCreation: Bool, within obvContext: ObvContext) throws {
        guard let contactIdentity = try ContactIdentity.get(contactIdentity: contactIdentity,
                                                            ownedIdentity: ownedIdentity,
                                                            delegateManager: delegateManager,
                                                            within: obvContext) else {
            throw ObvIdentityManagerImplementation.makeError(message: "Could not find contact identity")
        }
        try contactIdentity.addIfNotExistDeviceWith(uid: uid, createdDuringChannelCreation: createdDuringChannelCreation, flowId: obvContext.flowId)
    }
    
    
    public func getDeviceUidsOfContactIdentity(_ identity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<UID> {
        guard let contactIdentity = try ContactIdentity.get(contactIdentity: identity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerImplementation.makeError(message: "Could not find ContactIdentity object")
        }
        let deviceUids = contactIdentity.devices.map { $0.uid }
        return Set(deviceUids)
    }
    
    
    public func isDevice(withUid deviceUid: UID, aDeviceOfContactIdentity identity: ObvCryptoIdentity, ofOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        guard let contactIdentityObj = try ContactIdentity.get(contactIdentity: identity, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            assertionFailure()
            throw Self.makeError(message: "Could not find ContactIdentity")
        }
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
            try device.deleteContactDevice()
        }
    }
    
    // MARK: - API related to contact groups
    
    /// This method returns the group information (and photo) corresponding to the published details of the joined group.
    /// If a photoURL is present in the `GroupInformationWithPhoto`, this method will copy this photo and create server label/key for it.
    public func createContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupInformationWithPhoto: GroupInformationWithPhoto, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, within obvContext: ObvContext) throws -> GroupInformationWithPhoto {
        
        guard groupInformationWithPhoto.groupOwnerIdentity == ownedIdentity else { throw makeError(message: "The group owner is not the owned identity") }
        
        let groupUid = groupInformationWithPhoto.groupUid
        
        // If the GroupInformationWithPhoto contains a photo, we need to generate a server key/label for it.
        // We then update the GroupInformationWithPhoto in order for this server key/label to be stored in the created owned group
        let updatedGroupInformationWithPhoto: GroupInformationWithPhoto
        if let photoServerKeyAndLabel = groupInformationWithPhoto.groupDetailsElementsWithPhoto.photoServerKeyAndLabel {
            // This group was clearely created on another owned device
            _ = GroupServerUserData.createForOwnedGroupDetails(ownedIdentity: ownedIdentity,
                                                               label: photoServerKeyAndLabel.label,
                                                               groupUid: groupUid,
                                                               within: obvContext)
            updatedGroupInformationWithPhoto = groupInformationWithPhoto
        } else if groupInformationWithPhoto.photoURL == nil {
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
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard let group = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }
        
        guard try isIdentity(pendingMember, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotContact
        }
        
        guard try isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: pendingMember, within: obvContext) else {
            throw makeError(message: "Trying to transfer an inactive contact from pending to groups members of a group owned")
        }
        
        guard let contactIdentity = try ContactIdentity.get(contactIdentity: pendingMember, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotContact
        }
        
        try group.transferPendingMemberToGroupMembersForGroupOwned(contactIdentity: contactIdentity)
        
        try groupMembersChangedCallback()
    }
    
    
    public func transferGroupMemberToPendingMembersOfContactGroupOwnedAndMarkPendingMemberAsDeclined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupMember: ObvCryptoIdentity, within obvContext: ObvContext, groupMembersChangedCallback: () throws -> Void) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard let group = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }
        
        guard try isIdentity(groupMember, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotContact
        }
        
        try group.transferGroupMemberToPendingMembersForGroupOwned(contactCryptoIdentity: groupMember)
        
        try markPendingMemberAsDeclined(ownedIdentity: ownedIdentity, groupUid: groupUid, pendingMember: groupMember, within: obvContext)
        
        try groupMembersChangedCallback()
        
    }
    
    
    public func addPendingMembersToContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, newPendingMembers: Set<ObvCryptoIdentity>, within obvContext: ObvContext, groupMembersChangedCallback: () throws -> Void) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard let group = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }
        
        try group.add(newPendingMembers: newPendingMembers, delegateManager: delegateManager)
        
        try groupMembersChangedCallback()
        
    }
    
    
    public func removePendingAndMembersToContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, pendingOrMembersToRemove: Set<ObvCryptoIdentity>, within obvContext: ObvContext, groupMembersChangedCallback: () throws -> Void) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard let group = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }
        
        try group.remove(pendingOrGroupMembers: pendingOrMembersToRemove)
        
        try groupMembersChangedCallback()
        
    }
    
    
    public func markPendingMemberAsDeclined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, pendingMember: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }
        
        try groupOwned.markPendingMemberAsDeclined(pendingGroupMember: pendingMember)
        
    }
    
    
    public func unmarkDeclinedPendingMemberAsDeclined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, pendingMember: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }
        
        try groupOwned.unmarkDeclinedPendingMemberAsDeclined(pendingGroupMember: pendingMember)
        
    }
    
    
    public func updatePublishedDetailsOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation, within obvContext: ObvContext) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard let groupJoined = try ContactGroupJoined.get(groupUid: groupInformation.groupUid,
                                                           groupOwnerCryptoIdentity: groupInformation.groupOwnerIdentity,
                                                           ownedIdentity: ownedIdentityObject,
                                                           delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }
        
        try groupJoined.updateDetailsPublished(with: groupInformation.groupDetailsElements, delegateManager: delegateManager)
    }
    
    
    public func updateDownloadedPhotoOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupOwner: ObvCryptoIdentity, groupUid: UID, version: Int, photo: Data, within obvContext: ObvContext) throws {
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        guard let groupJoined = try ContactGroupJoined.get(groupUid: groupUid, groupOwnerCryptoIdentity: groupOwner, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }
        try groupJoined.updatePhoto(withData: photo, ofDetailsWithVersion: version, delegateManager: delegateManager, within: obvContext)
    }
    
    
    public func updateDownloadedPhotoOfContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, version: Int, photo: Data, within obvContext: ObvContext) throws {
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }
        try groupOwned.updatePhoto(withData: photo, ofDetailsWithVersion: version, delegateManager: delegateManager, within: obvContext)
    }
    
    
    public func trustPublishedDetailsOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard let groupJoined = try ContactGroupJoined.get(groupUid: groupUid, groupOwnerCryptoIdentity: groupOwner, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }
        
        try groupJoined.trustDetailsPublished(within: obvContext, delegateManager: delegateManager)
        
    }
    
    
    public func updateLatestDetailsOfContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, with newGroupDetails: GroupDetailsElementsWithPhoto, within obvContext: ObvContext) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }
        
        try groupOwned.updateDetailsLatest(with: newGroupDetails, delegateManager: delegateManager)
    }
    
    
    public func setPhotoServerKeyAndLabelForContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws -> PhotoServerKeyAndLabel {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
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
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }
        try groupOwned.discardDetailsLatest(delegateManager: delegateManager)
    }
    
    
    public func publishLatestDetailsOfContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws {
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }
        try groupOwned.publishDetailsLatest(delegateManager: delegateManager)
    }
    
    
    public func updatePendingMembersAndGroupMembersOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, groupMembers: Set<CryptoIdentityWithCoreDetails>, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, groupMembersVersion: Int, within obvContext: ObvContext) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard let groupJoined = try ContactGroupJoined.get(groupUid: groupUid, groupOwnerCryptoIdentity: groupOwner, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }
        
        try groupJoined.updatePendingMembersAndGroupMembers(groupMembersWithCoreDetails: groupMembers,
                                                            pendingMembersWithCoreDetails: pendingGroupMembers,
                                                            groupMembersVersion: groupMembersVersion,
                                                            delegateManager: delegateManager,
                                                            flowId: obvContext.flowId)
        
    }
    
    
    public func updatePendingMembersAndGroupMembersOfContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupMembers: Set<CryptoIdentityWithCoreDetails>, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, groupMembersVersion: Int, within obvContext: ObvContext) throws {

        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }

        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }

        try groupOwned.updatePendingMembersAndGroupMembers(groupMembersWithCoreDetails: groupMembers,
                                                           pendingMembersWithCoreDetails: pendingGroupMembers,
                                                           groupMembersVersion: groupMembersVersion,
                                                           delegateManager: delegateManager,
                                                           flowId: obvContext.flowId)
        
    }
    
    
    /// When a contact deletes her owned identity, this method gets called to delete this identity from groups v1 that we joined, without waiting for a group update from the group owner.
    public func removeContactFromPendingAndGroupMembersOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupOwner: ObvCryptoIdentity, groupUid: UID, contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }

        guard let groupJoined = try ContactGroupJoined.get(groupUid: groupUid, groupOwnerCryptoIdentity: groupOwner, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }

        try groupJoined.removeContactFromPendingAndGroupMembers(contactCryptoIdentity: contactIdentity)
        
    }

    
    public func getGroupOwnedStructure(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws -> GroupStructure? {
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            return nil
        }
        return try groupOwned.getOwnedGroupStructure(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
    }

    
    public func getGroupJoinedStructure(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> GroupStructure? {
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        guard let groupJoined = try ContactGroupJoined.get(groupUid: groupUid, groupOwnerCryptoIdentity: groupOwner, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            // When the group cannot be found, we return nil to indicate that this is the case.
            return nil
        }
        return try groupJoined.getJoinedGroupStructure(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
    }
    
    
    public func getAllGroupStructures(ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Set<GroupStructure> {
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        let groups = try ContactGroup.getAll(ownedIdentity: ownedIdentityObject, delegateManager: delegateManager)
        let groupStructures = Set(try groups.map({ try $0.getGroupStructure(identityPhotosDirectory: delegateManager.identityPhotosDirectory) }))
        return groupStructures
    }

    
    public func getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: ObvCryptoIdentity, groupUid: UID, within obvContext: ObvContext) throws -> GroupInformationWithPhoto {

        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }

        let groupInformationWithPhoto = try groupOwned.getPublishedOwnedGroupInformationWithPhoto(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
        return groupInformationWithPhoto
    }

    
    public func getGroupJoinedInformationAndPublishedPhoto(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> GroupInformationWithPhoto {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard let groupJoined = try ContactGroupJoined.get(groupUid: groupUid, groupOwnerCryptoIdentity: groupOwner, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }
        
        let groupInformationWithPhoto = try groupJoined.getPublishedJoinedGroupInformationWithPhoto(identityPhotosDirectory: delegateManager.identityPhotosDirectory)

        return groupInformationWithPhoto
        
    }

    public func deleteContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard let groupJoined = try ContactGroupJoined.get(groupUid: groupUid, groupOwnerCryptoIdentity: groupOwner, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            return
        }
        
        try groupJoined.delete(delegateManager: delegateManager)
        
    }
    
    
    public func deleteContactGroupOwned(ownedIdentity: ObvCryptoIdentity, groupUid: UID, deleteEvenIfGroupMembersStillExist: Bool, within obvContext: ObvContext) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard let groupOwned = try ContactGroupOwned.get(groupUid: groupUid, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            return
        }

        if !deleteEvenIfGroupMembersStillExist {
            guard groupOwned.groupMembers.isEmpty && groupOwned.pendingGroupMembers.isEmpty else {
                throw ObvIdentityManagerError.ownedContactGroupStillHasMembersOrPendingMembers
            }
        }
        
        try groupOwned.delete(delegateManager: delegateManager)
        
    }

    
    /// This method is exclusively called from the ProcessInvitationStep of the GroupInvitationProtocol.
    public func forceUpdateOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, authoritativeGroupInformation: GroupInformation, within obvContext: ObvContext) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }

        guard let groupJoined = try ContactGroupJoined.get(groupUid: authoritativeGroupInformation.groupUid,
                                                           groupOwnerCryptoIdentity: authoritativeGroupInformation.groupOwnerIdentity,
                                                           ownedIdentity: ownedIdentityObject,
                                                           delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }

        try groupJoined.resetGroupDetailsWithAuthoritativeDetailsIfRequired(
            authoritativeGroupInformation.groupDetailsElements,
            delegateManager: delegateManager,
            within: obvContext)
        
    }
    
    
    public func resetGroupMembersVersionOfContactGroupJoined(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        guard let ownedIdentityObject = try OwnedIdentity.get(ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.cryptoIdentityIsNotOwned
        }
        
        guard let groupJoined = try ContactGroupJoined.get(groupUid: groupUid, groupOwnerCryptoIdentity: groupOwner, ownedIdentity: ownedIdentityObject, delegateManager: delegateManager) else {
            throw ObvIdentityManagerError.groupDoesNotExist
        }

        try groupJoined.resetGroupMembersVersionOfContactGroupJoined()
        
    }

    // MARK: - User Data

    public func getAllServerDataToSynchronizeWithServer(within obvContext: ObvContext) throws -> (toDelete: Set<UserData>, toRefresh: Set<UserData>) {
        let ownedIdentities = try OwnedIdentity.getAll(restrictToActive: true, delegateManager: delegateManager, within: obvContext)
        
        let now = Date()
        var toDelete = Set<UserData>()
        var toRefresh = Set<UserData>()

        for ownedIdentity in ownedIdentities {
            let labelsToKeep = try getLabelsOfServerUserDataToKeepOnServer(ownedIdentity: ownedIdentity)
            let serverUserDatas = try ServerUserData.getAllServerUserDatas(for: ownedIdentity.cryptoIdentity, within: obvContext)
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
    /// - The labels corresponding to group v2 for which we are an administrator, and for which we were the one administrator to upload a profile picture.
    private func getLabelsOfServerUserDataToKeepOnServer(ownedIdentity: OwnedIdentity) throws -> Set<UID> {
        let ownedIdentityPhotoServerLabels = try OwnedIdentityDetailsPublished.getAllPhotoServerLabels(ownedIdentity: ownedIdentity)
        let ownedGroupPhotoServerLabels = try ContactGroupOwned.getAllContactGroupOwned(ownedIdentity: ownedIdentity, delegateManager: delegateManager)
            .map({ $0.publishedDetails })
            .compactMap({ $0.photoServerKeyAndLabel })
            .map({ $0.label })
        let administedGroupV2ServerLabels = try ContactGroupV2.getAllGroupIdsAndOwnedPhotoLabelsOfAdministratedGroups(ownedIdentity: ownedIdentity).map({ $0.label })
        let labelsToKeep = ownedIdentityPhotoServerLabels.union(Set(ownedGroupPhotoServerLabels)).union(administedGroupV2ServerLabels)
        return labelsToKeep
    }
    
    
    public func getServerUserData(for ownedIdentity: ObvCryptoIdentity, with label: UID, within obvContext: ObvContext) -> UserData? {
        let serverUserData = try? ServerUserData.getServerUserData(for: ownedIdentity, with: label, within: obvContext)
        return serverUserData?.toUserData()
    }

//    public func deleteUserData(for ownedIdentity: ObvCryptoIdentity, with label: UID, within obvContext: ObvContext) {
//        guard let userData = try? ServerUserData.getServerUserData(for: ownedIdentity, with: label, within: obvContext) else { return }
//        obvContext.delete(userData)
//    }
    
    public func deleteUserData(for ownedIdentity: ObvCryptoIdentity, with label: UID, flowId: FlowIdentifier) async throws {
        guard let contextCreator = delegateManager.contextCreator else {
            assertionFailure()
            throw ObvIdentityManagerError.contextCreatorIsNil
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { obvContext in
                do {
                    let serverUserData = try ServerUserData.getServerUserData(for: ownedIdentity, with: label, within: obvContext)
                    try serverUserData?.deleteServerUserData()
                    return continuation.resume(returning: ())
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }

//    public func updateUserDataNextRefreshTimestamp(for ownedIdentity: ObvCryptoIdentity, with label: UID, within obvContext: ObvContext) {
//        let userData = try? ServerUserData.getServerUserData(for: ownedIdentity, with: label, within: obvContext)
//        userData?.updateNextRefreshTimestamp()
//    }

    public func updateUserDataNextRefreshTimestamp(for ownedIdentity: ObvCryptoIdentity, with label: UID, flowId: FlowIdentifier) async throws {
        guard let contextCreator = delegateManager.contextCreator else {
            assertionFailure()
            throw ObvIdentityManagerError.contextCreatorIsNil
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { obvContext in
                do {
                    let serverUserData = try ServerUserData.getServerUserData(for: ownedIdentity, with: label, within: obvContext)
                    serverUserData?.updateNextRefreshTimestamp()
                    return continuation.resume(returning: ())
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    /// This method returns as soon as the owned identity is deleted from database.
    public func waitForOwnedIdentityDeletion(expectedOwnedCryptoId: ObvCryptoId, flowId: FlowIdentifier) async throws {
        let waiter = OwnedIdentityDeletionWaiter(expectedOwnedCryptoId: expectedOwnedCryptoId, identityManager: self, flowId: flowId)
        try await waiter.waitForOwnedIdentityDeletion()
    }
    
}


// MARK: - Implementing ObvKeyWrapperForIdentityDelegate


extension ObvIdentityManagerImplementation: ObvKeyWrapperForIdentityDelegate {
    
    public func wrap(_ key: AuthenticatedEncryptionKey, for identity: ObvCryptoIdentity, randomizedWith prng: PRNGService) -> EncryptedData? {
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
    
    
    public func wrap(_ messageKey: any AuthenticatedEncryptionKey, forRemoteDeviceUID uid: UID, ofRemoteCryptoId remoteCryptoId: ObvCryptoIdentity, ofOwnedCryptoId ownedCryptoId: ObvCryptoIdentity, randomizedWith prng: any PRNGService, within obvContext: ObvContext) throws -> EncryptedData? {
        
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoId, delegateManager: delegateManager, within: obvContext) else {
            assertionFailure()
            return nil
        }
        
        let wrappedMessageKeys = try ownedIdentity.wrap(messageKey,
                                                        forRemoteDeviceUID: uid,
                                                        ofRemoteCryptoId: remoteCryptoId,
                                                        prng: prng,
                                                        delegateManager: delegateManager)
        
        return wrappedMessageKeys
        
    }
    
    
    public func unwrapWithPreKey(_ wrappedMessageKey: EncryptedData, forOwnedIdentity ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ResultOfUnwrapWithPreKey {
        
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoId, delegateManager: delegateManager, within: obvContext) else {
            assertionFailure()
            return .couldNotUnwrap
        }

        return try ownedIdentity.unwrapForCurrentOwnedDevice(wrappedMessageKey, delegateManager: delegateManager, within: obvContext)
        
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

    
    public func solveChallenge(_ challengeType: ChallengeType, with authenticationKeyPair: (publicKey: any PublicKeyForAuthentication, privateKey: any PrivateKeyForAuthentication), using: any PRNGService) throws -> Data {
        
        guard let response = ObvSolveChallengeStruct.solveChallenge(challengeType,
                                                                    with: authenticationKeyPair.privateKey,
                                                                    and: authenticationKeyPair.publicKey,
                                                                    using: prng)
        else {
            os_log("Could not compute the challenge's response", log: log, type: .error)
            throw makeError(message: "Could not compute the challenge's response")
        }
        
        return response

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
            guard let contactCryptoIdentity = contact.cryptoIdentity else { assertionFailure(); return }
            result[contactCryptoIdentity] = contact.allCapabilities
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


// MARK: - API related to sync between owned devices

extension ObvIdentityManagerImplementation {
    
    public func processSyncAtom(_ syncAtom: ObvSyncAtom, ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvIdentityManagerError.ownedIdentityNotFound
        }
        try ownedIdentity.processSyncAtom(syncAtom, delegateManager: delegateManager)
    }
    
}


// MARK: - Getting informations about missing photos

extension ObvIdentityManagerImplementation {
    
    /// The user can request the (re)download of missing photos for her contacts. This is a helper method returnings the required informations about all the contacts that have a photoFilename that points to an URL on disk where no photo can be found. The engine uses this method to request the (re)download of all photos corresponding to the returned informations.
    public func getInformationsAboutContactsWithMissingContactPictureOnDisk(within obvContext: ObvContext) throws -> [(ownedCryptoId: ObvCryptoIdentity, contactCryptoId: ObvCryptoIdentity, contactIdentityDetailsElements: IdentityDetailsElements)] {
        
        let identityPhotosDirectory = delegateManager.identityPhotosDirectory
        let contatInfos = try ContactIdentityDetails.getInfosAboutContactsHavingPhotoFilename(identityPhotosDirectory: identityPhotosDirectory, within: obvContext)
        
        let allPhotoURLOnDisk = try getAllPhotoURLOnDisk()
        
        let contatInfosWithMissingPhotoOnDisk = contatInfos.filter { info in
            return !allPhotoURLOnDisk.contains(info.photoURL)
        }
        
        return contatInfosWithMissingPhotoOnDisk.map { infos in
            (infos.ownedCryptoId, infos.contactCryptoId, infos.contactIdentityDetailsElements)
        }
        
    }
    
    
    public func getInformationsAboutOwnedIdentitiesWithMissingPictureOnDisk(within obvContext: ObvContext) throws -> [(ownedCryptoId: ObvCryptoIdentity, ownedIdentityDetailsElements: IdentityDetailsElements)] {
     
        let identityPhotosDirectory = delegateManager.identityPhotosDirectory
        let ownedInfos = try OwnedIdentityDetailsPublished.getInfosAboutOwnedIdentitiesHavingPhotoFilename(identityPhotosDirectory: identityPhotosDirectory, within: obvContext)
        
        let allPhotoURLOnDisk = try getAllPhotoURLOnDisk()
        
        let ownedInfosWithMissingPhotoOnDisk = ownedInfos.filter { info in
            return !allPhotoURLOnDisk.contains(info.photoURL)
        }
        
        return ownedInfosWithMissingPhotoOnDisk.map { infos in
            (infos.ownedCryptoId, infos.ownedIdentityDetailsElements)
        }

    }

    
    /// The user can request the (re)download of missing photos for her groups v1. This is a helper method returnings the required informations about all the groups that have a photoFilename that points to an URL on disk where no photo can be found. The engine uses this method to request the (re)download of all photos corresponding to the returned informations.
    public func getInformationsAboutGroupsV1WithMissingContactPictureOnDisk(within obvContext: ObvContext) throws -> [(ownedIdentity: ObvCryptoIdentity, groupInfo: GroupInformation)] {
        
        let identityPhotosDirectory = delegateManager.identityPhotosDirectory
        let groupInfos = try ContactGroupDetails.getInfosAboutGroupsHavingPhotoFilename(identityPhotosDirectory: identityPhotosDirectory, within: obvContext)
        
        let allPhotoURLOnDisk = try getAllPhotoURLOnDisk()
        
        let groupInfosWithMissingPhotoOnDisk = groupInfos.filter { info in
            return !allPhotoURLOnDisk.contains(info.photoURL)
        }

        return groupInfosWithMissingPhotoOnDisk.map { infos in
            (infos.ownedIdentity, infos.groupInformation)
        }
        
    }
    
    
    /// The user can request the (re)download of missing photos for her groups v2. This is a helper method returnings the required informations about all the groups that have a photoFilename that points to an URL on disk where no photo can be found. The engine uses this method to request the (re)download of all photos corresponding to the returned informations.
    public func getInformationsAboutGroupsV2WithMissingContactPictureOnDisk(within obvContext: ObvContext) throws -> [(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, serverPhotoInfo: GroupV2.ServerPhotoInfo)] {
        
        let identityPhotosDirectory = delegateManager.identityPhotosDirectory
        let groupInfos = try ContactGroupV2Details.getInfosAboutGroupsHavingPhotoFilename(identityPhotosDirectory: identityPhotosDirectory, within: obvContext)
        
        let allPhotoURLOnDisk = try getAllPhotoURLOnDisk()
        
        let groupInfosWithMissingPhotoOnDisk = groupInfos.filter { info in
            return !allPhotoURLOnDisk.contains(info.photoURL)
        }

        return groupInfosWithMissingPhotoOnDisk.map { infos in
            (infos.ownedIdentity, infos.groupIdentifier, infos.serverPhotoInfo)
        }

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
            guard let delegate = delegate as? ObvCreateContextDelegate else {
                assertionFailure()
                throw Self.makeError(message: "Could not initiate ObvCreateContextDelegate")
            }
            delegateManager.contextCreator = delegate
        case .ObvNotificationDelegate:
            guard let delegate = delegate as? ObvNotificationDelegate else {
                assertionFailure()
                throw Self.makeError(message: "Could not initiate ObvNotificationDelegate")
            }
            delegateManager.notificationDelegate = delegate
        case .ObvNetworkFetchDelegate:
            guard let delegate = delegate as? ObvNetworkFetchDelegate else {
                assertionFailure()
                throw Self.makeError(message: "Could not initiate ObvNetworkFetchDelegate")
            }
            delegateManager.networkFetchDelegate = delegate
        default:
            assertionFailure()
            throw Self.makeError(message: "Unexpected case")
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
    
    
    private func getAllPhotoURLOnDisk() throws -> Set<URL> {
        Set(
            try FileManager.default.contentsOfDirectory(at: self.identityPhotosDirectory, includingPropertiesForKeys: nil)
                .map({ $0.resolvingSymlinksInPath() })
        )
    }
    
    
    private func pruneOldKeycloakRevokedIdentityAndUncertifyExpiredSignedContactDetails(flowId: FlowIdentifier) {
        
        guard let contextCreator = delegateManager.contextCreator else { assertionFailure(); return }
        let log = self.log

        contextCreator.performBackgroundTask(flowId: flowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            do {
                let ownedIdentities = try OwnedIdentity.getAll(restrictToActive: false, delegateManager: _self.delegateManager, within: obvContext)
                let managedOwnedIdentities = ownedIdentities.filter({ $0.isKeycloakManaged })
                managedOwnedIdentities.forEach { ownedIdentity in
                    ownedIdentity.pruneOldKeycloakRevokedContacts(delegateManager: _self.delegateManager)
                    ownedIdentity.uncertifyExpiredSignedContactDetails(delegateManager: _self.delegateManager)
                }
                if obvContext.context.hasChanges {
                    try obvContext.save(logOnFailure: log)
                }
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
    
    
    /// Early implementations of group v2 did not create ServerUserData for uploaded groupV2 profile picture. This was a bug. This method, launched during bootstrap, create those missing ServerUserData.
    private func createMissingGroupV2ServerUserData(flowId: FlowIdentifier) {
        
        guard let contextCreator = delegateManager.contextCreator else { assertionFailure(); return }
        let delegateManager = self.delegateManager
        let log = self.log

        contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
            
            do {
                
                let ownedIdentities = try OwnedIdentity.getAll(restrictToActive: true, delegateManager: delegateManager, within: obvContext)
                
                for ownedIdentity in ownedIdentities {
                    
                    // Get all group ids and associated photo server labels such that
                    // - we are an admin of the group
                    // - we are the profile picture uploader
                    
                    let groupIdsAndPhotoServerLabels = try ContactGroupV2.getAllGroupIdsAndOwnedPhotoLabelsOfAdministratedGroups(ownedIdentity: ownedIdentity)
                    
                    // For all these groupIds/labels, make sure
                    
                    for (groupIdentifier, label) in groupIdsAndPhotoServerLabels {
                        
                        _ = try GroupV2ServerUserData.getOrCreateIfRequiredForAdministratedGroupV2Details(
                            ownedIdentity: ownedIdentity.cryptoIdentity,
                            label: label,
                            groupIdentifier: groupIdentifier,
                            nextRefreshTimestampOnCreation: Date.distantPast, // Force a refresh as soon as possible
                            within: obvContext)
                        
                    }

                    guard obvContext.context.hasChanges else { return }
                    try obvContext.save(logOnFailure: log)

                }
                
            } catch {
                os_log("Could not create missing GroupV2ServerUserData: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
            
        }
        
    }
    
}


// MARK: - Helper actor used during an owned identity deletion

/// This helper actor allows to await the identity manager's notification sent when an OwnedIdentity gets deleted from database.
private actor OwnedIdentityDeletionWaiter: OwnedIdentityObserver {
    
    private weak var identityManager: ObvIdentityManagerImplementation?
    private let expectedOwnedCryptoId: ObvCryptoId
    private let flowId: FlowIdentifier

    private var notificationToken: (any NSObjectProtocol)?
    private var continuation: CheckedContinuation<Void, any Error>?
    
    init(expectedOwnedCryptoId: ObvCryptoId, identityManager: ObvIdentityManagerImplementation, flowId: FlowIdentifier) {
        self.identityManager = identityManager
        self.expectedOwnedCryptoId = expectedOwnedCryptoId
        self.flowId = flowId
    }
    
    private func getAndRemoveContinuation() -> CheckedContinuation<Void, any Error>? {
        guard let continuationToReturn = self.continuation else { return nil }
        self.continuation = nil
        return continuationToReturn
    }
    
    private func unsubscribeFromNotification() {
        notificationToken = nil
    }
    
    func waitForOwnedIdentityDeletion() async throws {
        
        guard let identityManager else { throw ObvError.identityManagerIsNil }
        
        await OwnedIdentity.addObvObserver(self)
        
        guard try await identityManager.ownedIdentityExistsOnThisDevice(ownedCryptoId: expectedOwnedCryptoId, flowId: flowId) else { return }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            Task {
                do {
                    guard try await identityManager.ownedIdentityExistsOnThisDevice(ownedCryptoId: expectedOwnedCryptoId, flowId: flowId) else {
                        return continuation.resume()
                    }
                    self.continuation = continuation
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
            
        }
    }
    
    /// Called by the OwnedIdentity database when an owned identity gets deleted
    func anOwnedIdentityWasDeleted(deletedOwnedCryptoId: ObvCryptoIdentity) async {
        guard deletedOwnedCryptoId.getIdentity() == expectedOwnedCryptoId.getIdentity() else { return }
        let continuation = self.getAndRemoveContinuation()
        continuation?.resume()
    }
    
    
    enum ObvError: Error {
        case identityManagerIsNil
    }
    
}

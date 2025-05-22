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
import ObvTypes
import ObvMetaManager
import OlvidUtils
import ObvEncoder
import ObvCrypto
import os.log


public final class ObvSyncSnapshotManagerImplementation: ObvSyncSnapshotDelegate {
        
    private weak var appSnapshotableObject: (any ObvAppSnapshotable)?
    private weak var identitySnapshotableObject: (any ObvIdentityManagerSnapshotable)?
    
    public init() {
    }
    
    
    // MARK: - ObvManager
    
    private static let defaultLogSubsystem = "io.olvid.syncSnapshot"
    public private(set) var logSubsystem = ObvSyncSnapshotManagerImplementation.defaultLogSubsystem
    
    public func prependLogSubsystem(with prefix: String) {
        logSubsystem = [prefix, Self.defaultLogSubsystem].joined(separator: ".")
    }
    
    public func fulfill(requiredDelegate delegate: AnyObject, forDelegateType delegateType: ObvEngineDelegateType) throws {
    }
    
    
    public var requiredDelegates: [ObvEngineDelegateType] {
        return []
    }
    
    
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {
    }
    
    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {
        assert(appSnapshotableObject != nil, "registerAppSnapshotableObject(_:) should have been called by now")
        assert(identitySnapshotableObject != nil, "registerIdentitySnapshotableObject(_:) should have been called by now")
    }
    
    
    // MARK: - ObvSyncSnapshotDelegate
        
    public func parseDeviceBackup(deviceBackupToParse: DeviceBackupToParse, flowId: FlowIdentifier) throws -> ObvDeviceBackupFromServer {
        
        guard let identitySnapshotableObject else {
            throw ObvError.identitySnapshotableObjectIsNil
        }

        let deviceSnapshot = try self.decodeSyncSnapshot(from: deviceBackupToParse.deviceBackupSnapshot, context: .backupDevice)
        
        let partialDeviceBackupFromServer = try identitySnapshotableObject.parseDeviceSnapshotNode(identityNode: deviceSnapshot.identityNode, version: deviceBackupToParse.version, flowId: flowId)
        
        let deviceBackupFromServer = partialDeviceBackupFromServer.withAppNode(deviceSnapshot.appNode)
        
        return deviceBackupFromServer

    }
    
    
    public func parseProfileBackup(profileCryptoId: ObvCryptoId, profileBackupToParse: ProfileBackupToParse, flowId: FlowIdentifier) async throws -> ObvProfileBackupFromServer {
        
        guard let identitySnapshotableObject else {
            throw ObvError.identitySnapshotableObjectIsNil
        }

        let profileSnapShot: ObvSyncSnapshot = try self.decodeSyncSnapshot(from: profileBackupToParse.profileBackupSnapshot.profileSnapshotNode, context: .backupProfile(ownedCryptoId: profileCryptoId))
        
        let parsedData: ObvProfileBackupFromServer.DataObtainedByParsingIdentityNode = try await identitySnapshotableObject.parseProfileSnapshotNode(identityNode: profileSnapShot.identityNode, flowId: flowId)
        
        let profileExistsOnThisDevice: Bool = try await identitySnapshotableObject.ownedIdentityExistsOnThisDevice(ownedCryptoId: profileCryptoId, flowId: flowId)
        
        let profileBackupFromServer: ObvProfileBackupFromServer = ObvProfileBackupFromServer(ownedCryptoId: profileCryptoId,
                                                                                             profileExistsOnThisDevice: profileExistsOnThisDevice,
                                                                                             parsedData: parsedData,
                                                                                             identityNode: profileSnapShot.identityNode,
                                                                                             appNode: profileSnapShot.appNode,
                                                                                             additionalInfosForProfileBackup: profileBackupToParse.profileBackupSnapshot.additionalInfosForProfileBackup,
                                                                                             creationDate: profileBackupToParse.profileBackupSnapshot.creationDate,
                                                                                             backupSeed: profileBackupToParse.backupSeed,
                                                                                             threadUID: profileBackupToParse.threadUID,
                                                                                             backupVersion: profileBackupToParse.version,
                                                                                             backupMadeByThisDevice: profileBackupToParse.backupMadeByThisDevice)

        return profileBackupFromServer
        
    }
    

    public func registerAppSnapshotableObject(_ appSnapshotableObject: ObvAppSnapshotable) {
        assert(self.appSnapshotableObject == nil, "We do not expect this method to be called twice")
        self.appSnapshotableObject = appSnapshotableObject
    }
    
    
    public func registerIdentitySnapshotableObject(_ identitySnapshotableObject: ObvIdentityManagerSnapshotable) {
        assert(self.identitySnapshotableObject == nil, "We do not expect this method to be called twice")
        self.identitySnapshotableObject = identitySnapshotableObject
    }

    
    private func getSyncSnapshotNode(context: ObvSyncSnapshot.Context) throws -> ObvSyncSnapshot {
        
        guard let appSnapshotableObject else {
            throw ObvError.appSnapshotableObjectIsNil
        }

        guard let identitySnapshotableObject else {
            throw ObvError.identitySnapshotableObjectIsNil
        }

        return try ObvSyncSnapshot(context: context,
                                   appSnapshotableObject: appSnapshotableObject,
                                   identitySnapshotableObject: identitySnapshotableObject)

    }

    
    public func getSyncSnapshotNodeAsObvDictionary(context: ObvSyncSnapshot.Context) throws -> ObvDictionary {
        
        guard let appSnapshotableObject else {
            throw ObvError.appSnapshotableObjectIsNil
        }

        guard let identitySnapshotableObject else {
            throw ObvError.identitySnapshotableObjectIsNil
        }
        
        let syncSnapshotNode = try getSyncSnapshotNode(context: context)
        let obvDict = try syncSnapshotNode.toObvDictionary(appSnapshotableObject: appSnapshotableObject, identitySnapshotableObject: identitySnapshotableObject)
        
        return obvDict
        
    }
    
    public func decodeSyncSnapshot(from obvDictionary: ObvDictionary, context: ObvSyncSnapshot.Context) throws -> ObvSyncSnapshot {
        
        guard let appSnapshotableObject else {
            throw ObvError.appSnapshotableObjectIsNil
        }

        guard let identitySnapshotableObject else {
            throw ObvError.identitySnapshotableObjectIsNil
        }

        return try ObvSyncSnapshot.fromObvDictionary(obvDictionary,
                                                     appSnapshotableObject: appSnapshotableObject,
                                                     identitySnapshotableObject: identitySnapshotableObject,
                                                     context: context)
        
    }
    
    
    public func syncEngineDatabaseThenUpdateAppDatabase(using obvSyncSnapshotNode: any ObvSyncSnapshotNode) async throws {
        try await appSnapshotableObject?.syncEngineDatabaseThenUpdateAppDatabase(using: obvSyncSnapshotNode)
    }
    
    
    public func requestServerToKeepDeviceActive(ownedCryptoId: ObvCryptoId, deviceUidToKeepActive: UID) async throws {
        try await appSnapshotableObject?.requestServerToKeepDeviceActive(ownedCryptoId: ownedCryptoId, deviceUidToKeepActive: deviceUidToKeepActive)
    }
    
    
    public func getAdditionalInfosForProfileBackup(ownedCryptoId: ObvCryptoId, flowId: FlowIdentifier) async throws -> AdditionalInfosForProfileBackup {
        
        guard let appSnapshotableObject else {
            throw ObvError.appSnapshotableObjectIsNil
        }

        guard let identitySnapshotableObject else {
            throw ObvError.identitySnapshotableObjectIsNil
        }

        let additionalInfosFromAppForProfileBackup = try await appSnapshotableObject.getAdditionalInfosFromAppForProfileBackup(ownedCryptoId: ownedCryptoId)
        let additionalInfosFromIdentityManagerForProfileBackup = try await identitySnapshotableObject.getAdditionalInfosFromIdentityManagerForProfileBackup(ownedCryptoId: ownedCryptoId, flowId: flowId)
        
        let additionalInfosForProfileBackup = AdditionalInfosForProfileBackup(nameOfDeviceWhichPerformedBackup: additionalInfosFromIdentityManagerForProfileBackup.deviceDisplayName,
                                                                              platformOfDeviceWhichPerformedBackup: additionalInfosFromAppForProfileBackup.platform)
        
        return additionalInfosForProfileBackup
        
    }

    // MARK: ObvError
    
    enum ObvError: Error {
        case appSnapshotableObjectIsNil
        case identitySnapshotableObjectIsNil
    }

}

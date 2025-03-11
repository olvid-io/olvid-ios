/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
    private weak var identitySnapshotableObject: (any ObvSnapshotable)?
    
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
        
    
    public func registerAppSnapshotableObject(_ appSnapshotableObject: ObvAppSnapshotable) {
        assert(self.appSnapshotableObject == nil, "We do not expect this method to be called twice")
        self.appSnapshotableObject = appSnapshotableObject
    }
    
    
    public func registerIdentitySnapshotableObject(_ identitySnapshotableObject: ObvSnapshotable) {
        assert(self.identitySnapshotableObject == nil, "We do not expect this method to be called twice")
        self.identitySnapshotableObject = identitySnapshotableObject
    }

    
    public func getSyncSnapshotNode(for ownedCryptoId: ObvCryptoId) throws -> ObvSyncSnapshot {

        guard let appSnapshotableObject else {
            throw ObvError.appSnapshotableObjectIsNil
        }

        guard let identitySnapshotableObject else {
            throw ObvError.identitySnapshotableObjectIsNil
        }

        return try ObvSyncSnapshot(ownedCryptoId: ownedCryptoId, appSnapshotableObject: appSnapshotableObject, identitySnapshotableObject: identitySnapshotableObject)

    }
    
    
    public func getSyncSnapshotNodeAsObvDictionary(for ownedCryptoId: ObvCryptoId) throws -> ObvDictionary {
        
        guard let appSnapshotableObject else {
            throw ObvError.appSnapshotableObjectIsNil
        }

        guard let identitySnapshotableObject else {
            throw ObvError.identitySnapshotableObjectIsNil
        }
        
        let syncSnapshotNode = try getSyncSnapshotNode(for: ownedCryptoId)
        let obvDict = try syncSnapshotNode.toObvDictionary(appSnapshotableObject: appSnapshotableObject, identitySnapshotableObject: identitySnapshotableObject)
        
        return obvDict
        
    }
    
    public func decodeSyncSnapshot(from obvDictionary: ObvDictionary) throws -> ObvSyncSnapshot {
        
        guard let appSnapshotableObject else {
            throw ObvError.appSnapshotableObjectIsNil
        }

        guard let identitySnapshotableObject else {
            throw ObvError.identitySnapshotableObjectIsNil
        }

        return try ObvSyncSnapshot.fromObvDictionary(obvDictionary, appSnapshotableObject: appSnapshotableObject, identitySnapshotableObject: identitySnapshotableObject)
        
    }
    
    
    public func syncEngineDatabaseThenUpdateAppDatabase(using obvSyncSnapshotNode: any ObvSyncSnapshotNode) async throws {
        try await appSnapshotableObject?.syncEngineDatabaseThenUpdateAppDatabase(using: obvSyncSnapshotNode)
    }
    
    
    public func requestServerToKeepDeviceActive(ownedCryptoId: ObvCryptoId, deviceUidToKeepActive: UID) async throws {
        try await appSnapshotableObject?.requestServerToKeepDeviceActive(ownedCryptoId: ownedCryptoId, deviceUidToKeepActive: deviceUidToKeepActive)
    }

    // MARK: ObvError
    
    enum ObvError: Error {
        case appSnapshotableObjectIsNil
        case identitySnapshotableObjectIsNil
    }

}

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
import ObvBackupManagerNew
import ObvMetaManager
import ObvCrypto
import ObvTypes
import ObvEncoder
import OlvidUtils


extension ObvEngine: ObvBackupManagerNewDelegate {
            
    public func solveChallengeForBackupUpload(_ backupManager: ObvBackupManagerNew, backupKeyUID: ObvCrypto.UID, deviceOrProfileBackupThreadUID: ObvCrypto.UID, backupVersion: Int, encryptedBackup: ObvCrypto.EncryptedData, authenticationKeyPair: (publicKey: any PublicKeyForAuthentication, privateKey: any PrivateKeyForAuthentication)) async throws -> Data {
        
        guard let solveChallengeDelegate else { assertionFailure(); throw ObvError.solveChallengeDelegateIsNil }
        
        let challengeResponse = try solveChallengeDelegate.solveChallenge(.backupUpload(backupKeyUID: backupKeyUID, deviceOrProfileBackupThreadUID: deviceOrProfileBackupThreadUID, backupVersion: backupVersion, encryptedBackup: encryptedBackup), with: authenticationKeyPair, using: prng)
        
        return challengeResponse
        
    }
    
    
    public func solveChallengeForBackupDelete(_ backupManager: ObvBackupManagerNew, backupKeyUID: UID, deviceOrProfileBackupThreadUID: UID, backupVersion: Int, authenticationKeyPair: (publicKey: any PublicKeyForAuthentication, privateKey: any PrivateKeyForAuthentication)) async throws -> Data {
        
        guard let solveChallengeDelegate else { assertionFailure(); throw ObvError.solveChallengeDelegateIsNil }

        let challengeResponse = try solveChallengeDelegate.solveChallenge(.backupDelete(backupKeyUID: backupKeyUID, deviceOrProfileBackupThreadUID: deviceOrProfileBackupThreadUID, backupVersion: backupVersion), with: authenticationKeyPair, using: prng)
        
        return challengeResponse
        
    }
    
    public func hasActiveOwnedIdentities(_ backupManager: ObvBackupManagerNew) async throws -> Bool {
        let ownedIdentities = try await getOwnedIdentities(restrictToActive: true)
        return !ownedIdentities.isEmpty
    }
    
    
    public func getDeviceSnapshotNodeAsObvDictionary(_ backupManager: ObvBackupManagerNew) async throws -> ObvEncoder.ObvDictionary {
     
        guard let syncSnapshotDelegate else {
            assertionFailure()
            throw ObvError.syncSnapshotDelegateIsNil
        }
        
        let deviceSnapshotNode = try syncSnapshotDelegate.getSyncSnapshotNodeAsObvDictionary(context: .backupDevice)
        
        return deviceSnapshotNode
        
    }

    
    public func getProfileSnapshotNodeAsObvDictionary(_ backupManager: ObvBackupManagerNew, ownedCryptoId: ObvCryptoId) async throws -> ObvEncoder.ObvDictionary {
     
        guard let syncSnapshotDelegate else {
            assertionFailure()
            throw ObvError.syncSnapshotDelegateIsNil
        }
        
        let deviceSnapshotNode = try syncSnapshotDelegate.getSyncSnapshotNodeAsObvDictionary(context: .backupProfile(ownedCryptoId: ownedCryptoId))
        
        return deviceSnapshotNode
        
    }


    public func getBackupSeedOfOwnedIdentity(_ backupManager: ObvBackupManagerNew, ownedCryptoId: ObvCryptoId, restrictToActive: Bool, flowId: FlowIdentifier) async throws -> BackupSeed? {
        
        guard let identityDelegate else { assertionFailure(); throw ObvError.identityDelegateIsNil }

        return try await identityDelegate.getBackupSeedOfOwnedIdentity(ownedCryptoId: ownedCryptoId, restrictToActive: restrictToActive, flowId: flowId)
        
    }
    
    
    public func getAdditionalInfosForProfileBackup(_ backupManager: ObvBackupManagerNew, ownedCryptoId: ObvCryptoId, flowId: FlowIdentifier) async throws -> AdditionalInfosForProfileBackup {
        
        guard let syncSnapshotDelegate else {
            assertionFailure()
            throw ObvError.syncSnapshotDelegateIsNil
        }
        
        let additionalInfosForProfileBackup = try await syncSnapshotDelegate.getAdditionalInfosForProfileBackup(ownedCryptoId: ownedCryptoId, flowId: flowId)
        
        return additionalInfosForProfileBackup

    }
    
    
    public func getAllActiveOwnedIdentities(_ backupManager: ObvBackupManagerNew, flowId: FlowIdentifier) async throws -> Set<ObvCryptoId> {
        
        let ownedCryptoIdentities = try await getOwnedIdentities(restrictToActive: true, flowId: flowId)

        return Set(ownedCryptoIdentities.map({ ObvCryptoId(cryptoIdentity: $0) }))
        
    }
    
    
    public func parseDeviceBackup(_ backupManager: ObvBackupManagerNew, deviceBackupToParse: DeviceBackupToParse, flowId: OlvidUtils.FlowIdentifier) async throws -> ObvTypes.ObvDeviceBackupFromServer {
        
        guard let syncSnapshotDelegate else {
            assertionFailure()
            throw ObvError.syncSnapshotDelegateIsNil
        }

        return try syncSnapshotDelegate.parseDeviceBackup(deviceBackupToParse: deviceBackupToParse, flowId: flowId)
                
    }
    
    
    public func parseProfileBackup(_ backupManager: ObvBackupManagerNew, profileCryptoId: ObvCryptoId, profileBackupToParse: ProfileBackupToParse, flowId: FlowIdentifier) async throws -> ObvProfileBackupFromServer {
        
        guard let syncSnapshotDelegate else {
            assertionFailure()
            throw ObvError.syncSnapshotDelegateIsNil
        }

        return try await syncSnapshotDelegate.parseProfileBackup(profileCryptoId: profileCryptoId, profileBackupToParse: profileBackupToParse, flowId: flowId)
        
    }
    
}



// MARK: - Helper for constructing an ObvDeviceBackupFromServer

//extension ObvDeviceBackupFromServer {
//    
//    init(appNode: (any ObvSyncSnapshotNode)?) {
//        
//    }
//    
//}

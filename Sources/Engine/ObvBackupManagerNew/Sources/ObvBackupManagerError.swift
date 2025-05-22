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


public struct ObvBackupManagerError {
    
    public enum CreateDeviceBackupSeed: Error {
        case unknownError
        case otherError(error: Error)
        case coreDataError(error: Error)
        case anActivePersistedDeviceBackupSeedAlreadyExists
        case keychain(error: Keychain)
        case getKeychainSecAttrAccount(error: GetDeviceActiveBackupSeedAndServerURL)
    }
    
    
    public enum DeletePersistedDeviceBackupSeed: Error {
        case unknownError
        case coreDataError(error: Error)
    }
    
    public enum GetDeviceActiveBackupSeedAndServerURL: Error {
        case unknownError
        case otherError(error: Error)
        case coreDataError(error: Error)
        case couldNotParseBackupSeed
        case couldNotParseServerURL
    }


    public enum Keychain: Error {
        case unhandledError(status: OSStatus)
    }
    
    
    public enum GetKeychainSecAttrAccount: Error {
        case unknownError
        case otherError(error: Error)
        case coreDataError(error: Error)
    }
    
    public enum DeactivateAllPersistedDeviceBackupSeeds: Error {
        case unknownError
        case coreDataError(error: Error)
    }
    
    public enum GetOrCreateProfileBackupThreadUIDForOwnedCryptoId: Error {
        case unknownError
        case coreDataError(error: Error)
    }
    
    
    
    enum CreateAndUploadProfileBackupTask: Error {
        case delegateIsNil
        case getOrCreateProfileBackupThreadUIDForOwnedCryptoId(error: GetOrCreateProfileBackupThreadUIDForOwnedCryptoId)
        case otherError(error: Error)
        case listBackupsOnServerError(error: ListBackupsOnServerError)
        case createBackupKeyUIDOnServerError(error: CreateBackupKeyUIDOnServerError)
        case failedToGetAdditionalInfosForProfileBackup(error: Error)
        case failedToCreateProfileSnapshotNode(error: Error)
        case encodingError(error: Error)
        case deviceBackupSnapshotSizeError
        case signatureGenerationFailed(error: Error)
        case uploadBackupToServerError(error: UploadBackupToServerError)
        case profileBackupSeedIsNil
    }
    
    
    enum CreateAndUploadDeviceBackupTask: Error {
        case delegateIsNil
        case deviceBackupSeedIsNil
        case getDeviceActiveBackupSeedAndServerURL(error: GetDeviceActiveBackupSeedAndServerURL)
        case delegateError(error: Error)
        case listBackupsOnServerError(error: ListBackupsOnServerError)
        case createBackupKeyUIDOnServerError(error: CreateBackupKeyUIDOnServerError)
        case failedToCreateDeviceSnapshotNode(error: Error)
        case deviceBackupSnapshotSizeError
        case signatureGenerationFailed(error: Error)
        case uploadBackupToServerError(error: UploadBackupToServerError)
    }
    

    public enum GetBackupParameterIsSynchronizedWithICloud: Error {
        case getKeychainSecAttrAccount(error: GetDeviceActiveBackupSeedAndServerURL)
        case keychain(error: Keychain)
        case secAttrAccountIsNil
    }
    
    public enum SetBackupParameterIsSynchronizedWithICloud: Error {
        case get(GetBackupParameterIsSynchronizedWithICloud)
        case keychain(error: Keychain)
        case getKeychainSecAttrAccount(error: GetDeviceActiveBackupSeedAndServerURL)
        case deviceBackupSeedIsNil
        case getDeviceActiveBackupSeedAndServerURL(error: GetDeviceActiveBackupSeedAndServerURL)
        case secAttrAccountIsNil
    }
    
    public enum EraseAndGenerateNewDeviceBackupSeed: Error {
        case getKeychainSecAttrAccount(error: GetDeviceActiveBackupSeedAndServerURL)
        case keychain(error: Keychain)
        case deactivateAllPersistedDeviceBackupSeeds(error: DeactivateAllPersistedDeviceBackupSeeds)
        case createDeviceBackupSeed(error: CreateDeviceBackupSeed)
        case secAttrAccountIsNil
    }
    
    public enum GetAllDeviceBackupSeedsFoundInKeychain: Error {
        case unhandledError(status: OSStatus)
    }
    
}

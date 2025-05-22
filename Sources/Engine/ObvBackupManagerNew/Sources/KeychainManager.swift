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
import ObvEncoder
import ObvTypes


struct KeychainManager {
    
    private let appGroupIdentifier: String // Also called sharedContainerIdentifier in other parts of the app
    
    init(appGroupIdentifier: String) {
        self.appGroupIdentifier = appGroupIdentifier
    }
    
    func getBackupParameterIsSynchronizedWithICloud(secAttrAccount: String) throws(ObvBackupManagerError.Keychain) -> Bool {
        
        let query = createQueryForSecItemCopyMatching(secAttrAccount: secAttrAccount, matchLimit: .one(doReturnData: false), doReturnAttributes: false)
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        switch status {
        case errSecItemNotFound:
            return false
        case errSecSuccess:
            return true
        default:
            assertionFailure()
            throw .unhandledError(status: status)
        }

    }
    
    
    func deleteDeviceBackupSeedFromKeychain(secAttrAccount: String) throws(ObvBackupManagerError.Keychain) {

        let query = createQueryForSecItemDelete(secAttrAccount: secAttrAccount)
        
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            assertionFailure()
            throw .unhandledError(status: status)
        }

    }


    /// Add the current physical device's backup seed to the keychain.
    /// - Parameters:
    ///   - backupSeed: The backup seed to add to the keychain
    ///   - bundleIdentifier: The app bundle identifier (currently, either io.olvid.messenger or io.olvid.messenger-debug)
    func saveOrUpdateCurrentDeviceBackupSeedToKeychain(secAttrAccount: String, backupSeedAndStorageServerURL: ObvBackupSeedAndStorageServerURL, physicalDeviceName: String) throws(ObvBackupManagerError.Keychain) {

        let query = createQueryForSecItemAdd(secAttrAccount: secAttrAccount, backupSeedAndStorageServerURL: backupSeedAndStorageServerURL, physicalDeviceName: physicalDeviceName)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        switch status {

        case errSecSuccess:
            
            return
            
        case errSecDuplicateItem:
            
            let attributesForQuery = Set([kSecClass, kSecAttrAccessGroup, kSecAttrAccount, kSecAttrService, kSecAttrSynchronizable])
            
            let newQuery = query.filter { element in
                return attributesForQuery.contains(element.key)
            } as CFDictionary
            
            let attributesToUpdate = query.filter { element in
                return !attributesForQuery.contains(element.key)
            } as CFDictionary
            
            let updateStatus = SecItemUpdate(newQuery, attributesToUpdate)
            
            switch updateStatus {
            case errSecSuccess:
                return
            default:
                assertionFailure("Update failed with status: \(updateStatus)")
                throw .unhandledError(status: updateStatus)
            }
            
        default:
            assertionFailure("Add failed with status: \(status)")
            throw .unhandledError(status: status)

        }
        
    }
    
    
    func getAllBackupSeedAndStorageServerURLFoundInKeychain() async throws(ObvBackupManagerError.GetAllDeviceBackupSeedsFoundInKeychain) -> Set<ObvBackupSeedAndStorageServerURL> {
        
        let query = createQueryForSecItemCopyMatching(secAttrAccount: nil, matchLimit: .all, doReturnAttributes: true)
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
                
        switch status {
            
        case errSecItemNotFound:
            
            return []
            
        case errSecSuccess:
            
            guard let items = item as? [AnyObject] else { assertionFailure(); return [] }
            let secAttrAccounts = items.compactMap({ $0[kSecAttrAccount] }).compactMap({ $0 as? String })
            
            var allDeviceBackupSeedAndStorageServerURL = Set<ObvBackupSeedAndStorageServerURL>()
            
            for secAttrAccount in secAttrAccounts {
                
                let query = createQueryForSecItemCopyMatching(secAttrAccount: secAttrAccount, matchLimit: .one(doReturnData: true), doReturnAttributes: true)
                
                var item: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &item)
                
                switch status {
                    
                case errSecItemNotFound:
                    
                    assertionFailure()
                    continue
                    
                case errSecSuccess:
                    
                    guard let secValueData = item?[kSecValueData] as? Data else { assertionFailure(); continue }
                    guard let secAttrGeneric = item?[kSecAttrGeneric] as? Data else { assertionFailure(); continue }
                    
                    guard let backupSeedAndStorageServerURL = ObvBackupSeedAndStorageServerURL(secValueData: secValueData, secAttrGeneric: secAttrGeneric) else { assertionFailure(); continue }

                    allDeviceBackupSeedAndStorageServerURL.insert(backupSeedAndStorageServerURL)
                    
                default:
                    assertionFailure()
                    continue
                }

            }
            
            return allDeviceBackupSeedAndStorageServerURL
            
        default:
            assertionFailure()
            throw .unhandledError(status: status)
        }

    }
    
}


// MARK: - Helpers for creating queries

extension KeychainManager {
    
    private enum MatchLimit {
        case one(doReturnData: Bool)
        case all
    }
    

    private func createQueryForSecItemAdd(secAttrAccount: String, backupSeedAndStorageServerURL: ObvBackupSeedAndStorageServerURL, physicalDeviceName: String) -> [CFString : Any] {
        
        var query = createQueryCompositePrimaryKey(secAttrAccount: secAttrAccount)

        // The following attributes don’t form part of its composite primary key
        // The kSecValueData is secret (encrypted) and may require the user to enter a password for access.

        let now = Date.now
        
        query[kSecAttrCreationDate] = now
        query[kSecAttrDescription] = "Olvid device backup seed of \(physicalDeviceName.prefix(64)) saved on \(now.formatted(date: .abbreviated, time: .shortened))"
        query[kSecAttrIsInvisible] = false
        
        let (secValueData, secAttrGeneric) = backupSeedAndStorageServerURL.toKeychainItemValues()
        
        query[kSecValueData] = secValueData
        query[kSecAttrGeneric] = secAttrGeneric
        
        return query
        
    }
    
    
    private func createQueryForSecItemDelete(secAttrAccount: String) -> [CFString : Any] {
        
        let query = createQueryCompositePrimaryKey(secAttrAccount: secAttrAccount)

        return query
        
    }
    
    
    private func createQueryForSecItemCopyMatching(secAttrAccount: String?, matchLimit: MatchLimit, doReturnAttributes: Bool) -> [CFString : Any] {
        
        var query = createQueryCompositePrimaryKey(secAttrAccount: secAttrAccount)
        
        switch matchLimit {
        case .one(doReturnData: let doReturnData):
            query[kSecMatchLimit] = kSecMatchLimitOne
            query[kSecReturnData] = doReturnData
        case .all:
            query[kSecMatchLimit] = kSecMatchLimitAll
            query[kSecReturnData] = false
        }
        
        query[kSecReturnAttributes] = doReturnAttributes

        return query
        
    }
    
    
    private func createQueryCompositePrimaryKey(secAttrAccount: String?) -> [CFString : Any] {
        
        let secAttrService = Bundle.main.bundleIdentifier ?? "io.olvid.messenger"
        
        var query: [CFString : Any]
        
        if let secAttrAccount {
            query = [
                kSecClass: kSecClassGenericPassword,
                // The following attributes form the composite primary key of a generic password item
                kSecAttrAccessGroup: self.appGroupIdentifier,
                kSecAttrAccount: secAttrAccount,
                kSecAttrService: secAttrService,
                kSecAttrSynchronizable: true,
            ]
        } else {
            query = [
                kSecClass: kSecClassGenericPassword,
                // The following attributes form the composite primary key of a generic password item
                kSecAttrAccessGroup: self.appGroupIdentifier,
                kSecAttrService: secAttrService,
                kSecAttrSynchronizable: true,
            ]
        }
        
        query[kSecUseDataProtectionKeychain] = true
        query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
        
        return query
    }
    
}



// MARK: - Private helpers

private extension ObvBackupSeedAndStorageServerURL {
    
    func toKeychainItemValues() -> (secValueData: Data, secAttrGeneric: Data) {
        
        let secValueData: Data
        if let data = self.backupSeed.description.data(using: .utf8) {
            secValueData = data
        } else {
            assertionFailure()
            secValueData = self.backupSeed.raw
        }

        let secAttrGeneric: Data
        if let data = self.serverURLForStoringDeviceBackup.absoluteString.data(using: .utf8) {
            secAttrGeneric = data
        } else {
            assertionFailure()
            secAttrGeneric = self.serverURLForStoringDeviceBackup.obvEncode().rawData
        }
                
        return (secValueData, secAttrGeneric)
        
    }
    
    init?(secValueData: Data, secAttrGeneric: Data) {
        
        let backupSeed: BackupSeed
        if let backupSeedDescription = String(data: secValueData, encoding: .utf8), let _backupSeed = BackupSeed(backupSeedDescription) {
            backupSeed = _backupSeed
        } else if let _backupSeed = BackupSeed(with: secValueData) {
            assertionFailure()
            backupSeed = _backupSeed
        } else {
            assertionFailure()
            return nil
        }
        
        let serverURLForStoringDeviceBackup: URL
        if let urlAsString = String(data: secAttrGeneric, encoding: .utf8), let url = URL(string: urlAsString) {
            serverURLForStoringDeviceBackup = url
        } else if let encodedURL = ObvEncoded(withRawData: secAttrGeneric), let url = URL(encodedURL) {
            assertionFailure()
            serverURLForStoringDeviceBackup = url
        } else {
            assertionFailure()
            return nil
        }
        
        self.init(backupSeed: backupSeed, serverURLForStoringDeviceBackup: serverURLForStoringDeviceBackup)
        
    }
    
}

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
import ObvTypes
import OlvidUtils
import ObvUICoreData
import ObvSettings


/// This singleton allows to store and fetch a `LatestCurrentOWnedIdentityStored` to and from the user defaults shared between the app and the app extensions.
/// If found the `LatestCurrentOWnedIdentityStored` always contains a `nonHiddenCryptoId` corresponding to the latest owned `cryptoId` used within the app.
/// It may also contain a `hiddenCryptoId` if the last current identity used within the app was a hidden one. Storing both allows to always have access to the latest non-hidden used owned identity, even of the latest current identity was hidden.
/// This is handdy when using these values in the share extension where we *never* want to show a hidden identity.
actor LatestCurrentOwnedIdentityStorage {
    
    static let shared = LatestCurrentOwnedIdentityStorage()
    
    private init() {}
    
    private let sharedUserDefaultsKey = ObvUICoreDataConstants.SharedUserDefaultsKey.latestCurrentOwnedIdentity.rawValue

    
    /// Returns the currently stored `LatestCurrentOWnedIdentityStored` if one is found. This structure contains at least the lates non hidden current owned identity and, if it exists, the latest hidden current owned identity.
    func getLatestCurrentOwnedIdentityStored() -> LatestCurrentOWnedIdentityStored? {
        guard let sharedUserDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { assertionFailure(); return nil }
        guard let serializedLatestCurrentOWnedIdentityStored = sharedUserDefaults.data(forKey: sharedUserDefaultsKey) else { return nil }
        guard let latestCurrentOWnedIdentityStored = try? LatestCurrentOWnedIdentityStored.jsonDecode(serializedLatestCurrentOWnedIdentityStored) else {
            removeLatestCurrentOWnedIdentityStored()
            assertionFailure()
            return nil
        }
        return latestCurrentOWnedIdentityStored
    }
    

    /// Returns the currently stored `LatestCurrentOWnedIdentityStored` if one is found. This structure contains at least the lates non hidden current owned identity and, if it exists, the latest hidden current owned identity.
    ///
    /// The difference with `getLatestCurrentOwnedIdentityStored()` is that this method does not delete the content of the user defaults if the json cannot be decoded.
    nonisolated
    func getLatestCurrentOwnedIdentityStoredSynchronously() -> LatestCurrentOWnedIdentityStored? {
        guard let sharedUserDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { assertionFailure(); return nil }
        guard let serializedLatestCurrentOWnedIdentityStored = sharedUserDefaults.data(forKey: sharedUserDefaultsKey) else { return nil }
        guard let latestCurrentOWnedIdentityStored = try? LatestCurrentOWnedIdentityStored.jsonDecode(serializedLatestCurrentOWnedIdentityStored) else { return nil }
        return latestCurrentOWnedIdentityStored
    }
    
    func storeLatestCurrentOwnedCryptoId(_ currentOwnedCryptoId: ObvCryptoId, isHidden: Bool) {
        if isHidden {
            storeLatestHiddenCurrentOwnedCryptoId(currentOwnedCryptoId)
        } else {
            storeLatestNonHiddenCurrentOwnedCryptoId(currentOwnedCryptoId)
        }
    }
    
    
    func removeLatestHiddenCurrentOWnedIdentityStored() {
        guard let latestCurrentOWnedIdentityStored = getLatestCurrentOwnedIdentityStored() else { return }
        let newCurrentOwnedIdentityStored = LatestCurrentOWnedIdentityStored(nonHiddenCryptoId: latestCurrentOWnedIdentityStored.nonHiddenCryptoId, hiddenCryptoId: nil)
        store(newCurrentOwnedIdentityStored: newCurrentOwnedIdentityStored)
    }
    
    
    func removeLatestCurrentOWnedIdentityStored() {
        guard let sharedUserDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { assertionFailure(); return }
        sharedUserDefaults.removeObject(forKey: sharedUserDefaultsKey)
    }

    
    // MARK: Private methods
    
    private func store(newCurrentOwnedIdentityStored: LatestCurrentOWnedIdentityStored) {
        guard let sharedUserDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { assertionFailure(); return }
        guard let newSerializedCurrentOWnedIdentityStored = try? newCurrentOwnedIdentityStored.jsonEncode() else {
            assertionFailure()
            removeLatestCurrentOWnedIdentityStored()
            return
        }
        sharedUserDefaults.setValue(newSerializedCurrentOWnedIdentityStored, forKey: sharedUserDefaultsKey)
    }

    
    /// Removes all previous `LatestCurrentOWnedIdentityStored` and sets one containing the received non hidden current owned identity.
    private func storeLatestNonHiddenCurrentOwnedCryptoId(_ currentOwnedCryptoId: ObvCryptoId) {
        let newCurrentOwnedIdentityStored = LatestCurrentOWnedIdentityStored(nonHiddenCryptoId: currentOwnedCryptoId, hiddenCryptoId: nil)
        store(newCurrentOwnedIdentityStored: newCurrentOwnedIdentityStored)
    }
        
    
    /// If a `LatestCurrentOWnedIdentityStored` is found, replaces the store hidden `ObvCryptoId` by the one received. If no `LatestCurrentOWnedIdentityStored` is found, this method does nothing.
    private func storeLatestHiddenCurrentOwnedCryptoId(_ currentOwnedCryptoId: ObvCryptoId) {
        let newCurrentOwnedIdentityStored: LatestCurrentOWnedIdentityStored
        if let latestCurrentOWnedIdentityStored = getLatestCurrentOwnedIdentityStored() {
            newCurrentOwnedIdentityStored = latestCurrentOWnedIdentityStored.replacingHiddenCryptoId(by: currentOwnedCryptoId)
        } else {
            return
        }
        store(newCurrentOwnedIdentityStored: newCurrentOwnedIdentityStored)
    }

}


struct LatestCurrentOWnedIdentityStored: Codable, ObvErrorMaker {

    let nonHiddenCryptoId: ObvCryptoId
    let hiddenCryptoId: ObvCryptoId?
    
    static let errorDomain = "LatestCurrentOWnedIdentityStored"
    
    fileprivate func replacingHiddenCryptoId(by newHiddenCryptoId: ObvCryptoId) -> Self {
        return LatestCurrentOWnedIdentityStored(
            nonHiddenCryptoId: nonHiddenCryptoId,
            hiddenCryptoId: newHiddenCryptoId)
    }

    fileprivate  func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    fileprivate static func jsonDecode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        return try decoder.decode(Self.self, from: data)
    }

}

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
import ObvTypes
import ObvEncoder
import ObvCrypto
import ObvMetaManager
import OlvidUtils


final class PendingServerQueryToPendingServerQueryMigrationPolicyV40ToV41: NSEntityMigrationPolicy, ObvErrorMaker {
    
    static let errorDomain = "ObvEngineMigrationV40ToV41"
    static let debugPrintPrefix = "[\(errorDomain)][PendingServerQueryToPendingServerQueryMigrationPolicyV40ToV41]"

    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(Self.debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(Self.debugPrintPrefix) createDestinationInstances ends")
        }
        
        let dInstance = try initializeDestinationInstance(forEntityName: "PendingServerQuery",
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: Self.errorDomain)
        defer {
            manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
        }

        // We work directely on the destination instance, read the "encodedQueryType" attribute, update it, and write it back.
                
        guard let encodedQueryTypeAsData = dInstance.value(forKey: "encodedQueryType") as? Data else {
            throw Self.makeError(message: "Could not read the encodedQueryType of a PendingServerQuery entity")
        }
        
        guard let legacyEncodedQueryType = ObvEncoded(withRawData: encodedQueryTypeAsData) else {
            throw Self.makeError(message: "Could not parse a raw encodedQueryType as an ObvEncoded value")
        }
        
        guard let updatedEncodedQueryType = updateLegacyEncodedQueryType(legacyEncodedQueryType) else {
            throw Self.makeError(message: "Failed to update legacy query type: \(legacyEncodedQueryType.rawData.hexString())")
        }
        
        dInstance.setValue(updatedEncodedQueryType.rawData, forKey: "encodedQueryType")
        
    }
    
    
    /// Updates legacy encoded server queries if required, and return the updated value. This function returns `nil` in case of failure
    private func updateLegacyEncodedQueryType(_ obvEncoded: ObvEncoded) -> ObvEncoded? {
        guard var listOfEncoded = [ObvEncoded](obvEncoded) else { assertionFailure(); return nil }
        guard let encodedRawValue = listOfEncoded.first else { assertionFailure(); return nil }
        guard let rawValue = Int(encodedRawValue) else { assertionFailure(); return nil }
        switch rawValue {
        case 1: // Type putUserData
            // Tested
            guard listOfEncoded.count == 4 else { return nil }
            guard let labelAsString = String(listOfEncoded[1]) else { assertionFailure(); return nil }
            if let uid = UID(hexString: labelAsString) {
                listOfEncoded[1] = uid.obvEncode()
            } else if let labelAsData = Data(base64Encoded: labelAsString), let uid = UID(uid: labelAsData) {
                listOfEncoded[1] = uid.obvEncode()
            } else {
                assertionFailure()
                return nil
            }
            return listOfEncoded.obvEncode()
        case 2: // Type getUserData
            // Tested
            guard listOfEncoded.count == 3 else { assertionFailure(); return nil }
            guard let labelAsString = String(listOfEncoded[2]) else { assertionFailure(); return nil }
            if let uid = UID(hexString: labelAsString) {
                listOfEncoded[2] = uid.obvEncode()
            } else if let labelAsData = Data(base64Encoded: labelAsString), let uid = UID(uid: labelAsData) {
                listOfEncoded[2] = uid.obvEncode()
            } else {
                assertionFailure()
                return nil
            }
            return listOfEncoded.obvEncode()
        default:
            // Tested
            return obvEncoded
        }
    }
        
}

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
import OlvidUtils
import ObvCrypto

// ok
final class ProvisionToProvisionV61ToV62: NSEntityMigrationPolicy {
    
    static let entityName: String = "Provision"
    static let errorDomain: String = entityName
    static let debugPrintPrefix: String = "[\(errorDomain)][ProvisionToProvisionV61ToV62]"

    override func begin(_ mapping: NSEntityMapping, with manager: NSMigrationManager) throws {
        ValueTransformer.setValueTransformer(SeedTransformerForMigration(), forName: .seedTransformerName)
    }

    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        do {
            
            debugPrint("\(Self.debugPrintPrefix) createDestinationInstances starts")
            defer {
                debugPrint("\(Self.debugPrintPrefix) createDestinationInstances ends")
            }
            
            let dInstance = try initializeDestinationInstance(forEntityName: Self.entityName,
                                                              forSource: sInstance,
                                                              in: mapping,
                                                              manager: manager,
                                                              errorDomain: Self.errorDomain)
            defer {
                manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
            }

            // seedForNextProvisionedReceiveKey (Seed) --> rawSeedForNextProvisionedReceiveKey (Binary)

            do {
                                
                guard let seedForNextProvisionedReceiveKey = sInstance.value(forKey: "seedForNextProvisionedReceiveKey") as? Seed else {
                    assertionFailure()
                    throw ObvError.couldNotGetSeedForNextProvisionedReceiveKey
                }
                
                dInstance.setValue(seedForNextProvisionedReceiveKey.raw, forKey: "rawSeedForNextProvisionedReceiveKey")
                
            }

            // Checks
            
            do {
                _ = try getSeedForNextProvisionedReceiveKey(dInstance: dInstance)
            }

        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
    enum ObvError: Error {
        case couldNotGetSeedForNextProvisionedReceiveKey
    }

    // For checks
    
    enum ObvErrorForChecks: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }

    private func getSeedForNextProvisionedReceiveKey(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> Seed {
        guard let rawSeedForNextProvisionedReceiveKey = dInstance.value(forKey: "rawSeedForNextProvisionedReceiveKey") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        guard let seed = Seed(with: rawSeedForNextProvisionedReceiveKey) else { assertionFailure(); throw .unexpectedNilValue }
        return seed
    }

}


// MARK: - Private helpers

private class SeedTransformerForMigration: ValueTransformer {

    override public class func transformedValueClass() -> AnyClass {
        return Seed.self
    }

    override public class func allowsReverseTransformation() -> Bool {
        return true
    }


    /// Turn an Seed into a Data object. This method never fails.
    override public func transformedValue(_ value: Any?) -> Any? {
        let uid = value as! Seed
        return uid.raw
    }

    /// Try to turn a Data object back into a Seed. This method can return nil.
    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return Seed(with: data)
    }

}

private extension NSValueTransformerName {
    static let seedTransformerName = NSValueTransformerName(rawValue: "SeedTransformer")
}

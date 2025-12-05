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
final class OutboxMessageToOutboxMessageV61ToV62: NSEntityMigrationPolicy {
    
    static let entityName: String = "OutboxMessage"
    static let errorDomain: String = entityName
    static let debugPrintPrefix: String = "[\(errorDomain)][OutboxMessageToOutboxMessageV61ToV62]"

    override func begin(_ mapping: NSEntityMapping, with manager: NSMigrationManager) throws {
        ValueTransformer.setValueTransformer(EncryptedDataTransformerForMigration(), forName: .encryptedDataTransformerName)
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

            // encryptedContent (EncryptedData) --> rawEncryptedContent (Binary)

            do {
                                
                guard let encryptedContent = sInstance.value(forKey: "encryptedContent") as? EncryptedData else {
                    assertionFailure()
                    throw ObvError.couldNotGetEncryptedContent
                }
                
                dInstance.setValue(encryptedContent.raw, forKey: "rawEncryptedContent")
                
            }

            // Checks
            
            do {
                _ = try getEncryptedContent(dInstance: dInstance)
            }

        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
    enum ObvError: Error {
        case couldNotGetEncryptedContent
    }

    // For checks
    
    enum ObvErrorForChecks: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }

    private func getEncryptedContent(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> EncryptedData {
        guard let rawEncryptedContent = dInstance.value(forKey: "rawEncryptedContent") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        return EncryptedData(data: rawEncryptedContent)
    }

}


// MARK: - Private helpers

private class EncryptedDataTransformerForMigration: ValueTransformer {
    
    override public class func transformedValueClass() -> AnyClass {
        return EncryptedData.self
    }
    
    override public class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    override public func transformedValue(_ value: Any?) -> Any? {
        guard let encryptedData = value as? EncryptedData else { return nil }
        return encryptedData.raw
    }
    
    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return EncryptedData(data: data)
    }
    
}


private extension NSValueTransformerName {
    static let encryptedDataTransformerName = NSValueTransformerName(rawValue: "EncryptedDataTransformer")
}

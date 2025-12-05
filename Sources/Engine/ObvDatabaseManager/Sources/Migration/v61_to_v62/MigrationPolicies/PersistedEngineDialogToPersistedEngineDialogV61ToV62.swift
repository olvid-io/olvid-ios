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
import ObvEncoder
import ObvTypes

// ok
final class PersistedEngineDialogToPersistedEngineDialogV61ToV62: NSEntityMigrationPolicy {
    
    static let entityName: String = "PersistedEngineDialog"
    static let errorDomain: String = entityName
    static let debugPrintPrefix: String = "[\(errorDomain)][PersistedEngineDialogToPersistedEngineDialogV61ToV62]"

    override func begin(_ mapping: NSEntityMapping, with manager: NSMigrationManager) throws {
        ValueTransformer.setValueTransformer(ObvEncodedTransformerForMigration(), forName: .obvEncodedTransformerName)
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

            // encodedObvDialog (ObvEncoded) --> rawEncodedObvDialog (Binary)

            do {
                                
                guard let encodedObvDialog = sInstance.value(forKey: "encodedObvDialog") as? ObvEncoded else {
                    assertionFailure()
                    throw ObvError.couldNotGetEncodedObvDialog
                }
                
                dInstance.setValue(encodedObvDialog.rawData, forKey: "rawEncodedObvDialog")
                
            }

            // Checks
            
            do {
                _ = try getObvDialog(dInstance: dInstance)
            }

        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
    enum ObvError: Error {
        case couldNotGetEncodedObvDialog
    }

    // For checks
    
    enum ObvErrorForChecks: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }

    private func getObvDialog(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> ObvDialog? {
        guard let rawEncodedObvDialog = dInstance.value(forKey: "rawEncodedObvDialog") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        guard let encodedValue = ObvEncoded(withRawData: rawEncodedObvDialog) else { assertionFailure(); throw .couldNotParseValue }
        return ObvDialog(encodedValue)
    }

}


// MARK: - Private helpers

private class ObvEncodedTransformerForMigration: ValueTransformer {

    override public class func transformedValueClass() -> AnyClass {
        return ObvEncoded.self
    }

    public override class func allowsReverseTransformation() -> Bool {
        return true
    }

    public override func transformedValue(_ value: Any?) -> Any? {
        guard let encodedData = value as? ObvEncoded else { return nil }
        return encodedData.rawData
    }

    public override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return ObvEncoded(withRawData: data)
    }
}


private extension NSValueTransformerName {
    static let obvEncodedTransformerName = NSValueTransformerName(rawValue: "ObvEncodedTransformer")
}

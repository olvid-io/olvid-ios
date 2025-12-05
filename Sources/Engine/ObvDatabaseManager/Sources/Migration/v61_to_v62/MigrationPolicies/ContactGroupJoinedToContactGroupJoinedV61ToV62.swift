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
final class ContactGroupJoinedToContactGroupJoinedV61ToV62: NSEntityMigrationPolicy {
    
    static let entityName: String = "ContactGroupJoined"
    static let errorDomain: String = entityName
    static let debugPrintPrefix: String = "[\(errorDomain)][ContactGroupJoinedToContactGroupJoinedV61ToV62]"

    override func begin(_ mapping: NSEntityMapping, with manager: NSMigrationManager) throws {
        ValueTransformer.setValueTransformer(UIDTransformerForMigration(), forName: .uidTransformerName)
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

            // groupUid (UID) --> rawGroupUid (Binary)
            
            do {
                                
                guard let groupUid = sInstance.value(forKey: "groupUid") as? UID else {
                    assertionFailure()
                    throw ObvError.couldNotGetGroupUid
                }
                
                dInstance.setValue(groupUid.raw, forKey: "rawGroupUid")
                
            }

            // Checks
            
            do {
                _ = try getGroupUid(dInstance: dInstance)
            }

        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
    enum ObvError: Error {
        case couldNotGetGroupUid
    }

    // For checks
    
    enum ObvErrorForChecks: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }

    private func getGroupUid(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> UID {
        guard let rawGroupUid = dInstance.value(forKey: "rawGroupUid") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        guard let groupUid = UID(uid: rawGroupUid) else { assertionFailure(); throw .couldNotParseValue }
        return groupUid
    }

}


// MARK: - Private helpers

private class UIDTransformerForMigration: ValueTransformer {

    override public class func transformedValueClass() -> AnyClass {
        return UID.self
    }

    override public class func allowsReverseTransformation() -> Bool {
        return true
    }


    /// Turn an UID into a Data object. This method never fails.
    override public func transformedValue(_ value: Any?) -> Any? {
        let uid = value as! UID
        return uid.raw
    }

    /// Try to turn a Data object back into a UID. This method can return nil.
    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return UID(uid: data)
    }

}


private extension NSValueTransformerName {
    static let uidTransformerName = NSValueTransformerName(rawValue: "UIDTransformer")
}

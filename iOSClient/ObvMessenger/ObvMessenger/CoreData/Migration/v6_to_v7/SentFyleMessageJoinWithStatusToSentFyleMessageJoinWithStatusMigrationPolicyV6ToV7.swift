/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import MobileCoreServices

fileprivate let errorDomain = "MessengerMigrationV6ToV7"
fileprivate let debugPrintPrefix = "[\(errorDomain)][SentFyleMessageJoinWithStatusToSentFyleMessageJoinWithStatusMigrationPolicyV6ToV7]"

final class SentFyleMessageJoinWithStatusToSentFyleMessageJoinWithStatusMigrationPolicyV6ToV7: NSEntityMigrationPolicy {
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }

        // Create an instance of the destination object.
        let entityName = "SentFyleMessageJoinWithStatus"
        guard let description = NSEntityDescription.entity(forEntityName: entityName, in: manager.destinationContext) else {
            let message = "Invalid entity name: \(entityName)"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        let newSentFyleMessageJoinWithStatus = SentFyleMessageJoinWithStatus(entity: description, insertInto: manager.destinationContext)
        
        // Create a method that performs the task of iterating over the property mappings if they are present in the migration. This method only controls the traversal while the next block of code will perform the operation required for each property mapping.
        func traversePropertyMappings(block: (NSPropertyMapping, String) -> Void) throws {
            guard let attributeMappings = mapping.attributeMappings else {
                let message = "No Attribute Mappings found!"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            for propertyMapping in attributeMappings {
                guard let destinationName = propertyMapping.name else {
                    let message = "Attribute destination not configured properly"
                    let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                    throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
                }
                block(propertyMapping, destinationName)
            }
        }
        
        // Most of the attributes migrations should be performed using the expressions defined in the mapping model. We use the previous traversal function and apply the value expression to the source instance and set the result to the new destination object.
        try traversePropertyMappings { (propertyMapping, destinationName) in
            if let valueExpression = propertyMapping.valueExpression {
                let context: NSMutableDictionary = ["source": sInstance]
                guard let destinationValue = valueExpression.expressionValue(with: sInstance, context: context) else {
                    return
                }
                newSentFyleMessageJoinWithStatus.setValue(destinationValue, forKey: destinationName)
            }
        }

        // It is time to perform the complex mappings

        // We need to find the appropriate uti. We apply the following strategies until one works out:
        // 1. Guess uti from filename
        // 2. Guess uti from the binary content of the file
        // 3. Fallback to kUTTypeData

        let uti: String
        
        if let _uti = ObvUTIUtils.utiOfFile(withName: newSentFyleMessageJoinWithStatus.fileName) {
            // Try 1: Using the filename
            uti = _uti
        } else {
            let sourceSentFyleMessageJoinWithStatus = sInstance
            guard let fyle = sourceSentFyleMessageJoinWithStatus.value(forKey: "fyle") as? NSManagedObject else {
                let message = "Could not get fyle from SourceSentFyleMessageJoinWithStatus"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            guard let url = fyle.value(forKey: "url") as? URL else {
                let message = "Could not get url from fyle"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            if let _uti = ObvUTIUtils.guessUTIOfBinaryFile(atURL: url) {
                uti = _uti
                if let ext = ObvUTIUtils.preferredTagWithClass(inUTI: uti, inTagClass: .FilenameExtension) {
                    let newFileName = [newSentFyleMessageJoinWithStatus.fileName, ext].joined(separator: ".")
                    newSentFyleMessageJoinWithStatus.setValue(newFileName, forKey: "fileName")
                }
            } else {
                uti = kUTTypeData as String
            }
        }

        newSentFyleMessageJoinWithStatus.setValue(uti, forKey: "uti")
        
        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: newSentFyleMessageJoinWithStatus, for: mapping)

    }
    
}

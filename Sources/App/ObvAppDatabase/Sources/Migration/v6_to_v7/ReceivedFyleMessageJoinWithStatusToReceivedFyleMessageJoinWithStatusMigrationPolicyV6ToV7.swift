/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import UniformTypeIdentifiers
import MobileCoreServices


fileprivate let errorDomain = "MessengerMigrationV6ToV7"
fileprivate let debugPrintPrefix = "[\(errorDomain)][ReceivedFyleMessageJoinWithStatusToReceivedFyleMessageJoinWithStatusMigrationPolicyV6ToV7]"


final class ReceivedFyleMessageJoinWithStatusToReceivedFyleMessageJoinWithStatusMigrationPolicyV6ToV7: NSEntityMigrationPolicy {
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        // Create an instance of the destination object.
        let dObject: NSManagedObject
        do {
            let entityName = "ReceivedFyleMessageJoinWithStatus"
            guard let description = NSEntityDescription.entity(forEntityName: entityName, in: manager.destinationContext) else {
                let message = "Invalid entity name: \(entityName)"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            dObject = NSManagedObject(entity: description, insertInto: manager.destinationContext)
        }
        
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
                dObject.setValue(destinationValue, forKey: destinationName)
            }
        }
        
        // It is time to perform the complex mappings
        
        // We need to find the appropriate uti. We apply the following strategies until one works out:
        // 1. Guess uti from filename
        // 2. Guess uti from the binary content of the file
        // 3. Fallback to kUTTypeData
        
        let uti: String
        
        guard let sFilename = sInstance.value(forKey: "fileName") as? String else {
            let message = "Unable to extract filename from source ReceivedFyleMessageJoinWithStatus"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        
        if let _uti = Self.utiOfFile(withName: sFilename) {
            // Try 1: Using the filename
            uti = _uti
        } else {
            let sourceReceivedFyleMessageJoinWithStatus = sInstance
            guard let fyle = sourceReceivedFyleMessageJoinWithStatus.value(forKey: "fyle") as? NSManagedObject else {
                let message = "Could not get fyle from SourceReceivedFyleMessageJoinWithStatus"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            guard let url = fyle.value(forKey: "url") as? URL else {
                let message = "Could not get url from fyle"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            if let _uti = Self.guessUTIOfBinaryFile(atURL: url) {
                uti = _uti
                if let ext = Self.preferredTagWithClassFilenameExtension(inUTI: uti) {
                    let newFileName = [sFilename, ext].joined(separator: ".")
                    dObject.setValue(newFileName, forKey: "fileName")
                }
            } else {
                uti = UTType.data.identifier
            }
        }
        
        dObject.setValue(uti, forKey: "uti")
        
        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dObject, for: mapping)
        
    }
    
    
    private static func utiOfFile(withName fileName: String) -> String? {
        let fileExtension = NSString(string: fileName).pathExtension
        return Self.utiOfFile(withExtension: fileExtension)
    }
    
    
    private static func utiOfFile(withExtension fileExtension: String) -> String? {
        guard !fileExtension.isEmpty else { return nil }
        return UTType(filenameExtension: fileExtension)?.identifier
    }
    

    private static func guessUTIOfBinaryFile(atURL url: URL) -> String? {
        
        let jpegPrefix = Data([0xff, 0xd8])
        let pngPrefix = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let pdfPrefix = Data([0x25, 0x50, 0x44, 0x46, 0x2D])
        let mp4Signatures = ["ftyp", "mdat", "moov", "pnot", "udta", "uuid", "moof", "free", "skip", "jP2 ", "wide", "load", "ctab", "imap", "matt", "kmat", "clip", "crgn", "sync", "chap", "tmcd", "scpt", "ssrc", "PICT"].map { Data([UInt8]($0.utf8)) }
        
        guard let fileData = try? Data(contentsOf: url) else {
            return nil
        }
        
        if fileData.starts(with: jpegPrefix) {
            return UTType.jpeg.identifier
        } else if fileData.starts(with: pngPrefix) {
            return UTType.png.identifier
        } else if fileData.starts(with: pdfPrefix) {
            return UTType.pdf.identifier
        } else if mp4Signatures.contains(fileData.advanced(by: 4)[0..<4]) {
            return UTType.mpeg4Movie.identifier
        } else {
            return nil
        }

    }

    
    private static func preferredTagWithClassFilenameExtension(inUTI uti: String) -> String? {
        return UTType(uti)?.preferredFilenameExtension
    }

}

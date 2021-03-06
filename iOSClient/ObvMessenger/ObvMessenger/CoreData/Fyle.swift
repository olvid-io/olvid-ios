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
import os.log
import ObvEngine

@objc(Fyle)
final class Fyle: NSManagedObject {
    
    private static let entityName = "Fyle"

    // MARK: - Properties

    @NSManaged var intrinsicFilename: String?
    @NSManaged private(set) var sha256: Data
    
    // MARK: - Relationship
    
    @NSManaged private(set) var allDraftFyleJoins: Set<PersistedDraftFyleJoin>
    @NSManaged private(set) var allFyleMessageJoinWithStatus: Set<FyleMessageJoinWithStatus>

    // MARK: - Other variables
    
    private var filenameOnDisk: String {
        sha256.hexString()
    }
    
    var url: URL {
        Fyle.getFileURL(lastPathComponent: filenameOnDisk)
    }
    
    // MARK: - Initializer

    convenience init?(sha256: Data, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: Fyle.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.sha256 = sha256
        
        self.allDraftFyleJoins = Set<PersistedDraftFyleJoin>()
        self.allFyleMessageJoinWithStatus = Set<FyleMessageJoinWithStatus>()
    }
    
    static func getFileURL(lastPathComponent: String) -> URL {
        ObvMessengerConstants.containerURL.forFyles.appendingPathComponent(lastPathComponent)
    }
    
    private static let errorDomain = "Fyle"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }
    
    static func getOrCreate(sha256: Data, within context: NSManagedObjectContext) throws -> Fyle {
        if let previousFyle = try Fyle.get(sha256: sha256, within: context) {
            return previousFyle
        } else {
            guard let newFyle = Fyle(sha256: sha256, within: context) else {
                throw makeError(message: "Could not create new Fyle instance")
            }
            return newFyle
        }
    }
    
}


// MARK: - Other methods

extension Fyle {
    
    func moveFileToPermanentURL(from fromUrl: URL, logTo log: OSLog) throws {

        guard FileManager.default.fileExists(atPath: fromUrl.path) else {
            os_log("Could not find the source file", log: log, type: .error)
            throw Fyle.makeError(message: "Could not find the source file")
        }
        
        if FileManager.default.fileExists(atPath: url.path) {
            os_log("The destination file already exists", log: log, type: .debug)
        } else {
            os_log("Moving a file from %@ to %@", log: log, type: .debug, fromUrl.debugDescription, url.debugDescription)
            try FileManager.default.moveItem(atPath: fromUrl.path, toPath: url.path)
        }
    }
    
    
    func copyFileToPermanentURL(from fromURL: URL, logTo log: OSLog) throws {
        guard FileManager.default.fileExists(atPath: fromURL.path) else {
            os_log("Could not find the source file", log: log, type: .error)
            throw NSError()
        }
        
        if FileManager.default.fileExists(atPath: url.path) {
            os_log("The destination file already exists", log: log, type: .debug)
        } else {
            os_log("Copying a file from %@ to %@", log: log, type: .debug, fromURL.debugDescription, url.debugDescription)
            try FileManager.default.copyItem(at: fromURL, to: url)
        }
    }
    
    
    func getFileSize() -> Int64? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return fileAttributes[FileAttributeKey.size] as? Int64
    }
    
    func remove(_ draftFyleJoin: PersistedDraftFyleJoin) {
        self.allDraftFyleJoins.remove(draftFyleJoin)
    }
    
    func deleteIfNoLongerUsed() {
        guard self.allFyleMessageJoinWithStatus.isEmpty else {
            return
        }
        guard self.allDraftFyleJoins.isEmpty else {
            return
        }
        guard let context = self.managedObjectContext else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            debugPrint("Could not delete file")
        }
        context.delete(self)
    }
    
    
    func moveFileToTrash() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let trashURL = ObvMessengerConstants.containerURL.forTrash.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: url, to: trashURL)
    }
    
}

// MARK: - Convenience DB getters

extension Fyle {
    
    struct Predicate {
        enum Key: String {
            case sha256 = "sha256"
            case allDraftFyleJoins = "allDraftFyleJoins"
            case allFyleMessageJoinWithStatus = "allFyleMessageJoinWithStatus"
        }
        fileprivate static func withSha256(_ sha256: Data) -> NSPredicate {
            NSPredicate.init(Key.sha256, EqualToData: sha256)
        }
        fileprivate static var isOrphaned: NSPredicate {
            NSPredicate(format: "%K.@count == 0 AND %K.@count == 0", Key.allFyleMessageJoinWithStatus.rawValue, Key.allDraftFyleJoins.rawValue)
        }
    }

    @nonobjc static func fetchRequest() -> NSFetchRequest<Fyle> {
        return NSFetchRequest<Fyle>(entityName: Fyle.entityName)
    }
    
    static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> Fyle? {
        return try context.existingObject(with: objectID) as? Fyle
    }
    
    static func get(sha256: Data, within context: NSManagedObjectContext) throws -> Fyle? {
        let request: NSFetchRequest<Fyle> = Fyle.fetchRequest()
        request.predicate = Predicate.withSha256(sha256)
        request.fetchLimit = 1
        let fyles = try context.fetch(request)
        return fyles.first
    }
        
    static func getAllOrphaned(within context: NSManagedObjectContext) throws -> [Fyle] {
        let request: NSFetchRequest<Fyle> = Fyle.fetchRequest()
        request.predicate = Predicate.isOrphaned
        return try context.fetch(request)
    }
    
    
    static func getAllFilenames(within context: NSManagedObjectContext) throws -> [String] {
        let request: NSFetchRequest<Fyle> = Fyle.fetchRequest()
        request.propertiesToFetch = [Predicate.Key.sha256.rawValue]
        let results = try context.fetch(request)
        let filenamesOnDisk = results.map({ $0.filenameOnDisk })
        return filenamesOnDisk
    }
    
    
    static func noFyleReferencesTheURL(_ url: URL, within context: NSManagedObjectContext) throws -> Bool {
        let request = NSFetchRequest<NSManagedObjectID>(entityName: Fyle.entityName)
        let filename = url.lastPathComponent
        guard let sha256 = Data(hexString: filename) else { return true }
        assert(sha256.count == 32)
        request.predicate = Predicate.withSha256(sha256)
        request.resultType = .managedObjectIDResultType
        request.fetchLimit = 1
        let objects: [NSManagedObjectID] = try context.fetch(request)
        return objects.isEmpty
    }
    
}

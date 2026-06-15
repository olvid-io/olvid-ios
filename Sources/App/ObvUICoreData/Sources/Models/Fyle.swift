/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import OSLog
import ObvTypes
import OlvidUtils
import ObvCrypto
import ObvSettings
import UniformTypeIdentifiers


@objc(Fyle)
public final class Fyle: NSManagedObject {
    
    private static let entityName = "Fyle"
    private static let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "Fyle")
    private static let logger = Logger(subsystem: ObvUICoreDataConstants.logSubsystem, category: "Fyle")

    // MARK: - Properties

    @NSManaged private var intrinsicFilename: String?
    @NSManaged public private(set) var sha256: Data
    
    // MARK: - Relationship
    
    @NSManaged private(set) var allDraftFyleJoins: Set<PersistedDraftFyleJoin>
    @NSManaged public private(set) var allFyleMessageJoinWithStatus: Set<FyleMessageJoinWithStatus>

    
    // MARK: - Transient URL - url to set if the fyle is not cached at the usual place (used mainly for previews generated on the fly)
    var transientURL: URL?
    
    // MARK: - Initializer

    private convenience init(sha256: Data, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: Fyle.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.sha256 = sha256
        
        self.allDraftFyleJoins = Set<PersistedDraftFyleJoin>()
        self.allFyleMessageJoinWithStatus = Set<FyleMessageJoinWithStatus>()
    }
      
    public static func getOrCreate(sha256: Data, within context: NSManagedObjectContext) throws -> Fyle {
        if let previousFyle = try Fyle.get(sha256: sha256, within: context) {
            return previousFyle
        } else {
            let newFyle = Fyle(sha256: sha256, within: context)
            return newFyle
        }
    }
    
    
    func updateFyle(with obvAttachment: ObvAttachment) throws {
        try updateFyle(obvAttachmentStatus: obvAttachment.status)
    }

    
    func updateFyle(with obvOwnedAttachment: ObvOwnedAttachment) throws {
        try updateFyle(obvAttachmentStatus: obvOwnedAttachment.status)
    }

    
    public func storeHistoryTransferredAttachment(sha256: Data, temporaryURLOfAttachment: URL) throws {
        
        guard self.sha256 == sha256 else {
            assertionFailure()
            throw ObvUICoreDataError.unexpectedSha256
        }
        
        // Make sure we do not already have a local (app) version of this file
        guard self.getFileSize() == nil else {
            Self.logger.error("We already have a local version of this file")
            assertionFailure()
            return
        }

        // Make sure the file is indeed available at the obvAttachmentURL.
        // If this is not the case, we throw. The exception will eventually be processed by the operation (at the app level) and a new download will be requested to the engine.
        guard FileManager.default.fileExists(atPath: temporaryURLOfAttachment.path) else {
            Self.logger.error("Could not find a file at the indicated URL")
            throw ObvUICoreDataError.couldNotFindSourceFile
        }

        // Compute the sha256 of the (complete) file indicated within the obvAttachment and compare it to what was expected
        let realHash: Data
        do {
            let sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()
            realHash = try sha256.hash(fileAtUrl: temporaryURLOfAttachment)
        } catch {
            throw ObvUICoreDataError.couldNotComputeSHA256
        }

        guard realHash == self.sha256 else {
            Self.logger.error("OMG, the sha256 of the received file does not match the one we expected. Expecting \(self.sha256.hexString(), privacy: .public) but the hash of the received file is \(realHash.hexString(), privacy: .public)")
            assertionFailure()
            throw ObvUICoreDataError.sha256OfReceivedFileReferenceByObvAttachmentDoesNotMatchWhatWeExpect
        }

        try self.moveFileToPermanentURL(from: temporaryURLOfAttachment, logTo: Self.log)
        
        Self.logger.debug("We moved a file received during history transfer to a permanent location")
        
        guard let fileSize = self.getFileSize() else {
            assertionFailure()
            Self.logger.fault("Could not get the file size of the copied file")
            throw ObvUICoreDataError.couldNotComputeFileSize
        }
        
        // Update the status of all joins
        
        for join in self.allFyleMessageJoinWithStatus {
            if let receivedJoin = join as? ReceivedFyleMessageJoinWithStatus {
                receivedJoin.setStatusToDownloadedDuringHistoryTransfer(fileSize: fileSize)
            } else if let sentJoin = join as? SentFyleMessageJoinWithStatus {
                sentJoin.setStatusToDownloadedDuringHistoryTransfer(fileSize: fileSize)
            }
        }
        
    }
    
    
    private func updateFyle(obvAttachmentStatus: ObvAttachment.Status) throws {
        
        // Make sure the file was downloaded and that we do not already have a local (app) version of this file
        
        switch obvAttachmentStatus {
        case .downloaded(url: let obvAttachmentURL):
            
            // Make sure we do not already have a local (app) version of this file
            guard self.getFileSize() == nil else {
                Self.logger.error("We already have a local version of this file")
                assertionFailure()
                return
            }
            
            // Make sure the file is indeed available at the obvAttachmentURL.
            // If this is not the case, we throw. The exception will eventually be processed by the operation (at the app level) and a new download will be requested to the engine.
            guard FileManager.default.fileExists(atPath: obvAttachmentURL.path) else {
                Self.logger.error("Could not find a file at the URL indicated by the engine, although it supposed to be complete")
                throw ObvUICoreDataError.couldNotFindSourceFile
            }

            // Compute the sha256 of the (complete) file indicated within the obvAttachment and compare it to what was expected
            let realHash: Data
            do {
                let sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()
                realHash = try sha256.hash(fileAtUrl: obvAttachmentURL)
            } catch {
                throw ObvUICoreDataError.couldNotComputeSHA256
            }

            guard realHash == self.sha256 else {
                let sha256HexString = self.sha256.hexString()
                Self.logger.error("OMG, the sha256 of the received file does not match the one we expected. Expecting \(sha256HexString, privacy: .public) but the hash of the received file is \(realHash.hexString(), privacy: .public)")
                assertionFailure()
                throw ObvUICoreDataError.sha256OfReceivedFileReferenceByObvAttachmentDoesNotMatchWhatWeExpect
            }

            // If we reach this point, the sha256 is correct. We move the received file to a permanent location

            try self.moveFileToPermanentURL(from: obvAttachmentURL, logTo: Self.log)

            Self.logger.debug("We moved a downloaded file to a permanent location")
            
        default:
            return
            
        }
        
    }

}


// MARK: - Other methods

extension Fyle {
    
    public func fyleMessageJoinWithStatuses(ownedCryptoId: ObvCryptoId) -> Set<FyleMessageJoinWithStatus> {
        allFyleMessageJoinWithStatus.filter { $0.message?.discussion?.ownedIdentity?.cryptoId == ownedCryptoId }
    }

    func remove(_ draftFyleJoin: PersistedDraftFyleJoin) {
        self.allDraftFyleJoins.remove(draftFyleJoin)
    }
    
    public var filenameOnDisk: String {
        sha256.hexString()
    }
    
    private var isAttachedToPreview: Bool {
        !allFyleMessageJoinWithStatus.filter { $0.uti == UTType.olvidPreviewUti }.isEmpty
    }
    
    public var url: URL {
        if let transientURL {
            return transientURL
        } else {
            return Fyle.getFileURL(lastPathComponent: filenameOnDisk)
        }
    }

    public static func getFileURL(lastPathComponent: String) -> URL {
        ObvUICoreDataConstants.ContainerURL.forFyles.appendingPathComponent(lastPathComponent)
    }


    public func getFileSize() -> Int64? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return fileAttributes[FileAttributeKey.size] as? Int64
    }
    
    
    public var fileExistsOnDisk: Bool {
        self.getFileSize() != nil
    }
    
}


// MARK: File management on disk

extension Fyle {
    
    // MARK: - Other methods
    
    public func moveFileToPermanentURL(from fromUrl: URL, logTo log: OSLog) throws {

        guard FileManager.default.fileExists(atPath: fromUrl.path) else {
            os_log("Could not find the source file", log: log, type: .error)
            throw ObvUICoreDataError.couldNotFindSourceFile
        }
        
        if FileManager.default.fileExists(atPath: url.path) {
            // Not a big deal since the file a certainly identical
            os_log("The destination file already exists, won't move the file", log: log, type: .debug)
        } else {
            os_log("Moving a file from %@ to %@", log: log, type: .debug, fromUrl.debugDescription, url.debugDescription)
            try FileManager.default.moveItem(atPath: fromUrl.path, toPath: url.path)
        }
    }
    
    
    func copyFileToPermanentURL(from fromURL: URL, logTo log: OSLog) throws {
        
        guard FileManager.default.fileExists(atPath: fromURL.path) else {
            os_log("Could not find the source file", log: log, type: .error)
            throw ObvUICoreDataError.couldNotFindSourceFile
        }
        
        if FileManager.default.fileExists(atPath: url.path) {
            // Not a big deal since the file a certainly identical
            os_log("The destination file already exists, won't copy file", log: log, type: .debug)
        } else {
            os_log("Copying a file from %@ to %@", log: log, type: .debug, fromURL.debugDescription, url.debugDescription)
            try FileManager.default.copyItem(at: fromURL, to: url)
        }
        
    }
    
    
    public func moveFileToTrash() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let trashURL = ObvUICoreDataConstants.ContainerURL.forTrash.appendingPathComponent(UUID().uuidString)
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
            NSPredicate(Key.sha256, EqualToData: sha256)
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

    
    /// Returns a `Fyle` if one can be found for the given sha256.
    public static func get(sha256: Data, within context: NSManagedObjectContext) throws -> Fyle? {
        let request: NSFetchRequest<Fyle> = Fyle.fetchRequest()
        request.predicate = Predicate.withSha256(sha256)
        request.fetchLimit = 1
        let fyles = try context.fetch(request)
        return fyles.first
    }
        
    public static func getAll(within context: NSManagedObjectContext) throws -> [Fyle] {
        let request: NSFetchRequest<Fyle> = Fyle.fetchRequest()
        request.fetchBatchSize = 500
        return try context.fetch(request)
    }

    /// Returns all orphaned `Fyle` entities, i.e., those that have no associated `PersistedDraftFyleJoin` and no associated `FyleMessageJoinWithStatus`.
    public static func getAllOrphaned(within context: NSManagedObjectContext) throws -> [Fyle] {
        let request: NSFetchRequest<Fyle> = Fyle.fetchRequest()
        request.predicate = Predicate.isOrphaned
        request.fetchBatchSize = 500
        return try context.fetch(request)
    }
    
    
    /// Returns the filename of all the `Fyles`.
    public static func getAllFilenames(within context: NSManagedObjectContext) throws -> [String] {
        let request: NSFetchRequest<Fyle> = Fyle.fetchRequest()
        request.propertiesToFetch = [Predicate.Key.sha256.rawValue]
        request.fetchBatchSize = 500
        let results = try context.fetch(request)
        let filenamesOnDisk = results.map({ $0.filenameOnDisk })
        return filenamesOnDisk
    }
    
    
    public static func noFyleReferencesTheURL(_ url: URL, within context: NSManagedObjectContext) throws -> Bool {
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

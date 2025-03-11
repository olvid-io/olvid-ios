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
import CoreServices
import ObvTypes
import os.log
import ObvSettings
import ObvUICoreDataStructs


@objc(ReceivedFyleMessageJoinWithStatus)
public final class ReceivedFyleMessageJoinWithStatus: FyleMessageJoinWithStatus, Identifiable {
    
    private static let entityName = "ReceivedFyleMessageJoinWithStatus"
    private static let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "ReceivedFyleMessageJoinWithStatus")

    public enum FyleStatus: Int {
        case downloadable = 0
        case downloading = 1
        case complete = 2
        case cancelledByServer = 3
    }
        
    // MARK: Properties
    
    @NSManaged public private(set) var wasOpened: Bool

    // MARK: Relationships
    
    @NSManaged public private(set) var receivedMessage: PersistedMessageReceived

    // MARK: Computed properties
    
    public var status: FyleStatus {
        return FyleStatus(rawValue: self.rawStatus)!
    }
    
    public var messageIdentifierFromEngine: Data {
        return receivedMessage.messageIdentifierFromEngine
    }
    
    public override var message: PersistedMessage? { receivedMessage }

    public override var fullFileIsAvailable: Bool { status == .complete }

    private var changedKeys = Set<String>()

    // MARK: - Initializer
    
    private convenience init(obvAttachment: ObvAttachment, within context: NSManagedObjectContext) throws {

        let metadata = try FyleMetadata.jsonDecode(obvAttachment.metadata)

        guard let receivedMessage = try PersistedMessageReceived.get(messageIdentifierFromEngine: obvAttachment.messageIdentifier,
                                                                     from: obvAttachment.fromContactIdentity,
                                                                     within: context) else {
            throw ObvUICoreDataError.couldNotFindPersistedMessageReceived
        }

        guard !receivedMessage.isWiped else {
            throw ObvUICoreDataError.cannotCreateReceivedFyleMessageJoinWithStatusForWipedMessage
        }
        
        try self.init(sha256: metadata.sha256,
                      totalByteCount: 0, // Reset bellow
                      fileName: metadata.fileName,
                      uti: metadata.contentType.identifier,
                      rawStatus: FyleStatus.complete.rawValue, // Reset later
                      messageSortIndex: receivedMessage.sortIndex,
                      index: obvAttachment.number,
                      forEntityName: ReceivedFyleMessageJoinWithStatus.entityName,
                      within: context)

        guard let fyle else {
            assertionFailure()
            throw ObvUICoreDataError.theFyleShouldHaveBeenCreatedByTheSuperclassInitializer
        }
        
        if let fileSize = fyle.getFileSize() {
            self.rawStatus = FyleStatus.complete.rawValue
            self.setTotalByteCount(to: fileSize)
        } else {
            self.rawStatus = obvAttachment.downloadPaused ? FyleStatus.downloadable.rawValue : FyleStatus.downloading.rawValue
            self.setTotalByteCount(to: obvAttachment.totalUnitCount)
        }

        // Set the remaining properties and relationships
        
        self.receivedMessage = receivedMessage
    }
    
    
    /// Initializer called exclusively to create transient `ReceivedFyleMessageJoinWithStatus` instances in the view context. 
    public convenience init(forPreviewWithSha256 sha256: Data, fromURL: URL, filename: String, uti: String, messageObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>, within viewContext: NSManagedObjectContext) throws {

        guard viewContext.concurrencyType == .mainQueueConcurrencyType else {
            assertionFailure()
            throw ObvUICoreDataError.inappropriateContext
        }
        
        guard Thread.isMainThread else {
            assertionFailure()
            throw ObvUICoreDataError.callMustBePerformedOnMainThread
        }
        
        guard let receivedMessage = try PersistedMessageReceived.get(with: messageObjectID, within: viewContext) else  {
            throw ObvUICoreDataError.couldNotFindPersistedMessageReceived
        }
        
        try self.init(sha256: sha256,
                      totalByteCount: 0, // Reset bellow
                      fileName: filename,
                      uti: uti,
                      rawStatus: FyleStatus.complete.rawValue, // Reset later
                      messageSortIndex: receivedMessage.sortIndex,
                      index: (receivedMessage.fyleMessageJoinWithStatus?.count ?? 0),
                      forEntityName: ReceivedFyleMessageJoinWithStatus.entityName,
                      within: viewContext)

        guard let fyle else {
            assertionFailure()
            throw ObvUICoreDataError.theFyleShouldHaveBeenCreatedByTheSuperclassInitializer
        }
        
        fyle.transientURL = fromURL
        
        if let fileSize = fyle.getFileSize() {
            self.rawStatus = FyleStatus.complete.rawValue
            self.setTotalByteCount(to: fileSize)
        } else {
            self.rawStatus = FyleStatus.downloadable.rawValue
            self.setTotalByteCount(to: 0)
        }

        // Set the remaining properties and relationships
        self.receivedMessage = receivedMessage
    }
    
    
    static func createOrUpdateReceivedFyleMessageJoinWithStatus(with obvAttachment: ObvAttachment, within context: NSManagedObjectContext) throws {
        
        let join: ReceivedFyleMessageJoinWithStatus
        if let previousJoin = try ReceivedFyleMessageJoinWithStatus.get(obvAttachment: obvAttachment, within: context) {
            join = previousJoin
            if join.fyle == nil {
                assertionFailure("This is unexpected as the join should have been cascade deleted when the fyle was deleted")
                let metadata = try FyleMetadata.jsonDecode(obvAttachment.metadata)
                try join.getOrCreateFyle(sha256: metadata.sha256)
            }
        } else {
            join = try Self.init(
                obvAttachment: obvAttachment,
                within: context)
            assert(join.fyle != nil, "The fyle should have been created by the init of the superclass")
        }
        
        try join.updateReceivedFyleMessageJoinWithStatus(with: obvAttachment)
            
    }

    
    private func updateReceivedFyleMessageJoinWithStatus(with obvAttachment: ObvAttachment) throws {
        
        // Update the status of the ReceivedFyleMessageJoinWithStatus depending on the status of the ObvAttachment

        switch obvAttachment.status {

        case .paused:
            tryToSetStatusTo(.downloadable)
            
        case .resumed:
            tryToSetStatusTo(.downloading)

        case .downloaded:
            guard let fyle else {
                assertionFailure("Could not find fyle although this join should have been cascade deleted when the fyle was deleted")
                throw ObvUICoreDataError.couldNotFindFyle
            }
            try fyle.updateFyle(with: obvAttachment)
            let attachmentFullyReceived = (fyle.getFileSize() == totalByteCount)
            if attachmentFullyReceived {
                tryToSetStatusTo(.complete)
                deleteDownsizedThumbnail()
            }

        case .cancelledByServer:
            tryToSetStatusTo(.cancelledByServer)

        case .markedForDeletion:
            break

        }
        
    }
    
    
    public override func wipe() throws {
        try super.wipe()
        tryToSetStatusTo(.complete)
    }

    
    /// Set the downsized thumbnail if required. Returns `true` if this was the case, or `false` otherwise.
    ///
    /// Exclusively called from ``PersistedMessageReceived.saveExtendedPayload(foundIn:)``.
    override func setDownsizedThumbnailIfRequired(data: Data) -> Bool {
        assert(self.downsizedThumbnail == nil)
        guard !isWiped else { assertionFailure(); return false }
        guard requiresDownsizedThumbnail() else { return false }
        return super.setDownsizedThumbnailIfRequired(data: data)
    }
    
    // MARK: - Observers
    
    private static var observersHolder = ReceivedFyleMessageJoinWithStatusObserversHolder()
    
    public static func addReceivedFyleMessageJoinWithStatusObserver(_ newObserver: ReceivedFyleMessageJoinWithStatusObserver) async {
        await observersHolder.addObserver(newObserver)
    }

}

// MARK: - Other methods

extension ReceivedFyleMessageJoinWithStatus {

    private func tryToSetStatusTo(_ newStatus: FyleStatus) {
        guard self.status != .complete else { return }
        self.rawStatus = newStatus.rawValue
        self.message?.setHasUpdate()
        if self.status == .complete {
            let joinObjectID = (self as FyleMessageJoinWithStatus).typedObjectID
            Task {
                await FyleMessageJoinWithStatus.removeProgressForJoinWithObjectID(joinObjectID)
            }
        }
    }

    public func tryToSetStatusToCancelledByServer() {
        tryToSetStatusTo(.cancelledByServer)
    }
    
    public func tryToSetStatusToDownloading() {
        tryToSetStatusTo(.downloading)
    }
    
    public func tryToSetStatusToDownloadable() {
        tryToSetStatusTo(.downloadable)
    }

    
    public func markAsOpened() {
        guard !self.wasOpened else { return }
        self.wasOpened = true
    }

    
    public func fyleElementOfReceivedJoin() -> FyleElement? {
        // If the associated received message requires a user interaction to be read, we do *not* return
        // FyleElement as these are typically used to display the join content on screen.
        guard !receivedMessage.readingRequiresUserAction else { return nil }
        return try? FyleElementForFyleMessageJoinWithStatus(self)
    }

    
    func obvAttachmentImage() -> ObvAttachmentImage? {
        guard !receivedMessage.readingRequiresUserAction else { return nil }
        if let fyleElement = fyleElementOfReceivedJoin(), fyleElement.fullFileIsAvailable {
            guard fyleElement.contentType.conforms(to: .jpeg) else { return nil }
            return .url(attachmentNumber: index, fyleElement.fyleURL)
        } else if let data = downsizedThumbnail {
            return .data(attachmentNumber: index, data)
        } else {
            return nil
        }

    }

    // `true` if this join is not complete, or if the fyle is not completely available on disk
    private func requiresDownsizedThumbnail() -> Bool {
        guard let fyle = self.fyle else { return true }
        return self.status != .complete || fyle.getFileSize() != self.totalByteCount
    }
    
}


// MARK: - Determining actions availability

extension ReceivedFyleMessageJoinWithStatus {
    
    var copyActionCanBeMadeAvailableForReceivedJoin: Bool {
        return shareActionCanBeMadeAvailableForReceivedJoin
    }
    
    var shareActionCanBeMadeAvailableForReceivedJoin: Bool {
        guard status == .complete, !isPreviewType else { return false }
        return receivedMessage.shareActionCanBeMadeAvailableForReceivedMessage
    }
    
    var forwardActionCanBeMadeAvailableForReceivedJoin: Bool {
        return shareActionCanBeMadeAvailableForReceivedJoin
    }
    
}


// MARK: - Convenience DB getters

extension ReceivedFyleMessageJoinWithStatus {
    
    struct Predicate {
        enum Key: String {
            // Properties
            case downsizedThumbnail = "downsizedThumbnail"
            case wasOpened = "wasOpened"
            // Relationships
            case receivedMessage = "receivedMessage"
        }
        static func forReceivedMessage(_ receivedMessage: PersistedMessageReceived) -> NSPredicate {
            NSPredicate(Key.receivedMessage, equalTo: receivedMessage)
        }
    }

    
    @nonobjc static func fetchRequest() -> NSFetchRequest<ReceivedFyleMessageJoinWithStatus> {
        return NSFetchRequest<ReceivedFyleMessageJoinWithStatus>(entityName: ReceivedFyleMessageJoinWithStatus.entityName)
    }
    
    
    public static func getReceivedFyleMessageJoinWithStatus(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> ReceivedFyleMessageJoinWithStatus {
        guard let obj = try context.existingObject(with: objectID) as? ReceivedFyleMessageJoinWithStatus else { throw ObvUICoreDataError.couldNotFindReceivedFyleMessageJoinWithStatus }
        return obj
    }
    
    
    private static func get(obvAttachment: ObvAttachment, within context: NSManagedObjectContext) throws -> ReceivedFyleMessageJoinWithStatus? {
        let metadata = try FyleMetadata.jsonDecode(obvAttachment.metadata)
        guard let receivedMessage = try PersistedMessageReceived.get(
            messageIdentifierFromEngine: obvAttachment.messageIdentifier,
            from: obvAttachment.fromContactIdentity,
            within: context) else {
            throw ObvUICoreDataError.couldNotFindPersistedMessageReceived
        }
        let request: NSFetchRequest<ReceivedFyleMessageJoinWithStatus> = ReceivedFyleMessageJoinWithStatus.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            FyleMessageJoinWithStatus.Predicate.withSha256(metadata.sha256),
            Predicate.forReceivedMessage(receivedMessage),
        ])
        request.fetchLimit = 1
        let receivedFyleMessageJoinWithStatuses = try context.fetch(request)
        return receivedFyleMessageJoinWithStatuses.first
    }
 
    
    static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = ReceivedFyleMessageJoinWithStatus.fetchRequest()
        request.predicate = NSPredicate(format: "%K == NIL", Predicate.Key.receivedMessage.rawValue)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(deleteRequest)
    }

    
    public static func get(objectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>, within context: NSManagedObjectContext) throws -> ReceivedFyleMessageJoinWithStatus? {
        return try super.get(objectID: objectID.objectID, within: context) as? ReceivedFyleMessageJoinWithStatus
    }
}


// MARK: - Downcasting

public extension TypeSafeManagedObjectID where T == ReceivedFyleMessageJoinWithStatus {
    var downcast: TypeSafeManagedObjectID<FyleMessageJoinWithStatus> {
        TypeSafeManagedObjectID<FyleMessageJoinWithStatus>(objectID: objectID)
    }
}


// MARK: - Reacting to changes

extension ReceivedFyleMessageJoinWithStatus {
    
    // MARK: - Deleting Fyle when deleting the last ReceivedFyleMessageJoinWithStatus
    
    public override func willSave() {
        super.willSave()
        
        assert(!Thread.isMainThread)

        if isDeleted {
            if let fyle = self.fyle, fyle.allFyleMessageJoinWithStatus.count == 1 && fyle.allFyleMessageJoinWithStatus.first == self {
                managedObjectContext?.delete(fyle)
            }
        } else if isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }

    }
 
    
    public override func didSave() {
        super.didSave()
        
        defer {
            self.changedKeys.removeAll()
        }
        
        // Request the sending of a "read" receipt, if appropriate

        if !isDeleted, changedKeys.contains(Predicate.Key.wasOpened.rawValue), wasOpened {
            if self.receivedMessage.discussion?.localConfiguration.doSendReadReceipt ?? ObvMessengerSettings.Discussions.doSendReadReceipt {
                if let elements = self.receivedMessage.returnReceipt?.elements,
                   let contactIdentifier = try? self.receivedMessage.contactIdentity?.obvContactIdentifier,
                   let contactDeviceUIDs = self.receivedMessage.contactIdentity?.contactDeviceUIDs,
                   !contactDeviceUIDs.isEmpty {
                    let returnReceiptToSend = ObvReturnReceiptToSend(elements: elements,
                                                                     status: .read,
                                                                     contactIdentifier: contactIdentifier,
                                                                     contactDeviceUIDs: contactDeviceUIDs,
                                                                     attachmentNumber: index)
                    Task { await Self.observersHolder.newReturnReceiptToSendForReceivedFyleMessageJoinWithStatus(returnReceiptToSend: returnReceiptToSend) }
                } else {
                    assertionFailure()
                }
            }
        }
                
        // Request the sending of a "delivered" receipt, if appropriate

        let statusChanged = changedKeys.contains(FyleMessageJoinWithStatus.Predicate.Key.rawStatus.rawValue)

        if !isDeleted && (statusChanged || isInserted), status == .complete {
            if let elements = self.receivedMessage.returnReceipt?.elements,
               let contactIdentifier = try? self.receivedMessage.contactIdentity?.obvContactIdentifier,
               let contactDeviceUIDs = self.receivedMessage.contactIdentity?.contactDeviceUIDs,
               !contactDeviceUIDs.isEmpty {
                let returnReceiptToSend = ObvReturnReceiptToSend(elements: elements,
                                                                 status: .delivered,
                                                                 contactIdentifier: contactIdentifier,
                                                                 contactDeviceUIDs: contactDeviceUIDs,
                                                                 attachmentNumber: index)
                Task { await Self.observersHolder.newReturnReceiptToSendForReceivedFyleMessageJoinWithStatus(returnReceiptToSend: returnReceiptToSend) }
            } else {
                assertionFailure()
            }
        }
        
    }
    
}


// MARK: - ReceivedFyleMessageJoinWithStatus observers

public protocol ReceivedFyleMessageJoinWithStatusObserver {
    func newReturnReceiptToSendForReceivedFyleMessageJoinWithStatus(returnReceiptToSend: ObvReturnReceiptToSend) async
}


private actor ReceivedFyleMessageJoinWithStatusObserversHolder: ReceivedFyleMessageJoinWithStatusObserver {
    
    private var observers = [ReceivedFyleMessageJoinWithStatusObserver]()
    
    func addObserver(_ newObserver: ReceivedFyleMessageJoinWithStatusObserver) {
        self.observers.append(newObserver)
    }

    // Implementing ReceivedFyleMessageJoinWithStatusObserver
    
    func newReturnReceiptToSendForReceivedFyleMessageJoinWithStatus(returnReceiptToSend: ObvReturnReceiptToSend) async {
        for observer in observers {
            await observer.newReturnReceiptToSendForReceivedFyleMessageJoinWithStatus(returnReceiptToSend: returnReceiptToSend)
        }
    }
    
}

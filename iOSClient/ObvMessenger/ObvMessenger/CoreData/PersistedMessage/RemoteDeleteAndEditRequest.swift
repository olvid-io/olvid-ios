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
 

@objc(RemoteDeleteAndEditRequest)
final class RemoteDeleteAndEditRequest: NSManagedObject {
    
    private static let entityName = "RemoteDeleteAndEditRequest"
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "RemoteDeleteAndEditRequest")
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: Self.self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { RemoteDeleteAndEditRequest.makeError(message: message) }

    enum RequestType: Int {
        case delete = 0
        case edit = 1
    }
    
    // MARK: - Attributes

    @NSManaged private(set) var body: String?
    @NSManaged private var rawRequestType: Int
    @NSManaged private var remoteDeleterIdentity: Data?
    @NSManaged private var senderIdentifier: Data
    @NSManaged private var senderSequenceNumber: Int
    @NSManaged private var senderThreadIdentifier: UUID
    @NSManaged private(set) var serverTimestamp: Date
    
    // MARK: - Relationships

    @NSManaged private var discussion: PersistedDiscussion? // Expected to be non-nil
    
    // MARK: - Other variables
    
    var requestType: RequestType {
        get { RequestType(rawValue: rawRequestType)! }
        set { self.rawRequestType = newValue.rawValue }
    }

    var messageReferenceJSON: MessageReferenceJSON {
        MessageReferenceJSON(senderSequenceNumber: senderSequenceNumber, senderThreadIdentifier: senderThreadIdentifier, senderIdentifier: senderIdentifier)
    }
    
    // MARK: - Creating and deleting
    
    private convenience init(body: String?, requestType: RequestType, remoteDeleterIdentity: Data?, senderIdentifier: Data, senderSequenceNumber: Int, senderThreadIdentifier: UUID, serverTimestamp: Date, discussion: PersistedDiscussion) throws {
        
        assert((requestType == .delete && remoteDeleterIdentity != nil && body == nil) || (requestType == .edit && remoteDeleterIdentity == nil && body != nil))
        guard let context = discussion.managedObjectContext else { throw RemoteDeleteAndEditRequest.makeError(message: "Could not find context") }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: RemoteDeleteAndEditRequest.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.body = body
        self.requestType = requestType
        self.remoteDeleterIdentity = remoteDeleterIdentity
        self.senderIdentifier = senderIdentifier
        self.senderSequenceNumber = senderSequenceNumber
        self.senderThreadIdentifier = senderThreadIdentifier
        self.serverTimestamp = serverTimestamp
        self.discussion = discussion
        
    }
    
    /// This is the method to call to create a `RemoteDeleteAndEditRequest` instance of type `edit`. Note that this method only creates a new instance if appropriate.
    ///
    /// In the following situations, this method does nothing:
    /// - An older entry of type "delete" is found with the same constaints.
    /// - A more recent entry (of any type) is found with the same constraints
    ///
    /// In all other cases, this method :
    /// - Deletes any existing entry with the same constraints
    /// - Creates a new entry using the parameters passed to that method.
    static func createEditRequestIfAppropriate(body: String?, messageReference: MessageReferenceJSON, serverTimestamp: Date, discussion: PersistedDiscussion) throws {
        
        // If an older delete request exists, we ignore this request whatever its type
        guard try countDeleteRequestsOlderThanServerTimestamp(serverTimestamp,
                                                              discussion: discussion,
                                                              senderIdentifier: messageReference.senderIdentifier,
                                                              senderThreadIdentifier: messageReference.senderThreadIdentifier,
                                                              senderSequenceNumber: messageReference.senderSequenceNumber) == 0 else { return }
        
        // We ignore this new edit request if there exists a more recent request
        guard try countRequestsMoreRecentThanServerTimestamp(serverTimestamp,
                                                             discussion: discussion,
                                                             senderIdentifier: messageReference.senderIdentifier,
                                                             senderThreadIdentifier: messageReference.senderThreadIdentifier,
                                                             senderSequenceNumber: messageReference.senderSequenceNumber) == 0 else { return }
        
        // If we reach this point, we will create a new edit request. We first delete any previous request.
        try deleteAllRequests(discussion: discussion, senderIdentifier: messageReference.senderIdentifier, senderThreadIdentifier: messageReference.senderThreadIdentifier, senderSequenceNumber: messageReference.senderSequenceNumber)
        _ = try RemoteDeleteAndEditRequest(body: body,
                                           requestType: .edit,
                                           remoteDeleterIdentity: nil,
                                           senderIdentifier: messageReference.senderIdentifier,
                                           senderSequenceNumber: messageReference.senderSequenceNumber,
                                           senderThreadIdentifier: messageReference.senderThreadIdentifier,
                                           serverTimestamp: serverTimestamp,
                                           discussion: discussion)
    }
    
    
    /// This is the method to call to create a `RemoteDeleteAndEditRequest` instance of type `delete`.
    ///
    /// This method :
    /// - Deletes any existing entry with the same constraints
    /// - Creates a new entry using the parameters passed to that method.
    static func createDeleteRequest(remoteDeleterIdentity: Data, messageReference: MessageReferenceJSON, serverTimestamp: Date, discussion: PersistedDiscussion) throws {
        
        try deleteAllRequests(discussion: discussion,
                              senderIdentifier: messageReference.senderIdentifier,
                              senderThreadIdentifier: messageReference.senderThreadIdentifier,
                              senderSequenceNumber: messageReference.senderSequenceNumber)
        _ = try RemoteDeleteAndEditRequest(body: nil,
                                           requestType: .delete,
                                           remoteDeleterIdentity: remoteDeleterIdentity,
                                           senderIdentifier: messageReference.senderIdentifier,
                                           senderSequenceNumber: messageReference.senderSequenceNumber,
                                           senderThreadIdentifier: messageReference.senderThreadIdentifier,
                                           serverTimestamp: serverTimestamp,
                                           discussion: discussion)
    }
    
    
    func delete() throws {
        guard let context = self.managedObjectContext else { throw makeError(message: "Cannot find context") }
        context.delete(self)
    }

    
    // MARK: - Convenience DB getters

    @nonobjc private static func fetchRequest() -> NSFetchRequest<RemoteDeleteAndEditRequest> {
        return NSFetchRequest<RemoteDeleteAndEditRequest>(entityName: RemoteDeleteAndEditRequest.entityName)
    }

    
    private struct Predicate {
        
        enum Key: String {
            case senderIdentifier = "senderIdentifier"
            case senderThreadIdentifier = "senderThreadIdentifier"
            case senderSequenceNumber = "senderSequenceNumber"
            case rawRequestType = "rawRequestType"
            case serverTimestamp = "serverTimestamp"
            case discussion = "discussion"
        }
        
        static func withPrimaryKey(discussion: PersistedDiscussion, senderIdentifier: Data, senderThreadIdentifier: UUID, senderSequenceNumber: Int) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "%K == %@", Key.discussion.rawValue, discussion),
                NSPredicate(Key.senderIdentifier, EqualToData: senderIdentifier),
                NSPredicate(Key.senderThreadIdentifier, EqualToUuid: senderThreadIdentifier),
                NSPredicate(Key.senderSequenceNumber, EqualToInt: senderSequenceNumber),
            ])
        }
        static func olderThanServerTimestamp(_ serverTimestamp: Date) -> NSPredicate {
            NSPredicate(format: "%K < %@", Key.serverTimestamp.rawValue, serverTimestamp as NSDate)
        }
        static func moreRecentThanServerTimestamp(_ serverTimestamp: Date) -> NSPredicate {
            NSPredicate(format: "%K > %@", Key.serverTimestamp.rawValue, serverTimestamp as NSDate)
        }
        static func ofRequestType(_ requestType: RequestType) -> NSPredicate {
            NSPredicate(Key.rawRequestType, EqualToInt: requestType.rawValue)
        }
        static var withoutAssociatedDiscussion: NSPredicate {
            NSPredicate(format: "%K == NIL", Key.discussion.rawValue)
        }
    }
    
    
    private static func countDeleteRequestsOlderThanServerTimestamp(_ serverTimestamp: Date, discussion: PersistedDiscussion, senderIdentifier: Data, senderThreadIdentifier: UUID, senderSequenceNumber: Int) throws -> Int {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context") }
        let request: NSFetchRequest<RemoteDeleteAndEditRequest> = RemoteDeleteAndEditRequest.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withPrimaryKey(discussion: discussion, senderIdentifier: senderIdentifier, senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber),
            Predicate.olderThanServerTimestamp(serverTimestamp),
            Predicate.ofRequestType(.delete),
        ])
        return try context.count(for: request)
    }
    
    
    private static func countRequestsMoreRecentThanServerTimestamp(_ serverTimestamp: Date, discussion: PersistedDiscussion, senderIdentifier: Data, senderThreadIdentifier: UUID, senderSequenceNumber: Int) throws -> Int {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context") }
        let request: NSFetchRequest<RemoteDeleteAndEditRequest> = RemoteDeleteAndEditRequest.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withPrimaryKey(discussion: discussion, senderIdentifier: senderIdentifier, senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber),
            Predicate.moreRecentThanServerTimestamp(serverTimestamp),
        ])
        return try context.count(for: request)
    }
    
    
    private static func deleteAllRequests(discussion: PersistedDiscussion, senderIdentifier: Data, senderThreadIdentifier: UUID, senderSequenceNumber: Int) throws {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context") }
        let request: NSFetchRequest<RemoteDeleteAndEditRequest> = RemoteDeleteAndEditRequest.fetchRequest()
        request.predicate = Predicate.withPrimaryKey(discussion: discussion, senderIdentifier: senderIdentifier, senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber)
        let results = try context.fetch(request)
        for result in results {
            context.delete(result)
        }
    }
    
    
    static func getRemoteDeleteAndEditRequest(discussion: PersistedDiscussion, senderIdentifier: Data, senderThreadIdentifier: UUID, senderSequenceNumber: Int) throws -> RemoteDeleteAndEditRequest? {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context") }
        let request: NSFetchRequest<RemoteDeleteAndEditRequest> = RemoteDeleteAndEditRequest.fetchRequest()
        request.predicate = Predicate.withPrimaryKey(discussion: discussion, senderIdentifier: senderIdentifier, senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber)
        let results = try context.fetch(request)
        switch results.count {
        case 0, 1:
            return results.first
        default:
            // We expect 0 or 1 request in database
            assertionFailure()
            // In production, we return either a deletion request or the most recent edit request
            return results.first(where: { $0.requestType == .delete }) ?? results.sorted(by: { $0.serverTimestamp > $1.serverTimestamp }).first
        }
    }
    
    
    static func deleteRequestsOlderThanDate(_ date: Date, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = RemoteDeleteAndEditRequest.fetchRequest()
        request.predicate = Predicate.olderThanServerTimestamp(date)
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(batchDeleteRequest)
    }
    
    
    static func deleteOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = RemoteDeleteAndEditRequest.fetchRequest()
        request.predicate = Predicate.withoutAssociatedDiscussion
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(batchDeleteRequest)
    }
    
}

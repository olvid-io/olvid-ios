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
import os.log
import OlvidUtils
import ObvTypes
import ObvSettings

@objc(RemoteRequestSavedForLater)
final class RemoteRequestSavedForLater: NSManagedObject {
    
    private static let entityName = "RemoteRequestSavedForLater"
    private static let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "FullSyncOperation")
    
    public enum RequestType: Int {
        case delete = 0
        case edit = 1
        case reaction = 2
    }
    
    // MARK: Attributes
    
    @NSManaged private var rawRequesterIdentity: Data // Either the owned identity of the discussion, or one of her contacts
    @NSManaged private var rawRequestType: Int
    @NSManaged private var senderIdentifier: Data // From MessageReferenceJSON
    @NSManaged private var senderSequenceNumber: Int // From MessageReferenceJSON
    @NSManaged private var senderThreadIdentifier: UUID // From MessageReferenceJSON
    @NSManaged private var serializedMessageJSON: Data?
    @NSManaged private(set) var serverTimestamp: Date
    
    // MARK: Relationships
    
    @NSManaged private var discussion: PersistedDiscussion? // Expected to be non-nil
    
    // MARK: Other variables
    
    /// Expected to be non-nil
    private(set) var requestType: RequestType? {
        get {
            RequestType(rawValue: rawRequestType)
        }
        set {
            guard let newValue else { assertionFailure(); return }
            self.rawRequestType = newValue.rawValue
        }
    }
    
    
    /// Expected to be non-nil
    private(set) var requesterCryptoId: ObvCryptoId? {
        get {
            try? ObvCryptoId(identity: rawRequesterIdentity)
        }
        set {
            guard let newValue else { assertionFailure(); return }
            self.rawRequesterIdentity = newValue.getIdentity()
        }
    }
    
    
    // MARK: - Init
    
    private convenience init(requestType: RequestType, requesterCryptoId: ObvCryptoId, senderIdentifier: Data, senderSequenceNumber: Int, senderThreadIdentifier: UUID, serverTimestamp: Date, serializedMessageJSON: Data?, for discussion: PersistedDiscussion) throws {
        
        guard let context = discussion.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.requesterCryptoId = requesterCryptoId
        self.requestType = requestType
        self.senderIdentifier = senderIdentifier
        self.senderSequenceNumber = senderSequenceNumber
        self.senderThreadIdentifier = senderThreadIdentifier
        self.serverTimestamp = serverTimestamp
        self.serializedMessageJSON = serializedMessageJSON
        
        self.discussion = discussion
        
    }
    
    
    /// This method is called after checking that the contact or the owned identity requesting the wipe is allowed to do so.
    /// When creating a wipe request, we delete all other previous requests concering this message before inserting this wipe request.
    static func createWipeOrDeleteRequest(requesterCryptoId: ObvCryptoId, messageReference: MessageReferenceJSON, serverTimestamp: Date, discussion: PersistedDiscussion) throws {
        
        try? deleteAllRemoteRequestsSavedForLater(for: messageReference, in: discussion)
        
        let _ = try RemoteRequestSavedForLater(
            requestType: .delete,
            requesterCryptoId: requesterCryptoId,
            senderIdentifier: messageReference.senderIdentifier,
            senderSequenceNumber: messageReference.senderSequenceNumber,
            senderThreadIdentifier: messageReference.senderThreadIdentifier,
            serverTimestamp: serverTimestamp,
            serializedMessageJSON: nil, // Can be reconstructed
            for: discussion)
        
    }
    
    
    /// At this point, most checks have been made on the validity of the edit request. One (important) is missing: the fact that the requester is the creator of the message. This check will be performed when applying this request on receiving the message.
    static func createEditRequest(requesterCryptoId: ObvCryptoId, updateMessageJSON: UpdateMessageJSON, serverTimestamp: Date, discussion: PersistedDiscussion) throws {
        
        let messageToEdit = updateMessageJSON.messageToEdit
        
        // If there exists a delete request for this message, we discard this edit request
        
        let deleteRequests = try RemoteRequestSavedForLater.fetchAllRemoteRequestsSavedForLater(for: messageToEdit, in: discussion, ofType: .delete)
        guard deleteRequests.isEmpty else {
            return
        }
        
        // If there exist a more recent edit request, we discard this edit request
        
        let previousEditRequest = try RemoteRequestSavedForLater.fetchAllRemoteRequestsSavedForLater(for: messageToEdit, in: discussion, ofType: .edit)
        guard !previousEditRequest.contains(where: { $0.serverTimestamp > serverTimestamp }) else {
            return
        }
        
        // At this point, we can save this request for later
        
        let serializedMessageJSON = try updateMessageJSON.jsonEncode()
        
        let _ = try RemoteRequestSavedForLater(
            requestType: .edit,
            requesterCryptoId: requesterCryptoId,
            senderIdentifier: messageToEdit.senderIdentifier,
            senderSequenceNumber: messageToEdit.senderSequenceNumber,
            senderThreadIdentifier: messageToEdit.senderThreadIdentifier,
            serverTimestamp: serverTimestamp,
            serializedMessageJSON: serializedMessageJSON,
            for: discussion)
        
    }
    
    
    static func createSetOrUpdateReactionRequest(requesterCryptoId: ObvCryptoId, reactionJSON: ReactionJSON, serverTimestamp: Date, discussion: PersistedDiscussion) throws {
        
        let messageToEdit = reactionJSON.messageReference
        
        // If there exists a delete request for this message, we discard this edit request
        
        let deleteRequests = try RemoteRequestSavedForLater.fetchAllRemoteRequestsSavedForLater(for: messageToEdit, in: discussion, ofType: .delete)
        guard deleteRequests.isEmpty else {
            return
        }
        
        // Save the request for later
        
        let serializedMessageJSON = try reactionJSON.jsonEncode()
        
        let _ = try RemoteRequestSavedForLater(
            requestType: .reaction,
            requesterCryptoId: requesterCryptoId,
            senderIdentifier: messageToEdit.senderIdentifier,
            senderSequenceNumber: messageToEdit.senderSequenceNumber,
            senderThreadIdentifier: messageToEdit.senderThreadIdentifier,
            serverTimestamp: serverTimestamp,
            serializedMessageJSON: serializedMessageJSON,
            for: discussion)
        
    }
    
    
    
    private func delete() throws {
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        context.delete(self)
    }
    
    // MARK: - Applying remote requests saved for later on a newly created message
        
    static func applyRemoteRequestsSavedForLater(for message: PersistedMessage) throws {
        
        guard let messageReference = message.toMessageReferenceJSON() else {
            throw ObvUICoreDataError.couldNotDetermineMessageReferenceFromPersistedMessage
        }
        
        guard let discussion = message.discussion else {
            throw ObvUICoreDataError.discussionIsNil
        }
        
        defer {
            try? deleteAllRemoteRequestsSavedForLater(for: messageReference, in: discussion)
        }
        
        // Fetch all remote requests concerning this message. The most recent is last in the returned array, so we can process them in order.
        
        let remoteRequestsSavedForLater = try fetchAllRemoteRequestsSavedForLater(for: messageReference, in: discussion)
        
        guard !remoteRequestsSavedForLater.isEmpty else {
            return
        }
        
        // If there is a delete request, we only process that request
        
        let deleteOrWipeRequests = remoteRequestsSavedForLater.filter { $0.requestType == .delete }
        let otherRequests = remoteRequestsSavedForLater.filter { $0.requestType != .delete }
        
        for deleteOrWipeRequest in deleteOrWipeRequests {
            
            do {
                try deleteOrWipeRequest.apply(to: message)
                // The delete request succeeded, we can return
                return
            } catch {
                // The delete request failed, we delete it and continue with the next one
                try deleteOrWipeRequest.delete()
            }
            
        }
        
        // If we reach this point, no delete request was successfuly applied. We apply the other requests
        
        for request in otherRequests {
            
            try? request.apply(to: message)
            try? request.delete()

        }

    }
    
    
    private func apply(to message: PersistedMessage) throws {
        
        guard let context = message.managedObjectContext else {
            throw ObvUICoreDataError.noContext
        }
        
        guard let requestType = self.requestType else {
            throw ObvUICoreDataError.couldNotDetermineRequestType
        }
        
        guard let requesterCryptoId else {
            throw ObvUICoreDataError.couldNotDetermineRequester
        }
        
        guard let discussion = message.discussion else {
            throw ObvUICoreDataError.discussionIsNil
        }
        
        guard let discussionOwnedIdentity = discussion.ownedIdentity else {
            throw ObvUICoreDataError.couldNotDetermineOwnedCryptoId
        }
        
        let oneToOneIdentifier: OneToOneIdentifierJSON? = try (discussion as? PersistedOneToOneDiscussion)?.oneToOneIdentifier
        
        let groupIdentifier: GroupIdentifier?
        if let group = (discussion as? PersistedGroupDiscussion)?.contactGroup {
            let groupV1Identifier = try GroupV1Identifier(groupUid: group.groupUid, groupOwner: ObvCryptoId(identity: group.ownerIdentity))
            groupIdentifier = .groupV1(groupV1Identifier: groupV1Identifier)
        } else if let group = (discussion as? PersistedGroupV2Discussion)?.group {
            let groupV2Identifier = group.groupIdentifier
            groupIdentifier = .groupV2(groupV2Identifier: groupV2Identifier)
        } else {
            groupIdentifier = nil
        }
        
        guard (oneToOneIdentifier != nil || groupIdentifier != nil) && (oneToOneIdentifier == nil || groupIdentifier == nil) else {
            assertionFailure()
            throw ObvUICoreDataError.unexpectedIdentifiers
        }
        
        if requesterCryptoId == discussionOwnedIdentity.cryptoId {
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(
                cryptoId: requesterCryptoId,
                within: context) else {
                throw ObvUICoreDataError.couldNotFindOwnedIdentity
            }
            
            switch requestType {
                
            case .delete:
                
                let deleteMessagesJSON = try DeleteMessagesJSON(persistedMessagesToDelete: [message])
                
                _ = try ownedIdentity.processWipeMessageRequestFromOtherOwnedDevice(
                    deleteMessagesJSON: deleteMessagesJSON,
                    messageUploadTimestampFromServer: serverTimestamp)
                
            case .edit:
                
                guard let serializedMessageJSON else {
                    assertionFailure("Edit request *must* be stored")
                    throw ObvUICoreDataError.couldNotFindSerializedMessageJSON
                }
                
                let updateMessageJSON = try UpdateMessageJSON.jsonDecode(serializedMessageJSON)
                
                _ = try ownedIdentity.processUpdateMessageRequestFromThisOwnedIdentity(
                    updateMessageJSON: updateMessageJSON,
                    messageUploadTimestampFromServer: serverTimestamp)
                
            case .reaction:
                
                guard let serializedMessageJSON else {
                    assertionFailure("Reaction request *must* be stored")
                    throw ObvUICoreDataError.couldNotFindSerializedMessageJSON
                }
                
                let reactionJSON = try ReactionJSON.jsonDecode(serializedMessageJSON)
                
                _ = try ownedIdentity.processSetOrUpdateReactionOnMessageRequestFromThisOwnedIdentity(
                    reactionJSON: reactionJSON,
                    messageUploadTimestampFromServer: serverTimestamp)
                
            }
            
        } else {
            
            guard let contact = try PersistedObvContactIdentity.get(
                contactCryptoId: requesterCryptoId,
                ownedIdentityCryptoId: discussionOwnedIdentity.cryptoId,
                whereOneToOneStatusIs: .any,
                within: context) else {
                throw ObvUICoreDataError.couldNotFindContactWithId(contactIdentifier: .init(contactCryptoId: requesterCryptoId, ownedCryptoId: discussionOwnedIdentity.cryptoId))
            }
            
            switch requestType {
                
            case .delete:
                
                let deleteMessagesJSON = try DeleteMessagesJSON(persistedMessagesToDelete: [message])
                
                _ = try contact.processWipeMessageRequestFromThisContact(
                    deleteMessagesJSON: deleteMessagesJSON,
                    messageUploadTimestampFromServer: serverTimestamp)
                
            case .edit:
                
                guard let serializedMessageJSON else {
                    assertionFailure("Edit request *must* be stored")
                    throw ObvUICoreDataError.couldNotFindSerializedMessageJSON
                }
                
                let updateMessageJSON = try UpdateMessageJSON.jsonDecode(serializedMessageJSON)
                
                _ = try contact.processUpdateMessageRequestFromThisContact(
                    updateMessageJSON: updateMessageJSON,
                    messageUploadTimestampFromServer: serverTimestamp)
                
            case .reaction:
                
                guard let serializedMessageJSON else {
                    assertionFailure("Reaction request *must* be stored")
                    throw ObvUICoreDataError.couldNotFindSerializedMessageJSON
                }
                
                let reactionJSON = try ReactionJSON.jsonDecode(serializedMessageJSON)
                
                _ = try contact.processSetOrUpdateReactionOnMessageRequestFromThisContact(
                    reactionJSON: reactionJSON,
                    messageUploadTimestampFromServer: serverTimestamp,
                    overrideExistingReaction: true)
                
            }
            
        }
        
    }
    
    
    // MARK: - Convenience DB getters
    
    private struct Predicate {
        enum Key: String {
            // Attributes
            case rawRequesterIdentity = "rawRequesterIdentity"
            case rawRequestType = "rawRequestType"
            case senderIdentifier = "senderIdentifier"
            case senderSequenceNumber = "senderSequenceNumber"
            case senderThreadIdentifier = "senderThreadIdentifier"
            case serverTimestamp = "serverTimestamp"
            // Relationships
            case discussion = "discussion"
        }
        static func forMessageReference(_ messageReference: MessageReferenceJSON) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(Key.senderSequenceNumber, EqualToInt: messageReference.senderSequenceNumber),
                NSPredicate(Key.senderThreadIdentifier, EqualToUuid: messageReference.senderThreadIdentifier),
                NSPredicate(Key.senderIdentifier, EqualToData: messageReference.senderIdentifier),
            ])
        }
        static func withinDiscussion(_ discussion: PersistedDiscussion) -> NSPredicate {
            NSPredicate(Key.discussion, equalTo: discussion)
        }
        static func withRequestType(_ requestType: RequestType) -> NSPredicate {
            NSPredicate(Key.rawRequestType, EqualToInt: requestType.rawValue)
        }
        static func withServerTimestamp(earlierThan date: Date) -> NSPredicate {
            NSPredicate(Key.serverTimestamp, earlierThan: date)
        }
    }
    
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<RemoteRequestSavedForLater> {
        return NSFetchRequest<RemoteRequestSavedForLater>(entityName: Self.entityName)
    }
    
    
    private static func deleteAllRemoteRequestsSavedForLater(for messageReference: MessageReferenceJSON, in discussion: PersistedDiscussion) throws {
        let remoteRequestsSavedForLater = try fetchAllRemoteRequestsSavedForLater(for: messageReference, in: discussion)
        remoteRequestsSavedForLater.forEach { remoteRequest in
            try? remoteRequest.delete()
        }
    }
    
    
    private static func fetchAllRemoteRequestsSavedForLater(for messageReference: MessageReferenceJSON, in discussion: PersistedDiscussion) throws -> [RemoteRequestSavedForLater] {
        guard let context = discussion.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        let request: NSFetchRequest<RemoteRequestSavedForLater> = RemoteRequestSavedForLater.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.forMessageReference(messageReference),
            Predicate.withinDiscussion(discussion),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.serverTimestamp.rawValue, ascending: true)] // Most recent last
        request.fetchBatchSize = 1_000
        let remoteRequestsSavedForLater = try context.fetch(request)
        return remoteRequestsSavedForLater
    }
    
    
    private static func fetchAllRemoteRequestsSavedForLater(for messageReference: MessageReferenceJSON, in discussion: PersistedDiscussion, ofType requestType: RequestType) throws -> [RemoteRequestSavedForLater] {
        guard let context = discussion.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        let request: NSFetchRequest<RemoteRequestSavedForLater> = RemoteRequestSavedForLater.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.forMessageReference(messageReference),
            Predicate.withinDiscussion(discussion),
            Predicate.withRequestType(requestType),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.serverTimestamp.rawValue, ascending: true)] // Most recent last
        request.fetchBatchSize = 1_000
        let remoteRequestsSavedForLater = try context.fetch(request)
        return remoteRequestsSavedForLater
    }
    
    
    static func deleteRemoteRequestsSavedForLaterEarlierThan(_ deletionDate: Date, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<RemoteRequestSavedForLater> = RemoteRequestSavedForLater.fetchRequest()
        request.predicate = Predicate.withServerTimestamp(earlierThan: deletionDate)
        request.propertiesToFetch = []
        let items = try context.fetch(request)
        items.forEach {
            do {
                try $0.delete()
            } catch {
                assertionFailure()
                os_log("Could not delete an old RemoteRequestSavedForLater: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            }
        }
    }
    
}

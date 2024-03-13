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
import OlvidUtils
import UniformTypeIdentifiers

@objc(PersistedDraft)
public final class PersistedDraft: NSManagedObject, ObvErrorMaker, ObvIdentifiableManagedObject {
        
    public static let entityName = "PersistedDraft"
    public static let errorDomain = "PersistedDraft"

    // MARK: Attributes
    
    @NSManaged public private(set) var body: String?
    @NSManaged private var permanentUUID: UUID
    @NSManaged private var rawExistenceDuration: NSNumber?
    @NSManaged private var rawVisibilityDuration: NSNumber?
    @NSManaged public private(set) var readOnce: Bool
    @NSManaged private(set) var sendRequested: Bool

    // MARK: Relationships
    
    @NSManaged public private(set) var discussion: PersistedDiscussion
    @NSManaged public private(set) var mentions: Set<PersistedUserMentionInDraft>
    @NSManaged public private(set) var replyTo: PersistedMessage?
    @NSManaged private(set) var unsortedDraftFyleJoins: Set<PersistedDraftFyleJoin>

    // MARK: Computed Properties
    
    public var objectPermanentID: ObvManagedObjectPermanentID<PersistedDraft> {
        ObvManagedObjectPermanentID<PersistedDraft>(uuid: self.permanentUUID)
    }
    
    public var fyleJoins: [FyleJoin] {
        unsortedDraftFyleJoins.sorted(by: { $0.index < $1.index })
    }

    public var fyleJoinsNotPreviews: [FyleJoin] {
        unsortedDraftFyleJoins
            .filter { $0.uti != UTType.olvidPreviewUti }
            .sorted(by: { $0.index < $1.index })
    }

    // MARK: Other variables
    
    private var changedKeys = Set<String>()
    
    public var existenceDuration: TimeInterval? {
        get {
            guard let seconds = rawExistenceDuration?.intValue else { return nil }
            return TimeInterval(seconds)
        }
        set {
            self.rawExistenceDuration = (newValue == nil ? nil : NSNumber(value: newValue!) )
        }
    }

    public var visibilityDuration: TimeInterval? {
        get {
            guard let seconds = rawVisibilityDuration?.intValue else { return nil }
            return TimeInterval(seconds)
        }
        set {
            self.rawVisibilityDuration = (newValue == nil ? nil : NSNumber(value: newValue!) )
        }
    }

    
    public var isNotEmpty: Bool {
        let bodyIsNotEmpty = (body != nil && !body!.isEmpty)
        let joinsNotEmpty = !unsortedDraftFyleJoins.isEmpty
        return bodyIsNotEmpty || joinsNotEmpty
    }
    
}


// MARK: - Initializer

extension PersistedDraft {
    
    convenience init(within discussion: PersistedDiscussion) throws {
        guard let context = discussion.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedDraft.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.body = nil
        self.permanentUUID = UUID()
        self.sendRequested = false
        self.discussion = discussion
        self.replyTo = nil
        self.unsortedDraftFyleJoins = Set<PersistedDraftFyleJoin>()
        self.readOnce = false
        self.visibilityDuration = nil
        self.existenceDuration = nil
        self.mentions = Set<PersistedUserMentionInDraft>()
        
        self.discussion.unarchive()
    }
    
}


// MARK: - Linking Fyle to the draft

extension PersistedDraft {

    public func removeDraftFyleJoin(_ draftFyleJoin: PersistedDraftFyleJoin) {
        assert(unsortedDraftFyleJoins.contains(draftFyleJoin))
        let fyle = draftFyleJoin.fyle
        self.unsortedDraftFyleJoins.remove(draftFyleJoin)
        fyle?.remove(draftFyleJoin)
        self.managedObjectContext?.delete(draftFyleJoin)
    }
    
    
    public func removeAllDraftFyleJoin() {
        unsortedDraftFyleJoins
            .forEach { removeDraftFyleJoin($0) }
    }
    
    public func removeAllDraftFyleJoinNotPreviews() {
        unsortedDraftFyleJoins
            .filter { $0.uti != UTType.olvidPreviewUti }
            .forEach { removeDraftFyleJoin($0) }
    }
    
    public func removePreviewDraftFyleJoin() {
        unsortedDraftFyleJoins
            .filter { $0.uti == UTType.olvidPreviewUti }
            .forEach { removeDraftFyleJoin($0) }
    }
}

extension PersistedDraft {
    /// Helper method that deletes and removes all associated mentions (``PersistedDraftMentionInDraft``) from ``mentions``
    private func deleteAllAssociatedMentions() {
        let oldMentions = mentions
        oldMentions
            .forEach { try? $0.deleteUserMention() }
        if !mentions.isEmpty {
            mentions = []
        }
    }
}


// MARK: - Other methods

extension PersistedDraft {
    
    public func reset() {
        
        self.body = nil
        deleteAllAssociatedMentions()

        self.replyTo = nil

        if self.sendRequested {
            self.sendRequested = false
            self.changedKeys.insert(Predicate.Key.sendRequested.rawValue)
        }
        resetExpiration()
        removeAllDraftFyleJoin()
        
    }

    private func resetExpiration() {
        self.readOnce = false
        self.existenceDuration = nil
        self.visibilityDuration = nil
        assert(!hasSomeExpiration)
    }
    
    public func send() {
        self.sendRequested = true
        self.changedKeys.insert(Predicate.Key.sendRequested.rawValue)
    }
    
    public func forceResend() {
        sendNewDraftToSendNotification()
    }
    
    
    public func replaceContentWith(newBody: String, newMentions: Set<MessageJSON.UserMention>) {

        let (trimmedBody, mentionsInTrimmedBody) = newBody.trimmingWhitespacesAndNewlines(updating: Array(newMentions))
        
        if self.body != trimmedBody {
            self.body = trimmedBody
            if let resultingBody = self.body, !resultingBody.isEmpty {
                self.discussion.resetTimestampOfLastMessageIfCurrentValueIsEarlierThan(Date())
                self.discussion.unarchive()
            }
        }
        
        deleteAllAssociatedMentions()
        mentionsInTrimmedBody.forEach { mention in
            _ = try? PersistedUserMentionInDraft(mention: mention, draft: self)
        }
        
    }
    

    public func appendContentToBody(_ content: String) {
        guard !content.isEmpty else { return }
        if self.body == nil {
            self.body = ""
        }
        self.body?.append(content)
        // We don't need to reset the mentions since we are only appending characters to the existing body.
        self.discussion.resetTimestampOfLastMessageIfCurrentValueIsEarlierThan(Date())
        self.discussion.unarchive()
    }

    public var hasSomeExpiration: Bool {
        readOnce == true || existenceDuration != nil || visibilityDuration != nil
    }

    public func removeReplyTo() {
        guard self.replyTo != nil else { return }
        self.replyTo = nil
    }
    
    public func setReplyTo(to message: PersistedMessage) {
        guard self.replyTo != message else { return }
        self.replyTo = message
    }
    
}

extension PersistedDraft {
    public func update(with configuration: PersistedDiscussionSharedConfigurationValue?) {
        if let configuration = configuration {
            switch configuration {
            case .readOnce(readOnce: let readOnce):
                self.readOnce = readOnce
            case .existenceDuration(existenceDuration: let existenceDuration):
                self.existenceDuration = existenceDuration
            case .visibilityDuration(visibilityDuration: let visibilityDuration):
                self.visibilityDuration = visibilityDuration
            }
        } else {
            resetExpiration()
        }
    }
}


// MARK: - Convenience DB getters

extension PersistedDraft {
    
    struct Predicate {
        enum Key: String {
            case permanentUUID = "permanentUUID"
            case sendRequested = "sendRequested"
            case discussion = "discussion"
            case replyTo = "replyTo"
        }
        static func persistedDraft(withObjectID objectID: TypeSafeManagedObjectID<PersistedDraft>) -> NSPredicate {
            NSPredicate(withObjectID: objectID.objectID)
        }
        static func whereSendRequestedIs(_ sendRequested: Bool) -> NSPredicate {
            NSPredicate(Key.sendRequested, is: sendRequested)
        }
        static func forDiscussion(_ discussion: PersistedDiscussion) -> NSPredicate {
            NSPredicate(Key.discussion, equalTo: discussion)
        }
        static func withPermanentID(_ permanentID: ObvManagedObjectPermanentID<PersistedDraft>) -> NSPredicate {
            NSPredicate(Key.permanentUUID, EqualToUuid: permanentID.uuid)
        }
        static func whereReplyToIsMessage(_ message: PersistedMessage) -> NSPredicate {
            NSPredicate(Key.replyTo, equalTo: message)
        }
    }

    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedDraft> {
        return NSFetchRequest<PersistedDraft>(entityName: PersistedDraft.entityName)
    }
    
    
    public static func getManagedObject(withPermanentID permanentID: ObvManagedObjectPermanentID<PersistedDraft>, within context: NSManagedObjectContext) throws -> PersistedDraft? {
        let request: NSFetchRequest<PersistedDraft> = PersistedDraft.fetchRequest()
        request.predicate = Predicate.withPermanentID(permanentID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func get(objectID: TypeSafeManagedObjectID<PersistedDraft>, within context: NSManagedObjectContext) throws -> PersistedDraft? {
        let request: NSFetchRequest<PersistedDraft> = PersistedDraft.fetchRequest()
        request.predicate = Predicate.persistedDraft(withObjectID: objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    /// Returns all `PersistedDraft` entities such that `sendRequested` is `true`, regardless of the owned identity.
    public static func getAllUnsent(within context: NSManagedObjectContext) throws -> [PersistedDraft] {
        let request: NSFetchRequest<PersistedDraft> = PersistedDraft.fetchRequest()
        request.predicate = Predicate.whereSendRequestedIs(true)
        let unsentDrafts = try context.fetch(request)
        return unsentDrafts
    }
    

    public static func getPersistedDraft(of discussion: PersistedDiscussion, within context: NSManagedObjectContext) throws -> PersistedDraft? {
        let request: NSFetchRequest<PersistedDraft> = PersistedDraft.fetchRequest()
        request.predicate = Predicate.forDiscussion(discussion)
        request.fetchBatchSize = 1
        return try context.fetch(request).first
    }
    
    
    public static func getObjectIDsOfAllDraftsReplyingTo(message: PersistedMessage) throws -> Set<TypeSafeManagedObjectID<PersistedDraft>> {
        let request: NSFetchRequest<PersistedDraft> = PersistedDraft.fetchRequest()
        guard let context = message.managedObjectContext else { assertionFailure(); throw Self.makeError(message: "Could not find context") }
        request.predicate = Predicate.whereReplyToIsMessage(message)
        request.propertiesToFetch = []
        request.fetchBatchSize = 1_000
        let drafts = try context.fetch(request)
        return Set(drafts.map({ $0.typedObjectID }))
    }
}


// Reacting to changes

extension PersistedDraft {
    
    // MARK: - Deleting Fyle when deleting the last ReceivedFyleMessageJoinWithStatus
    
    public override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
        }
        
        if changedKeys.contains(Predicate.Key.sendRequested.rawValue) {
            if sendRequested {
                sendNewDraftToSendNotification()
            } else {
                ObvMessengerCoreDataNotification.draftWasSent(persistedDraftObjectID: typedObjectID)
                    .postOnDispatchQueue()
            }
        }
    }
    
    private func sendNewDraftToSendNotification() {
        ObvMessengerCoreDataNotification.newDraftToSend(draftPermanentID: objectPermanentID)
            .postOnDispatchQueue()
    }
    
}

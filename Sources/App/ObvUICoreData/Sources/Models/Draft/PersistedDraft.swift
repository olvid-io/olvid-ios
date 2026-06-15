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
import OlvidUtils
import UniformTypeIdentifiers
import ObvAppTypes
import ObvTypes

@objc(PersistedDraft)
public final class PersistedDraft: NSManagedObject, ObvIdentifiableManagedObject {
        
    public static let entityName = "PersistedDraft"

    // MARK: Attributes

    @NSManaged private var body: String?
    @NSManaged private var permanentUUID: UUID
    @NSManaged private var rawExistenceDuration: NSNumber?
    @NSManaged private var rawVisibilityDuration: NSNumber?
    @NSManaged public private(set) var readOnce: Bool
    @NSManaged private(set) var sendRequested: Bool // 2024-11-27 legacy attribute that shall be dropped

    // MARK: Relationships
    
    @NSManaged public private(set) var discussion: PersistedDiscussion
    @NSManaged public private(set) var mentions: Set<PersistedUserMentionInDraft>
    @NSManaged public private(set) var replyTo: PersistedMessage?
    @NSManaged private(set) var unsortedDraftFyleJoins: Set<PersistedDraftFyleJoin>

    // MARK: Computed Properties
    
    var bodyAndMentions: StringAndUserMentions? {
        
        guard let body = self.body, !body.isEmpty else { return nil }
                
        var mentions = [StringAndUserMentions.UserMention]()
        for mention in self.mentions {
            do {
                let userMention = try mention.userMention
                mentions.append(userMention)
            } catch {
                assertionFailure() // In production, continue with the next mention
            }
        }
        
        let stringAndUserMentions = StringAndUserMentions(body: body, mentions: mentions)

        return stringAndUserMentions
        
    }
    
    public var attributedBody: AttributedString? {
        return bodyAndMentions?.attributedString
    }
    

    /// Expected to be non-nil, unless this `NSManagedObject` is deleted.
    public var objectPermanentID: ObvManagedObjectPermanentID<PersistedDraft> {
        get throws {
            guard self.managedObjectContext != nil else { assertionFailure(); throw ObvUICoreDataError.noContext }
            return ObvManagedObjectPermanentID<PersistedDraft>(uuid: self.permanentUUID)
        }
    }
    
    public var fyleJoins: [FyleJoin] {
        unsortedDraftFyleJoins.sorted(by: { $0.index < $1.index })
    }

    public var fyleJoinsNotPreviews: [FyleJoin] {
        unsortedDraftFyleJoins
            .filter { $0.uti != UTType.olvidPreviewUti }
            .sorted(by: { $0.index < $1.index })
    }
    
    public var fyleJoinsPreviews: [FyleJoin] {
        unsortedDraftFyleJoins
            .filter { $0.uti == UTType.olvidPreviewUti }
            .sorted(by: { $0.index < $1.index })
    }

    public var fyleJoinsAudio: [FyleJoin] {
        unsortedDraftFyleJoins
            .filter { $0.contentType == UTType.audio }
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
            assertionFailure()
            throw ObvUICoreDataError.noContext
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
        
//        self.discussion.unarchive()
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

        resetExpiration()
        removeAllDraftFyleJoin()
        
    }

    
    private func resetExpiration() {
        self.readOnce = false
        self.existenceDuration = nil
        self.visibilityDuration = nil
        assert(!hasSomeExpiration)
    }
    
    
    public func replaceContentWith(newBody: AttributedString) {

        let messageBodyWithUserMentions = newBody.trimmingWhitespacesAndNewlines().messageBodyWithUserMentions
        
        if self.body != messageBodyWithUserMentions.body {
            self.body = messageBodyWithUserMentions.body
            if let resultingBody = self.body, !resultingBody.isEmpty {
                self.discussion.resetSortDateIfCurrentValueIsEarlierThan(Date.now)
            }
        }
        
        deleteAllAssociatedMentions()
        messageBodyWithUserMentions.mentions.forEach { mention in
            do {
                try PersistedUserMentionInDraft.createPersistedUserMentionInDraft(mention: mention, draft: self)
            } catch {
                assertionFailure()
            }
        }
        
    }

    
//    public func appendContentToBody(_ content: String) {
//        guard !content.isEmpty else { return }
//        if self.body == nil {
//            self.body = ""
//        }
//        self.body?.append(content)
//        // We don't need to reset the mentions since we are only appending characters to the existing body.
//        self.discussion.resetSortDateIfCurrentValueIsEarlierThan(Date())
////        self.discussion.unarchive()
//    }

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
            case body = "body"
            case permanentUUID = "permanentUUID"
            case discussion = "discussion"
            case replyTo = "replyTo"
        }
        static func persistedDraft(withObjectID objectID: TypeSafeManagedObjectID<PersistedDraft>) -> NSPredicate {
            NSPredicate(withObjectID: objectID.objectID)
        }
        static func forDiscussion(_ discussion: PersistedDiscussion) -> NSPredicate {
            NSPredicate(Key.discussion, equalTo: discussion)
        }
        static func forDiscussionObjectID(_ discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) -> NSPredicate {
            NSPredicate(Key.discussion, equalToObjectWithObjectID: discussionObjectID.objectID)
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

    
    public static func getPersistedDraft(of discussion: PersistedDiscussion, within context: NSManagedObjectContext) throws -> PersistedDraft? {
        let request: NSFetchRequest<PersistedDraft> = PersistedDraft.fetchRequest()
        request.predicate = Predicate.forDiscussion(discussion)
        request.fetchBatchSize = 1
        return try context.fetch(request).first
    }

    
    public static func getPersistedDraft(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, within context: NSManagedObjectContext) throws -> PersistedDraft? {
        let request: NSFetchRequest<PersistedDraft> = PersistedDraft.fetchRequest()
        request.predicate = Predicate.forDiscussionObjectID(discussionObjectID)
        request.fetchBatchSize = 1
        return try context.fetch(request).first
    }
    
    
    public static func getBodyOfPersistedDraft(objectID: TypeSafeManagedObjectID<PersistedDraft>, within context: NSManagedObjectContext) throws -> String? {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: PersistedDraft.entityName)
        request.resultType = .dictionaryResultType
        request.predicate = Predicate.persistedDraft(withObjectID: objectID)
        request.propertiesToFetch = [Predicate.Key.body.rawValue]
        request.includesPendingChanges = true
        request.fetchLimit = 1
        guard let results = try context.fetch(request) as? [[String: String?]] else { assertionFailure(); throw ObvUICoreDataError.couldNotCastFetchedResult }

        let valueToReturn = try results
            .compactMap { dict in
                guard let body = dict[Predicate.Key.body.rawValue] else { assertionFailure(); throw ObvUICoreDataError.couldNotCastFetchedResult }
                return body
            }
            .first
        
        return valueToReturn
    }
    
    
    public static func getPersistedDraft(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, within context: NSManagedObjectContext) throws -> PersistedDraft? {
        guard let discussionObjectID = try PersistedDiscussion.getPersistedDiscussionObjectID(discussionIdentifier: discussionIdentifier, within: context) else {
            return nil
        }
        return try getPersistedDraft(discussionObjectID: discussionObjectID, within: context)
    }

    
    public static func getObjectIDsOfAllDraftsReplyingTo(message: PersistedMessage) throws -> Set<TypeSafeManagedObjectID<PersistedDraft>> {
        let request: NSFetchRequest<PersistedDraft> = PersistedDraft.fetchRequest()
        guard let context = message.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        request.predicate = Predicate.whereReplyToIsMessage(message)
        request.propertiesToFetch = []
        request.fetchBatchSize = 1_000
        let drafts = try context.fetch(request)
        return Set(drafts.map({ $0.typedObjectID }))
    }
    
    public static func getFetchedResultsControllerForPersistedDraft(of discussion: PersistedDiscussion, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedDraft> {
        let request: NSFetchRequest<PersistedDraft> = PersistedDraft.fetchRequest()
        request.predicate = Predicate.forDiscussion(discussion)
        request.fetchBatchSize = 1
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.permanentUUID.rawValue, ascending: true)]
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: request,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        return fetchedResultsController
    }

    public static func getFetchedResultsControllerForPersistedDraft(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedDraft> {
        let request: NSFetchRequest<PersistedDraft> = PersistedDraft.fetchRequest()
        request.predicate = Predicate.forDiscussionObjectID(discussionObjectID)
        request.fetchBatchSize = 1
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.permanentUUID.rawValue, ascending: true)]
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: request,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        return fetchedResultsController
    }


    /// Since this method performs a fetch, we ensure it performs it on the appropriate thread. This is required as this method is often called from the main thread, but with a background context.
    public static func getFetchedResultsControllerForPersistedDraft(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, within context: NSManagedObjectContext) async throws -> NSFetchedResultsController<PersistedDraft> {
        try await context.perform {
            guard let discussionObjectID = try PersistedDiscussion.getPersistedDiscussionObjectID(discussionIdentifier: discussionIdentifier, within: context) else {
                throw ObvUICoreDataError.couldNotFindDiscussion
            }
            return getFetchedResultsControllerForPersistedDraft(discussionObjectID: discussionObjectID, within: context)
        }
    }

}

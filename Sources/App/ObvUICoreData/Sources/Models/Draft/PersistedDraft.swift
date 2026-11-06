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
import ObvSettings
import ObvTypes

@objc(PersistedDraft)
public final class PersistedDraft: NSManagedObject, ObvIdentifiableManagedObject {
        
    public static let entityName = "PersistedDraft"

    // MARK: Attributes

    @NSManaged private var body: String?
    @NSManaged private var permanentUUID: UUID
    @NSManaged private var rawExistenceDuration: NSNumber?
    /// The size this draft's photos and videos are sent at, as an ``ObvMediaFormat`` raw value. See ``selectedMediaFormat``.
    @NSManaged private var rawSelectedMediaFormat: String?
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

    /// The photographs of this draft, in the order they were attached. See ``videoJoins`` for the other half of what the size choice
    /// applies to; the two are kept apart because what is done with them is not the same — every size of a photograph is written at
    /// once, where only the chosen size of a video is ever exported.
    public var photoJoins: [PersistedDraftFyleJoin] {
        unsortedDraftFyleJoins
            .filter { $0.isPhotoEligibleForAFormatChoice }
            .sorted(by: { $0.index < $1.index })
    }

    /// The videos of this draft, in the order they were attached — the ones, and only the ones, the size choice also applies to.
    public var videoJoins: [PersistedDraftFyleJoin] {
        unsortedDraftFyleJoins
            .filter { $0.isVideoEligibleForAFormatChoice }
            .sorted(by: { $0.index < $1.index })
    }

    /// Whether the composition bar should offer a size to choose. Cheaper than ``photoJoins`` and ``videoJoins``, and asked on every
    /// rebuild of the bar's model.
    public var hasAtLeastOneMediaWithAFormatChoice: Bool {
        unsortedDraftFyleJoins.contains(where: { $0.isEligibleForAFormatChoice })
    }

    /// The size this draft's photos and videos are sent at.
    ///
    /// One choice per draft, applying to every attachment, including those added after it was made.
    ///
    /// A draft with no stored choice, or one this build does not know, answers with the app-wide default. That is safe only while the
    /// draft has no media: ``applySelectedMediaFormatToAllMedia()`` stores the size once files are placed, so that a choice made in another
    /// discussion cannot change what this draft shows without changing what it sends.
    public var selectedMediaFormat: ObvMediaFormat {
        guard let rawSelectedMediaFormat else { return ObvMessengerSettings.Discussions.defaultMediaFormat }
        return ObvMediaFormat(rawValue: rawSelectedMediaFormat) ?? ObvMessengerSettings.Discussions.defaultMediaFormat
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


// MARK: - Choosing the size this draft's photos and videos are sent at

extension PersistedDraft {

    /// Records that this draft's photos and videos are to be sent at `format`, and points everything that already has that size at its
    /// file.
    ///
    /// An attachment without a file for that size points at the nearest larger one, and moves when the file lands: the sizes makers
    /// re-apply the choice after each size they record. That is the usual case for a video, whose chosen size is exported only now.
    ///
    /// It does not write `ObvMessengerSettings.Discussions.defaultMediaFormat`: drafts with no choice read through it, so writing it
    /// inside a save that fails would change their size. The caller writes it after the save,
    /// in `PersistedDiscussionsUpdatesCoordinator.processUserWantsToChangeMediaFormatOfDraft(...)`.
    public func setSelectedMediaFormat(_ format: ObvMediaFormat) {
        if rawSelectedMediaFormat != format.rawValue {
            rawSelectedMediaFormat = format.rawValue
        }
        for join in photoJoins + videoJoins {
            join.setSelectedFormat(format)
        }
    }


    /// Points every photo and video of this draft at the file for the size currently chosen, **and records the size it used**.
    ///
    /// Called by the sizes makers after they record new sizes, a file that has just landed being possibly the one to send now.
    ///
    /// Storing the size matters: otherwise a draft with no stored choice would keep reading the app-wide default, and a size chosen in
    /// another discussion would change what its bar shows while its attachments stay on the old file. A draft with no media is left alone,
    /// so the default keeps seeding the next draft.
    public func applySelectedMediaFormatToAllMedia() {
        let mediaJoins = photoJoins + videoJoins
        guard !mediaJoins.isEmpty else { return }
        let format = selectedMediaFormat
        if rawSelectedMediaFormat != format.rawValue {
            rawSelectedMediaFormat = format.rawValue
        }
        for join in mediaJoins {
            join.setSelectedFormat(format)
        }
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

        // Forgetting the size chosen for the message just sent, rather than keeping it for the next one. The choice is not lost: it was
        // written to the app-wide default when it was made, and `selectedMediaFormat` falls back to that — so the next draft starts from
        // the same size, and does so through one mechanism instead of two that could disagree.
        self.rawSelectedMediaFormat = nil

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
            case rawSelectedMediaFormat = "rawSelectedMediaFormat"
            case discussion = "discussion"
            case replyTo = "replyTo"
            case unsortedDraftFyleJoins = "unsortedDraftFyleJoins"
        }
        static var withAtLeastOneAttachment: NSPredicate {
            NSPredicate(withStrictlyPositiveCountForKey: Key.unsortedDraftFyleJoins)
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

    
    /// Every draft holding a photograph or a video that has not been written at a size it may be sent at.
    ///
    /// Asked at launch, to catch up drafts from builds before sizes existed and drafts whose writing was interrupted. Nearly always empty.
    ///
    /// The fetch keeps drafts with an attachment and the rest is decided in Swift, by ``PersistedDraftFyleJoin/photoFormatsWithoutAFile``
    /// and ``PersistedDraftFyleJoin/videoFormatsWithoutAFile(whenSelectedFormatIs:)``, rather than restating that rule as a subquery.
    /// Drafts with attachments are few.
    ///
    /// Videos are included, at the cost of an export of tens of seconds each, once. Leaving them until the discussion is opened would leave
    /// a draft whose clip would be sent at a size other than the one the bar shows.
    public static func getObjectIDsOfDraftsWithAMediaMissingASize(within context: NSManagedObjectContext) throws -> [TypeSafeManagedObjectID<PersistedDraft>] {
        let request: NSFetchRequest<PersistedDraft> = PersistedDraft.fetchRequest()
        request.predicate = Predicate.withAtLeastOneAttachment
        request.sortDescriptors = []
        request.fetchBatchSize = 50
        return try context.fetch(request)
            .filter { draft in
                if draft.photoJoins.contains(where: { !$0.photoFormatsWithoutAFile.isEmpty }) { return true }
                let selectedFormat = draft.selectedMediaFormat
                return draft.videoJoins.contains(where: { !$0.videoFormatsWithoutAFile(whenSelectedFormatIs: selectedFormat).isEmpty })
            }
            .map(\.typedObjectID)
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
    
    /// **No sort descriptor.** A fetched results controller places a row *in memory* whenever one is merged in, by sending `compare:` to the
    /// sort-descriptor values — and `NSUUID` implements it no more than `NSData` does. There is one draft per discussion, so sorting on
    /// `permanentUUID` never had anything to compare against, but it is the same latent abort as the one fixed in
    /// `PersistedMessageSentRecipientInfos.getFetchedResultsControllerForInfos`.
    public static func getFetchedResultsControllerForPersistedDraft(of discussion: PersistedDiscussion, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedDraft> {
        let request: NSFetchRequest<PersistedDraft> = PersistedDraft.fetchRequest()
        request.predicate = Predicate.forDiscussion(discussion)
        request.fetchBatchSize = 1
        request.sortDescriptors = []
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: request,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        return fetchedResultsController
    }

    /// No sort descriptor, for the reason given on the controller above.
    public static func getFetchedResultsControllerForPersistedDraft(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedDraft> {
        let request: NSFetchRequest<PersistedDraft> = PersistedDraft.fetchRequest()
        request.predicate = Predicate.forDiscussionObjectID(discussionObjectID)
        request.fetchBatchSize = 1
        request.sortDescriptors = []
        
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

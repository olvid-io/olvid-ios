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

// MARK: - Convenience DB getters

extension PersistedMessage.Predicate {
    static func inboundMessageThatIsNotNewAnymore(within context: NSManagedObjectContext) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            isInboundMessage(within: context),
            PersistedMessageReceived.Predicate.isNotNewAnymore,
        ])
    }
    static func withSectionIdentifier(_ sectionIdentifier: String) -> NSPredicate {
        NSPredicate(Key.sectionIdentifier, EqualToString: sectionIdentifier)
    }
    /// A received message whose body may not be shown until the reader taps it.
    ///
    /// **Scoped to received messages on purpose, and not by naming their attributes.** `readOnce` and `rawVisibilityDuration` sit on the base entity, so a sent
    /// ephemeral message carries them too — and `rawStatus` counts something else entirely there. Read across both kinds, the rule would hide the reader's own
    /// messages, whose bodies they wrote and may always see. ``isInboundMessage(within:)`` restricts it to the one entity where the rule means what it says.
    static func inboundMessageWhoseReadingRequiresUserAction(within context: NSManagedObjectContext) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            isInboundMessage(within: context),
            PersistedMessageReceived.Predicate.readingRequiresUserAction,
        ])
    }
    static func outboundMessageThatWasSent(within context: NSManagedObjectContext) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            isOutboundMessage(within: context),
            PersistedMessageSent.Predicate.wasSent,
        ])
    }
}


extension PersistedMessage {

    static func getMessage(beforeSortIndex sortIndex: Double, inDiscussionWithObjectID objectID: TypeSafeManagedObjectID<PersistedDiscussion>, within context: NSManagedObjectContext) throws -> PersistedMessage? {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(objectID),
            Predicate.withSortIndexSmallerThan(sortIndex),
        ])
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: false)]
        return try context.fetch(request).first
    }

    
    public static func getAll(with objectIDs: [NSManagedObjectID], within context: NSManagedObjectContext) throws -> [PersistedMessage] {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = Predicate.objectsWithObjectId(in: objectIDs)
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }


    static func getNumberOfMessagesWithinDiscussion(discussionObjectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> Int {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = Predicate.withinDiscussionWithObjectID(discussionObjectID)
        return try context.count(for: request)
    }

    
    public static func getLastMessage(in discussion: PersistedDiscussion) throws -> PersistedMessage? {
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: false)]
        request.fetchLimit = 1
        request.predicate = Predicate.withinDiscussion(discussion)
        return try context.fetch(request).first
    }
    
}

// MARK: - What one look at the message above says

extension PersistedMessage {

    /// What a cell of a discussion learns by looking once at the message above it: whether it opens a day, and whether it opens a run of messages from one sender.
    ///
    /// The two are answered together because they are one question about one row — the message immediately above this one — and answering them separately would
    /// mean asking twice. A screen drawing a message needs both before it can draw anything: a date separator goes above a message that opens a day, and the
    /// sender's name and picture go above one that opens a run.
    public struct WhatTheMessageAboveSays: Sendable, Equatable, Hashable {

        /// The day this message opens, and nil when the message above already belongs to it.
        ///
        /// A `Date` at the start of the day, taken from ``PersistedMessage/sectionIdentifier`` rather than from the timestamp: that attribute is what the legacy
        /// screen sections by, and it is *adjusted* when it is written so that the days of a discussion never go backwards — a message whose timestamp disagrees
        /// with its neighbours is kept in their day. Formatting is the caller's, so that "Today" cannot be baked into a value that outlives the day.
        public let dayThisMessageOpens: Date?

        /// Whether the message above is a **received** message from the same contact as this one, in which case the sender has already been named and is not named
        /// again.
        ///
        /// False whenever this message is not a received one, whenever the message above is a sent or a system message, and whenever the message above belongs to
        /// another day — the legacy screen compares within one section only, so a new day names its sender again.
        public let followsAMessageFromTheSameContact: Bool

    }


    /// Which messages of a discussion a screen puts in its list.
    ///
    /// **One description, read by two fetches**, and that is the point of it existing: the list of a screen and the "what does the message above say" of
    /// ``getWhatTheMessageAboveSays(among:)`` must agree, or a message opening a day is compared against a row the reader cannot see and its separator is silently
    /// not drawn. Whoever changes what a screen shows changes one value.
    public struct MessagesShownByTheScreen: Sendable {

        /// Whether the system messages that report a change among the members of a group v2 are shown, which is the reader's own setting.
        let includeMembersOfGroupV2WereUpdated: Bool

        /// The system messages a screen would rather draw **itself**, and which must therefore not appear in its list.
        ///
        /// The SwiftUI screen has two. `numberOfNewMessages` is the marker saying how many messages arrived since the reader last looked, which that screen holds as
        /// two values for the life of the screen rather than as a row written into the database — see `SingleDiscussionView.InitialValues.newMessages`. And
        /// `discussionIsEndToEndEncrypted` is drawn as a **fixed first row**, which is what guarantees it can never end up below a message: were it merely a row like
        /// any other, an ordering accident could put it anywhere, and that ordering is an invariant rather than a hope.
        let categoriesOfSystemMessagesTheScreenDrawsItself: [PersistedMessageSystem.Category]

        public init(includeMembersOfGroupV2WereUpdated: Bool, categoriesOfSystemMessagesTheScreenDrawsItself: [PersistedMessageSystem.Category] = []) {
            self.includeMembersOfGroupV2WereUpdated = includeMembersOfGroupV2WereUpdated
            self.categoriesOfSystemMessagesTheScreenDrawsItself = categoriesOfSystemMessagesTheScreenDrawsItself
        }

        /// What has to be excluded from a fetch, and nil when a screen shows everything.
        func predicate(within context: NSManagedObjectContext) -> NSPredicate? {

            var subPredicates = [NSPredicate]()

            if !includeMembersOfGroupV2WereUpdated {
                subPredicates.append(NSCompoundPredicate(notPredicateWithSubpredicate: PersistedMessage.Predicate.isSystemMessageForMembersOfGroupV2WereUpdated(within: context)))
            }

            for category in categoriesOfSystemMessagesTheScreenDrawsItself {
                let isThatKindOfSystemMessage = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    PersistedMessage.Predicate.isSystemMessage(within: context),
                    PersistedMessageSystem.Predicate.withCategory(category),
                ])
                subPredicates.append(NSCompoundPredicate(notPredicateWithSubpredicate: isThatKindOfSystemMessage))
            }

            guard !subPredicates.isEmpty else { return nil }
            return NSCompoundPredicate(andPredicateWithSubpredicates: subPredicates)

        }

    }


    /// Looks once at the message above this one, and says what a cell needs to know of it. See ``WhatTheMessageAboveSays``.
    ///
    /// One indexed query for the day, and **no message materialized** by any of this: every fact needed is a stored attribute, so a dictionary result is enough.
    /// Meant to be called wherever the model of a message is built — on a background context, ahead of the cells that want it — and the answer kept with that model.
    ///
    /// A second query is run for a *received* message only, and only in order to compare senders: `senderIdentifier` is an attribute of
    /// ``PersistedMessageReceived`` and cannot be asked of ``PersistedMessage``, whose entity does not have it. It asks for the nearest message above from the same
    /// sender, and the sender is the same as the row above exactly when the two rows are the same one.
    public func getWhatTheMessageAboveSays(among messagesShownByTheScreen: MessagesShownByTheScreen) throws -> WhatTheMessageAboveSays {

        guard let context = self.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        // A message on its way out of the database, whose discussion has already gone. Nothing above it to look at.
        guard let discussion = self.discussion else { throw ObvUICoreDataError.couldNotFindDiscussion }

        let dayOfThisMessage = PersistedMessage.getDateComponents(fromSectionIdentifier: self.sectionIdentifier)?.date

        var subPredicates = [
            Predicate.withinDiscussion(discussion),
            Predicate.withSortIndexSmallerThan(self.sortIndex),
        ]
        if let predicateForWhatTheScreenShows = messagesShownByTheScreen.predicate(within: context) {
            subPredicates.append(predicateForWhatTheScreenShows)
        }

        let request: NSFetchRequest<NSDictionary> = PersistedMessage.dictionaryFetchRequest()
        request.resultType = .dictionaryResultType
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subPredicates)
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: false)]
        request.fetchLimit = 1
        request.propertiesToFetch = [Predicate.Key.sectionIdentifier.rawValue, Predicate.Key.sortIndex.rawValue]

        // Nothing above: this is the first message of the discussion, which therefore opens its day and names its sender.
        guard let messageAbove = try context.fetch(request).first else {
            return .init(dayThisMessageOpens: dayOfThisMessage, followsAMessageFromTheSameContact: false)
        }

        guard let sectionIdentifierOfTheMessageAbove = messageAbove[Predicate.Key.sectionIdentifier.rawValue] as? String,
              let sortIndexOfTheMessageAbove = messageAbove[Predicate.Key.sortIndex.rawValue] as? Double else {
            assertionFailure()
            return .init(dayThisMessageOpens: dayOfThisMessage, followsAMessageFromTheSameContact: false)
        }

        let opensADay = (sectionIdentifierOfTheMessageAbove != self.sectionIdentifier)

        let followsAMessageFromTheSameContact: Bool
        if opensADay {
            // A new day names its sender again, as the legacy screen does by comparing within one section only.
            followsAMessageFromTheSameContact = false
        } else {
            followsAMessageFromTheSameContact = try messageAboveIsTheNearestOneFromTheSameSender(sortIndexOfTheMessageAbove: sortIndexOfTheMessageAbove, in: discussion, within: context)
        }

        return .init(dayThisMessageOpens: opensADay ? dayOfThisMessage : nil,
                     followsAMessageFromTheSameContact: followsAMessageFromTheSameContact)

    }


    /// Whether the row above this message is the nearest received message from the same sender, which is what makes the two one run.
    ///
    /// The sender is compared through `senderIdentifier`, and not through the `contactIdentity` relationship the legacy screen compares: it is an attribute, so
    /// nothing has to be materialized, and it still names the sender of a message from a contact since deleted — where the relationship is nil for every one of
    /// them, making the messages of two deleted contacts read as one run.
    private func messageAboveIsTheNearestOneFromTheSameSender(sortIndexOfTheMessageAbove: Double, in discussion: PersistedDiscussion, within context: NSManagedObjectContext) throws -> Bool {

        guard let receivedMessage = self as? PersistedMessageReceived else { return false }

        let request: NSFetchRequest<NSDictionary> = PersistedMessageReceived.dictionaryFetchRequestForReceivedMessages()
        request.resultType = .dictionaryResultType
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            PersistedMessageReceived.Predicate.withinDiscussion(discussion),
            Predicate.withSortIndexSmallerThan(self.sortIndex),
            PersistedMessageReceived.Predicate.withSenderIdentifier(receivedMessage.senderIdentifier),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: false)]
        request.fetchLimit = 1
        request.propertiesToFetch = [Predicate.Key.sortIndex.rawValue]

        guard let nearestMessageFromTheSameSender = try context.fetch(request).first else { return false }
        guard let sortIndex = nearestMessageFromTheSameSender[Predicate.Key.sortIndex.rawValue] as? Double else { assertionFailure(); return false }

        return sortIndex == sortIndexOfTheMessageAbove

    }

}


// MARK: - Convenience NSFetchedResultsController creators

extension PersistedMessage {

    public static func getFetchRequestPredicateForAllMessagesWithinDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, showing messagesShownByTheScreen: MessagesShownByTheScreen, within context: NSManagedObjectContext) -> NSPredicate {

        guard let predicateForWhatTheScreenShows = messagesShownByTheScreen.predicate(within: context) else {
            return Predicate.withinDiscussion(discussionObjectID)
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussionObjectID),
            predicateForWhatTheScreenShows,
        ])

    }

    
    private static func getFetchRequestForAllMessagesWithinDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, showing messagesShownByTheScreen: MessagesShownByTheScreen, within context: NSManagedObjectContext) -> FetchRequestControllerModel<PersistedMessage> {
        
        let fetchRequest: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        
        fetchRequest.predicate = Self.getFetchRequestPredicateForAllMessagesWithinDiscussion(
            discussionObjectID: discussionObjectID,
            showing: messagesShownByTheScreen,
            within: context)
        
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: true)]
        fetchRequest.fetchBatchSize = 500
        // 2024-02-27 Commenting the following lines
//        fetchRequest.propertiesToFetch = [
//            Predicate.Key.body.rawValue,
//            Predicate.Key.rawStatus.rawValue,
//            Predicate.Key.rawVisibilityDuration.rawValue,
//            Predicate.Key.readOnce.rawValue,
//            Predicate.Key.sectionIdentifier.rawValue,
//            Predicate.Key.senderSequenceNumber.rawValue,
//            Predicate.Key.sortIndex.rawValue,
//            Predicate.Key.timestamp.rawValue,
//        ]
        //fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.shouldRefreshRefetchedObjects = true

        return .init(fetchRequest: fetchRequest, sectionNameKeyPath: Predicate.Key.sectionIdentifier.rawValue)
        
    }
    
    /// Method used when navigating to a single discussion, to populate all the cells of a single discussion collection view.
    public static func getFetchedResultsControllerForAllMessagesWithinDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, showing messagesShownByTheScreen: MessagesShownByTheScreen, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedMessage> {
        let fetchRequestModel = Self.getFetchRequestForAllMessagesWithinDiscussion(
            discussionObjectID: discussionObjectID,
            showing: messagesShownByTheScreen,
            within: context)
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequestModel.fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: fetchRequestModel.sectionNameKeyPath,
                                                                  cacheName: nil)
        return fetchedResultsController
    }
    
    
    /// Returns the object IDs of all the messages of the given discussion, each with its ``sectionIdentifier``, in the exact same order as the objects fetched by
    /// the controller returned by ``getFetchedResultsControllerForAllMessagesWithinDiscussion(discussionObjectID:includeMembersOfGroupV2WereUpdated:within:)``.
    ///
    /// This performs an object-ID-only fetch: no message is materialized, which makes it suitable for building the initial model of a discussion
    /// that potentially contains a very large number of messages.
    public static func getObjectIDsOfAllMessagesWithinDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, showing messagesShownByTheScreen: MessagesShownByTheScreen, within context: NSManagedObjectContext) throws -> [(objectID: NSManagedObjectID, sectionIdentifier: String)] {
        let fetchRequestModel = Self.getFetchRequestForAllMessagesWithinDiscussion(
            discussionObjectID: discussionObjectID,
            showing: messagesShownByTheScreen,
            within: context)
        // **Dictionaries rather than `managedObjectIDResultType`, whose *order* cannot be relied on.**
        //
        // Measured on 2026-08-19, on a discussion of 948 messages, by asking this same request both ways in the same breath and comparing them at every
        // position. After deleting a few messages, leaving the discussion and coming back: the two fetches returned **the same rows** (`sameRows=true`, same
        // count), the dictionary fetch was monotonic in `sortIndex` with **no inversion anywhere**, and the two orderings **differed from position 0** — not one
        // row out of place, an entirely different order. A control entry moments earlier, on the same discussion before the deletion, agreed at every position.
        //
        // What that cost, before it was understood: the screen believed the array ordered, so the marker above the first unread message was placed at index 136
        // of 948 rather than near the end, and entering a discussion dropped the reader three weeks into the past. Force-quitting the app made it correct again,
        // which is what first showed the store was innocent.
        //
        // Object-ID fetches are an optimisation path that can be answered from the row cache, and the order stops being trustworthy once a context has had
        // deletions merged into it. **A dictionary fetch keeps what this is for**: it reads columns and materialises no message, so the size of a discussion
        // still costs nothing here. `sortIndex` is asked for beside the ID deliberately — that is the request measured ordered, and a column sorted on but never
        // selected is exactly the sort of thing an optimiser may treat differently.
        let theObjectID = NSExpressionDescription()
        theObjectID.name = Self.nameOfTheObjectIDInTheFetchedDictionaries
        theObjectID.expression = NSExpression.expressionForEvaluatedObject()
        theObjectID.expressionResultType = .objectIDAttributeType

        let request = NSFetchRequest<NSDictionary>(entityName: Self.globalEntityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = [theObjectID, Predicate.Key.sortIndex.rawValue, Predicate.Key.sectionIdentifier.rawValue]
        request.predicate = fetchRequestModel.fetchRequest.predicate
        request.sortDescriptors = fetchRequestModel.fetchRequest.sortDescriptors

        let rows = try context.fetch(request)
        let objectIDsAndSectionIdentifiers = rows.compactMap { row -> (objectID: NSManagedObjectID, sectionIdentifier: String)? in
            guard let objectID = row[Self.nameOfTheObjectIDInTheFetchedDictionaries] as? NSManagedObjectID,
                  let sectionIdentifier = row[Predicate.Key.sectionIdentifier.rawValue] as? String else { return nil }
            return (objectID, sectionIdentifier)
        }
        guard objectIDsAndSectionIdentifiers.count == rows.count else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotCastFetchedResult
        }
        return objectIDsAndSectionIdentifiers
    }


    /// The key the object ID comes back under in ``getObjectIDsOfAllMessagesWithinDiscussion(discussionObjectID:showing:within:)``, which has to name it itself
    /// because a dictionary fetch has no other way of asking for one.
    private static let nameOfTheObjectIDInTheFetchedDictionaries = "theObjectID"


    /// Returns the messages with the given object IDs, fetched in one go.
    ///
    /// Suitable for materializing a bounded batch of messages at once, e.g. those a screen is about to display, instead of faulting them one by one.
    /// The order of the returned messages is *not* that of `objectIDs`.
    public static func getMessages(objectIDs: [NSManagedObjectID], within context: NSManagedObjectContext) throws -> [PersistedMessage] {
        guard !objectIDs.isEmpty else { return [] }
        let request = NSFetchRequest<PersistedMessage>(entityName: Self.globalEntityName)
        request.predicate = NSPredicate(format: "self IN %@", objectIDs)
        request.fetchLimit = objectIDs.count
        return try context.fetch(request)
    }


    public static func searchForAllMessagesWithinDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, searchTerm: String, within context: NSManagedObjectContext) throws -> [TypeSafeManagedObjectID<PersistedMessage>] {
        
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: Self.globalEntityName)
        request.resultType = .managedObjectIDResultType
        
        var subPredicates = [Predicate.withinDiscussion(discussionObjectID)]
        do {
            let searchTerms = searchTerm.trimmingWhitespacesAndNewlines().split(separator: " ").map({ String($0) })
            let searchTermsPredicates = searchTerms.map({ Predicate.whereBodyContains(searchTerm: $0) })
            let searchTermsPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: searchTermsPredicates)
            subPredicates.append(searchTermsPredicate)
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subPredicates)
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: true)]
        
        let objectIDs = try context.fetch(request) as? [NSManagedObjectID] ?? []
        
        let returnedValues = objectIDs.map { TypeSafeManagedObjectID<PersistedMessage>(objectID: $0) }

        return returnedValues

    }


    /// Searches a discussion for the messages the reader may be shown, given the words they are looking for. Returns their object IDs, oldest first.
    ///
    /// **Beside ``searchForAllMessagesWithinDiscussion(discussionObjectID:searchTerm:within:)`` rather than replacing it**, that one still being what the UIKit
    /// screen uses. This is the SwiftUI screen's, and it differs in three deliberate ways.
    ///
    /// **It is given the words, not the term.** The older one takes a string and splits it itself, and the highlight then looks for the whole string as one range —
    /// so a search for two words finds the message that holds both and shows no highlight at all. Whoever searches now decides what the words are, once, and hands
    /// the same words to this fetch and to the view that highlights them. The two cannot disagree.
    ///
    /// **A location is never a result.** Its body is the text written for clients too old to understand a location — a maps URL — so it matches words the reader
    /// cannot see anywhere on the screen, and a map has nothing to highlight. A **poll** is deliberately still a result: its question is on the screen, and the
    /// question is what gets highlighted.
    ///
    /// **A message the reader has not been allowed to read is never a result.** An unread read-once message, or one whose visibility is limited, holds its body in
    /// the database and would otherwise match, be scrolled to, and have its words highlighted — revealing exactly what the tap-to-read guard exists to withhold.
    /// A **wiped** message needs no such care: wiping nils the body, so it can match nothing.
    public static func searchForMessagesTheReaderMayRead(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, words: [String], within context: NSManagedObjectContext) throws -> [TypeSafeManagedObjectID<PersistedMessage>] {

        // No words is not an empty search, it is *no* search. Fetching every message of the discussion would be the opposite of what the caller means.
        guard !words.isEmpty else { return [] }

        let request = NSFetchRequest<NSFetchRequestResult>(entityName: Self.globalEntityName)
        request.resultType = .managedObjectIDResultType

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussionObjectID),
            // Every word, each matched anywhere in the body: "meeting friday" finds a message about Friday and the meeting. This is the older method's rule, kept.
            NSCompoundPredicate(andPredicateWithSubpredicates: words.map({ Predicate.whereBodyContains(searchTerm: $0) })),
            Predicate.isNotLocationMessage,
            NSCompoundPredicate(notPredicateWithSubpredicate: Predicate.inboundMessageWhoseReadingRequiresUserAction(within: context)),
        ])

        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: true)]

        let objectIDs = try context.fetch(request) as? [NSManagedObjectID] ?? []

        return objectIDs.map { TypeSafeManagedObjectID<PersistedMessage>(objectID: $0) }

    }

    /// This method deletes the first outbound/inbound messages of the discussion, up to the `count` parameter.
    /// Outbound messages only concerns sent messages. Inbound messages only concerns non-new messages.
    public static func deleteFirstMessages(discussion: PersistedDiscussion, count: Int) throws {
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        guard count > 0 else { return }
        let fetchRequest: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortIndex.rawValue, ascending: true)]
        fetchRequest.fetchLimit = count
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                Predicate.outboundMessageThatWasSent(within: context),
                Predicate.inboundMessageThatIsNotNewAnymore(within: context),
            ]),
        ])
        let messages = try context.fetch(fetchRequest)
        messages.forEach { context.delete($0) }
    }

    /// The messages with these object IDs, for a controller whose set changes while it lives — see ``fetchesTheMessages(withObjectIDs:with:)``.
    ///
    /// Each row is found by its primary key, whatever the size of the discussion. No order, the caller finding each message by its object ID.
    public static func getFetchedResultsControllerForMessages(withObjectIDs objectIDs: Set<NSManagedObjectID>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedMessage> {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = Predicate.withObjectIDIn(objectIDs)
        request.sortDescriptors = []
        return .init(fetchRequest: request,
                     managedObjectContext: context,
                     sectionNameKeyPath: nil,
                     cacheName: nil)
    }


    /// Has a controller made by ``getFetchedResultsControllerForMessages(withObjectIDs:within:)`` fetch another set of messages. Called on the queue of its context.
    ///
    /// The controller reports nothing about what the new fetch adds or removes, only the changes that come after it, so the caller compares the sets itself.
    public static func fetchesTheMessages(withObjectIDs objectIDs: Set<NSManagedObjectID>, with controller: NSFetchedResultsController<PersistedMessage>) throws {
        controller.fetchRequest.predicate = Predicate.withObjectIDIn(objectIDs)
        try controller.performFetch()
    }


    public static func getFetchedResultsController(objectID: TypeSafeManagedObjectID<PersistedMessage>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedMessage> {
        let request: NSFetchRequest<PersistedMessage> = PersistedMessage.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID.objectID)
        request.fetchLimit = 1
        request.sortDescriptors = []
        return .init(fetchRequest: request,
                     managedObjectContext: context,
                     sectionNameKeyPath: nil,
                     cacheName: nil)
    }
}


// MARK: - Determining actions availability

extension PersistedMessage {
    
    public var copyTextActionCanBeMadeAvailable: Bool {
        if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.copyTextActionCanBeMadeAvailableForReceivedMessage
        } else if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.copyTextActionCanBeMadeAvailableForSentMessage
        } else {
            return false
        }
    }

    public var shareActionCanBeMadeAvailable: Bool {
        if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.shareActionCanBeMadeAvailableForReceivedMessage
        } else if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.shareActionCanBeMadeAvailableForSentMessage
        } else {
            return false
        }
    }
    
    /// **Why this message may not be forwarded, or nil when it may**.
    ///
    /// **The reason is the primitive and the boolean below is derived from it**, so the two cannot say different things. It exists because a selection of messages
    /// may hold one that cannot be forwarded, and the reader is then told *which rule stopped them* rather than being left with a control that declines without a
    /// word — the decision Step 42c took for the trash, applied to the action beside it.
    ///
    /// **This unties forwarding from sharing, which were the same rule by accident of implementation.** `forwardActionCanBeMadeAvailableFor*Message` used to be a
    /// one-line alias of `shareActionCanBeMadeAvailableFor*Message`; the clauses are transcribed here rather than shared, and `shareActionCanBeMadeAvailable*`
    /// keeps its own body untouched. That is deliberate: the two answer different questions and happened to agree. Do not "fix" the duplication back.
    public var whyThisMessageCannotBeForwarded: WhyAMessageCannotBeForwarded? {
        if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.whyThisReceivedMessageCannotBeForwarded
        } else if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.whyThisSentMessageCannotBeForwarded
        } else {
            // A system message is the discussion talking about itself — a contact joined, a call was missed — and there is nothing to carry elsewhere. It is
            // nonetheless a row a reader may tick, which is why this has to be a reason rather than a silence.
            return .itIsASystemMessage
        }
    }

    public var forwardActionCanBeMadeAvailable: Bool {
        whyThisMessageCannotBeForwarded == nil
    }
    
    public var infoActionCanBeMadeAvailable: Bool {
        if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.infoActionCanBeMadeAvailableForReceivedMessage
        } else if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.infoActionCanBeMadeAvailableForSentMessage
        } else if let systemMessage = self as? PersistedMessageSystem {
            return systemMessage.infoActionCanBeMadeAvailableForSystemMessage
        } else {
            return false
        }
    }
    
    
    public var replyToActionCanBeMadeAvailable: Bool {
        assert(Thread.isMainThread)

        // Only a message somebody wrote can be answered. A system message is the discussion talking about itself — a contact joined, a call was missed, the shared
        // settings changed — and there is nobody to reply to.
        //
        // 2026-08-09: this used to be missing, and the omission was invisible because the only caller that could have shown it hid it by other means: the legacy
        // screen reads `cell.persistedDraftObjectID` alongside this, and `SystemMessageCell` returns nil for it. That nil is a *policy* wearing the clothes of
        // plumbing, and a second screen reading this rule on its own offered Reply on every system message. The rule belongs here.
        switch self.kind {
        case .none, .system:
            return false
        case .sent, .received:
            break
        }

        guard !self.isWiped, !self.isLocationMessage else { return false }

        // **And not one the reader has not been allowed to read yet**, 2026-08-26, and the twin of the guard added to
        // `ownedIdentityIsAllowedToSetReaction` the same day. A tap-to-read message that has not been tapped offered *Reply*, which would quote a message
        // the reader has not seen — and, since the quote carries the body, put it in front of them by another route.
        //
        // Shared by both discussion screens, so the legacy one is fixed by this line too.
        if let received = self as? PersistedMessageReceived, received.readingRequiresUserAction { return false }

        // 2024-09-11: We used to perform a deep check by actually trying to create a reply in a child view context.
        // This method was not efficient enough, as this check can be made multiple times on the main thread, and
        // creating a message is expensive. So we now rely on an adhoc method, that should be sufficient.

        guard let discussion else { assertionFailure(); return false }
        do {
            try PersistedMessageSent.isCreationAllowed(inDiscussion: discussion)
        } catch {
            return false
        }

        return true

    }

    /// Returns `true` iff the edit body action can be made available for this message. This is expected to be called on the main thread to allow the UI to determine if the edit action can be shown to the user.
    ///
    /// We implement this by simulating what would happen if the edit action was performed. We return `true` iff the call succeeds. This is performed on a child view context to prevent any unwanted side-effect.
    public var editBodyActionCanBeMadeAvailable: Bool {
        guard !self.isLocationMessage else { return false }
        if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.editBodyActionCanBeMadeAvailableForSentMessage
        } else {
            return false
        }
    }
    
    public var callActionCanBeMadeAvailable: Bool {
        if let systemMessage = self as? PersistedMessageSystem {
            return systemMessage.callActionCanBeMadeAvailableForSystemMessage
        } else {
            return false
        }
    }
    

    public var deleteOwnReactionActionCanBeMadeAvailable: Bool {
        if let receivedMessage = self as? PersistedMessageReceived {
            return receivedMessage.deleteOwnReactionActionCanBeMadeAvailableForReceivedMessage
        } else if let sentMessage = self as? PersistedMessageSent {
            return sentMessage.deleteOwnReactionActionCanBeMadeAvailableForSentMessage
        } else {
            return false
        }
    }
    
    
    /// The deletion types that can be made available for **all** of these messages at once, which is what a screen offering one button for a whole selection needs
    /// to know.
    ///
    /// **Three child contexts, and not three per message.** The obvious way to answer this is to intersect
    /// ``deletionTypesThatCanBeMadeAvailableForThisMessage`` over the set — and that property makes a child context for *each* deletion type it tries, so a
    /// selection of two hundred messages asked one at a time is six hundred child contexts and six hundred simulated deletions, on the main thread. Simulating the
    /// whole set at once, once per type, is three. The plural
    /// `processMessageDeletionRequestRequestedFromCurrentDeviceOfThisOwnedIdentity(persistedMessageObjectIDs:deletionType:)` throws on the first message that
    /// refuses, which is exactly the *all of them, or none* that a single button promises.
    ///
    /// Empty is a legitimate answer and means nothing here can be deleted — a location still being shared, above all.
    ///
    /// As with the singular property, this asserts the main thread and wants the **view** context: the child contexts it makes are children of that one, and the
    /// simulation is never saved.
    ///
    /// Added for the SwiftUI discussion screen, where several messages may be selected at once.
    public static func deletionTypesThatCanBeMadeAvailable(forAllOf objectIDs: Set<NSManagedObjectID>, within context: NSManagedObjectContext) -> Set<DeletionType> {
        assert(Thread.isMainThread)

        guard !objectIDs.isEmpty else { return Set() }

        guard context.concurrencyType == .mainQueueConcurrencyType else {
            assertionFailure()
            return Set()
        }

        // **A location still being shared refuses every kind, and the simulation does not discover that.** The singular property answers `Set()` for one in a
        // *pre-check*, before it simulates anything — so leaving this out would offer to delete a selection holding one, and the deletion would then be asked to
        // do what the single-message path says it may not. Read here rather than in a child context: nothing is being simulated yet.
        for objectID in objectIDs {
            guard let message = try? PersistedMessage.get(with: objectID, within: context) else { continue }
            if let receivedMessage = message as? PersistedMessageReceived, receivedMessage.locationContinuousReceived != nil {
                return Set()
            } else if let sentMessage = message as? PersistedMessageSent, sentMessage.locationContinuousSent != nil {
                return Set()
            }
        }

        var acceptableDeletionTypes = Set<DeletionType>()

        for deletionType in DeletionType.allCases {

            let childViewContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            childViewContext.parent = context

            // The owned identity is read in the child context, as the messages are: the simulation must happen entirely there, or it would touch the view context.
            guard let anyMessage = try? PersistedMessage.get(with: objectIDs.first!, within: childViewContext),
                  let ownedIdentityInChildViewContext = anyMessage.discussion?.ownedIdentity else {
                assertionFailure()
                return Set()
            }

            do {
                _ = try ownedIdentityInChildViewContext.processMessageDeletionRequestRequestedFromCurrentDeviceOfThisOwnedIdentity(
                    persistedMessageObjectIDs: objectIDs,
                    deletionType: deletionType)
                acceptableDeletionTypes.insert(deletionType)
            } catch {
                continue
            }

        }

        return acceptableDeletionTypes
    }


    /// Why **one** of these messages cannot be forwarded, or nil when every one of them may be.
    ///
    /// **One reason is enough, because the caller sends all of them or none** — which is what a screen offering a single Forward over a whole selection promises:
    /// a forward creates one message per source message per destination, and forwarding the eligible subset silently would leave the reader believing they had
    /// sent something they had not. That policy is the caller's; what this answers is the narrower fact the policy is built on.
    ///
    /// **Cheap, unlike its deletion counterpart above.** ``PersistedMessage/whyThisMessageCannotBeForwarded`` is plain property reads — no child context, no
    /// simulation — so this is a loop over the selection and costs nothing worth measuring. It is asked when Forward is tapped rather than as the selection
    /// changes all the same, for consistency with the deletion and because it wants the view context, on the queue that owns it.
    ///
    /// **The reason reported is the first in ``WhyAMessageCannotBeForwarded``'s own case order, not the first offending message.** A selection is a set and has no
    /// order the reader would recognise, so reporting the first message found would give a different sentence for the same selection depending on how the ticks
    /// happened to hash. Asking the enum instead makes the answer a property of what was chosen.
    ///
    /// A message that cannot be found is ignored rather than refused: a selection can be pruned by a deletion arriving from another device while a sheet stands
    /// open, and the messages that remain are still forwardable. An **empty** set answers nil — there is nothing that cannot be forwarded — and the caller is
    /// expected to have refused an empty selection before asking.
    ///
    public static func whyOneOfTheseMessagesCannotBeForwarded(objectIDs: Set<NSManagedObjectID>, within context: NSManagedObjectContext) -> WhyAMessageCannotBeForwarded? {
        assert(Thread.isMainThread)

        // **Fails closed, unlike an earlier version of this and like its deletion sibling above.** A rule that cannot do its work must refuse: returning nil here
        // means *nothing refuses them*, which a caller reads as *send all of it* — and the direction of that failure is content leaving the discussion, an
        // ephemeral message forwarded out of it because a check never ran. See ``WhyAMessageCannotBeForwarded/theQuestionCouldNotBeAsked``.
        guard context.concurrencyType == .mainQueueConcurrencyType else {
            assertionFailure()
            return .theQuestionCouldNotBeAsked
        }

        var reasonsFound = Set<WhyAMessageCannotBeForwarded>()

        for objectID in objectIDs {
            guard let message = try? PersistedMessage.get(with: objectID, within: context) else { continue }
            if let reason = message.whyThisMessageCannotBeForwarded {
                reasonsFound.insert(reason)
            }
        }

        return WhyAMessageCannotBeForwarded.allCases.first(where: reasonsFound.contains)

    }


    /// This is expected to be called from the UI in order to determine which deletion types can be shown.
    ///
    /// This is implemented by creating a child context in which we simulate the deletion of the message.
    /// Of course, the child context is not saved to prevent any side-effect (view contexts are never saved anyway).
    public var deletionTypesThatCanBeMadeAvailableForThisMessage: Set<DeletionType> {
        assert(Thread.isMainThread)
        
        if let receivedMessage = self as? PersistedMessageReceived, receivedMessage.locationContinuousReceived != nil {
            return Set()
        } else if let sentMessage = self as? PersistedMessageSent, sentMessage.locationContinuousSent != nil {
            return Set()
        }
        
        guard let context = self.managedObjectContext else {
            assertionFailure()
            return Set()
        }
        guard context.concurrencyType == .mainQueueConcurrencyType else {
            assertionFailure()
            return Set()
        }
        
        var acceptableDeletionTypes = Set<DeletionType>()
        
        for deletionType in DeletionType.allCases {
            
            let childViewContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            childViewContext.parent = context
            guard let messageInChildViewContext = try? PersistedMessage.get(with: self.typedObjectID, within: childViewContext) else {
                assertionFailure()
                return Set()
            }
            guard let discussionInChildViewContext = messageInChildViewContext.discussion else {
                assertionFailure()
                return Set()
            }
            guard let ownedIdentityInChildViewContext = discussionInChildViewContext.ownedIdentity else {
                assertionFailure()
                return Set()
            }

            do {
                _ = try ownedIdentityInChildViewContext.processMessageDeletionRequestRequestedFromCurrentDeviceOfThisOwnedIdentity(persistedMessageObjectID: messageInChildViewContext.objectID, deletionType: deletionType)
                acceptableDeletionTypes.insert(deletionType)
            } catch {
                continue
            }
            
        }
        
        return acceptableDeletionTypes
    }

}

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

import Intents
import OSLog
import CoreData
import OlvidUtils
import ObvAppTypes
import ObvTypes
import ObvUICoreData
import ObvUserNotificationsContent
import ObvUserNotificationsDatabase
import ObvAppCoreConstants
import ObvSiriReadIntents

/// Handles `INSearchForMessagesIntent` within the Intents extension.
///
/// **Intent lifecycle**
/// 1. ``resolveRecipients(for:)`` / ``resolveSenders(for:)`` — each `INPerson` in the list is resolved
///    independently via ``resolvePersons(persons:)``, which also propagates a shared owned-identity
///    constraint extracted from any `isMe` person.
/// 2. ``resolveSpeakableGroupNames(for:)`` — resolves each group name to an `INSpeakableString` whose
///    `vocabularyIdentifier` encodes the `ObvDiscussionIdentifier`; returns `.notRequired()` when absent.
/// 3. ``confirm(intent:)`` — validates the resolved intent and returns `.ready`.
/// 4. ``handle(intent:)`` — executes the search across `PersistedMessageReceived` and/or
///    `PersistedMessageSent` based on intent shape, returning up to 100 results ordered by date.
final class SearchForMessagesIntentHandler: NSObject {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "SearchForMessagesIntentHandler")

    /// Whether the user-notifications Core Data stack was successfully initialized in the Intents
    /// extension. When `false`, ``handle(intent:)`` skips the NSE-database fetch and serves results
    /// from the app database only.
    private let nseStackAvailable: Bool

    /// Lets the handler force-consume pending App-database history before querying, so it never reads
    /// a stale row cache (e.g. messages the main app already marked as read). `nil` only when the
    /// `ObvStack` failed to initialize, in which case there is nothing to merge.
    private let appHistoryMerger: ObvPersistentHistoryMerger?

    /// Same, for the user-notifications database, so the extension doesn't re-surface pending messages
    /// the NSE or app has changed. `nil` when the user-notifications stack is unavailable.
    private let nseHistoryMerger: ObvPersistentHistoryMerger?

    init(nseStackAvailable: Bool, appHistoryMerger: ObvPersistentHistoryMerger?, nseHistoryMerger: ObvPersistentHistoryMerger?) {
        self.nseStackAvailable = nseStackAvailable
        self.appHistoryMerger = appHistoryMerger
        self.nseHistoryMerger = nseHistoryMerger
        super.init()
    }

}


// MARK: - Implementing INSearchForMessagesIntentHandling

extension SearchForMessagesIntentHandler: INSearchForMessagesIntentHandling {
    
    /// Resolves the `recipients` field of an `INSearchForMessagesIntent`.
    ///
    /// In SiriKit, `recipients` are the people who received a message from the user (outgoing traffic).
    /// Each person is resolved independently via ``resolvePerson(person:)``.
    /// Other intent attributes (`searchTerms`, `attributes`, `dateTimeRange`, etc.) are not the
    /// concern of this method and are handled in ``handle(intent:)``.
    func resolveRecipients(for intent: INSearchForMessagesIntent) async -> [INPersonResolutionResult] {
        
        guard let recipients = intent.recipients, !recipients.isEmpty else { return [] }
        
        Self.logger.info("📨🏁 Resolving \(recipients.count) recipient(s) for INSearchForMessagesIntent")
        do {
            return try await resolvePersons(persons: recipients)
        } catch {
            Self.logger.fault("📨 resolveRecipients failed: \(error)")
            return [.unsupported()]
        }
        
    }


    /// Resolves the `senders` field of an `INSearchForMessagesIntent`.
    ///
    /// In SiriKit, `senders` are the people who sent messages to the user (incoming traffic).
    /// Each person is resolved independently via ``resolvePerson(person:)``.
    /// Other intent attributes are not the concern of this method and are handled in ``handle(intent:)``.
    func resolveSenders(for intent: INSearchForMessagesIntent) async -> [INPersonResolutionResult] {
        
        guard let senders = intent.senders, !senders.isEmpty else { return [] }

        Self.logger.info("📨🏁 Resolving \(senders.count) sender(s) for INSearchForMessagesIntent")
        do {
            return try await resolvePersons(persons: senders)
        } catch {
            Self.logger.fault("📨 resolveSenders failed: \(error)")
            return [.unsupported()]
        }
    }

    
    /// Resolves the `speakableGroupNames` field of an `INSearchForMessagesIntent`.
    ///
    /// Returns `[.notRequired()]` when `intent.speakableGroupNames` is nil or empty. Otherwise
    /// resolves each group name independently via `PersistedDiscussion.resolveGroupName(_:)`.
    func resolveSpeakableGroupNames(for intent: INSearchForMessagesIntent) async -> [INSpeakableStringResolutionResult] {
        guard let groupNames = intent.speakableGroupNames, !groupNames.isEmpty else {
            Self.logger.info("📨🏁 resolveSpeakableGroupNames, returning notRequired")
            return [.notRequired()]
        }
        Self.logger.info("📨🏁 Resolving \(groupNames.count) speakable group name(s)")
        var results: [INSpeakableStringResolutionResult] = []
        for groupName in groupNames {
            results.append(await PersistedDiscussion.resolveGroupName(groupName))
        }
        return results
    }


    func confirm(intent: INSearchForMessagesIntent) async -> INSearchForMessagesIntentResponse {
        Self.logger.info("📨🏁 Confirming INSearchForMessagesIntent, returning .ready")
        return INSearchForMessagesIntentResponse(code: .ready, userActivity: nil)
    }


    /// Executes the search and returns matching messages.
    ///
    /// Picks the storage to query from intent shape:
    /// - `senders`/`recipients` decide direction via ``searchDirection(senders:recipients:restrictToNewMessages:)``,
    ///   which can select `PersistedMessageReceived`, `PersistedMessageSent`, or both.
    /// - `conversationIdentifiers`, `speakableGroupNames`, `senders`, `recipients` (with their operators)
    ///   are resolved by ``getDiscussionIdentifiers(conversationIdentifiers:speakableGroupNames:senders:sendersOperator:recipients:recipientsOperator:)``
    ///   into a discussion scope (`nil` = all discussions, empty set = no match short-circuits to `.success` with no messages).
    /// - `attributes` is reduced to `restrictToNewMessages` (true iff `.unread` is set and `.read` is not);
    ///   this also forces the direction to Received only.
    /// - `searchTerms` is passed through verbatim — every non-empty term must appear (case- and
    ///   diacritic-insensitive substring) in the message body.
    /// - `dateTimeRange.startDateComponents` / `endDateComponents` are resolved to absolute `Date`
    ///   values via the current calendar; nil components produce an open-ended range on that side.
    ///
    /// When both sides are queried, the 100 most recent results (by `dateSent`) are kept and then
    /// returned in ascending date order via ``mergeByDate(_:_:cap:)`` so Siri reads them oldest-first.
    func handle(intent: INSearchForMessagesIntent) async -> INSearchForMessagesIntentResponse {

        Self.logger.info("📨🏁 Handling INSearchForMessagesIntent")

        // Force-consume any App-database writes made by other processes before querying. This closes
        // the race where the main app marked messages as read but the corresponding
        // `NSPersistentStoreRemoteChange` notification hasn't been processed yet: without it, the
        // fetch below would read a stale row cache and re-surface already-read messages.
        await appHistoryMerger?.mergePendingTransactionsAndWait()

        let response: INSearchForMessagesIntentResponse

        do {

            let restrictToNewMessages: Bool = intent.attributes.contains(.unread) && !intent.attributes.contains(.read)
            Self.logger.info("📨 restrictToNewMessages=\(restrictToNewMessages)")

            // Honor explicit message scoping. When Siri targets specific messages — by app
            // message identifier (`identifiers`) or, in practice, by the notification it is currently
            // reading aloud (`notificationIdentifiers`) — return exactly those messages and stop. This is
            // the fix for the backlog-read bug: a `notificationIdentifiers`-only call (no other
            // constraint, `restrictToNewMessages == false`) used to fall through to the all-discussions
            // fetch below, so Siri read up to 100 messages. Each identifier maps to a single message, so
            // we union the two fields and ignore their `…Operator` (an intersection across distinct
            // identifiers would be empty and meaningless).
            let explicitMessageIdentifiers = intent.identifiers ?? []
            let explicitNotificationIdentifiers = intent.notificationIdentifiers ?? []
            if !explicitMessageIdentifiers.isEmpty || !explicitNotificationIdentifiers.isEmpty {
                let inMessages = try await fetchINMessagesScopedToExplicitIdentifiers(
                    messageIdentifierStrings: explicitMessageIdentifiers,
                    notificationRequestIdentifiers: explicitNotificationIdentifiers)
                Self.logger.info("📨 Scoped to explicit identifiers, response messages count=\(inMessages.count)")
                response = INSearchForMessagesIntentResponse(code: .success, userActivity: nil)
                response.messages = inMessages
                return response
            }

            let direction = Self.searchDirection(senders: intent.senders, recipients: intent.recipients, restrictToNewMessages: restrictToNewMessages)
            Self.logger.info("📨 direction searchReceived=\(direction.searchReceived) searchSent=\(direction.searchSent)")

            let searchTerms = intent.searchTerms
            let (startDate, endDate) = Self.dateRange(from: intent.dateTimeRange)
            Self.logger.info("📨 searchTerms=\(searchTerms?.count ?? 0) startDate=\(startDate?.description ?? "nil") endDate=\(endDate?.description ?? "nil")")

            let discussionIdentifiers = try await getDiscussionIdentifiers(
                conversationIdentifiers: intent.conversationIdentifiers,
                speakableGroupNames: intent.speakableGroupNames,
                senders: intent.senders,
                sendersOperator: intent.sendersOperator,
                recipients: intent.recipients,
                recipientsOperator: intent.recipientsOperator
            )

            if let ids = discussionIdentifiers, ids.isEmpty {
                Self.logger.info("📨 No discussions match constraints, returning empty")
                response = INSearchForMessagesIntentResponse(code: .success, userActivity: nil)
                response.messages = []
                return response
            }

            var receivedMessages: [INMessage] = []
            var sentMessages: [INMessage] = []

            if direction.searchReceived {
                if let ids = discussionIdentifiers {
                    Self.logger.info("📨 Fetching received messages across \(ids.count) matched discussion(s)")
                    receivedMessages = try await PersistedMessageReceived.fetchLastReceivedINMessages(discussionIdentifiers: ids, restrictToNewMessages: restrictToNewMessages, searchTerms: searchTerms, startDate: startDate, endDate: endDate)
                } else {
                    Self.logger.info("📨 Fetching received messages across all discussions")
                    receivedMessages = try await PersistedMessageReceived.fetchLastReceivedINMessages(restrictToNewMessages: restrictToNewMessages, searchTerms: searchTerms, startDate: startDate, endDate: endDate)
                }

                // NSE database: include pending received messages that haven't been drained into the
                // app DB yet, so Siri can read messages the user already saw notifications for.
                // `appKnownIdentifiers` fast-excludes identifiers already in the app-DB new-messages
                // result; `filterOutMessagesExistingInAppDatabase` then removes any NSE row that has
                // since been drained into the app DB (and possibly marked as read), preventing
                // already-read messages from resurfacing on subsequent Siri queries.
                //
                // For new-messages queries we additionally exclude identifiers recorded in
                // `SiriReadIntentStore`: an NSE-only message that Siri already read aloud and marked
                // read has no `PersistedMessageReceived` to flip yet, so neither `appKnownIdentifiers`
                // nor `filterOutMessagesExistingInAppDatabase` would catch it — without this it would
                // be re-read every time a newly arrived message triggers a fresh "read my new messages".
                // The store entry survives exactly until the app drains the message (at which point
                // the NSE-DB fetch's own `wasPersistedInApp` filter takes over), so there is no gap.
                // This mirrors the app-DB behavior, where read messages still surface in non-unread
                // queries, by gating the exclusion on `restrictToNewMessages`.
                //
                // Skipped entirely when `nseStackAvailable` is false (stack init failed in
                // `IntentHandler.handler(for:)`), since accessing `ObvUserNotificationsStack.shared`
                // would fatal-error. A runtime failure of the fetch itself is also non-fatal:
                // we log and serve the app-DB-only result rather than failing the whole search.
                if nseStackAvailable {
                    do {
                        // Force-consume user-notifications history first, for the same reason as the
                        // App-DB catch-up above: without it the fetch below could read a stale row
                        // cache and re-surface pending messages the NSE or app has since changed.
                        await nseHistoryMerger?.mergePendingTransactionsAndWait()

                        var excludedIdentifiers = Set(receivedMessages.compactMap { ObvMessageAppIdentifier($0.identifier) })
                        if restrictToNewMessages {
                            excludedIdentifiers.formUnion(await SiriReadIntentStore.shared.allMarkedAsReadBySiri())
                        }
                        Self.logger.info("📨 Fetching pending received messages from NSE database (excluding \(excludedIdentifiers.count) identifier(s))")
                        let pendingMessages = try await PersistedUserNotification.fetchPendingINMessages(
                            discussionIdentifiers: discussionIdentifiers,
                            excludingMessageAppIdentifiers: excludedIdentifiers,
                            searchTerms: searchTerms,
                            startDate: startDate,
                            endDate: endDate,
                            fetchLimit: 100)
                        Self.logger.info("📨 Fetched \(pendingMessages.count) pending message(s) from NSE database")
                        let trulyPendingMessages = try await filterOutMessagesExistingInAppDatabase(pendingMessages)
                        Self.logger.info("📨 \(trulyPendingMessages.count) of \(pendingMessages.count) NSE message(s) not yet in app database")
                        receivedMessages.append(contentsOf: trulyPendingMessages)
                    } catch {
                        Self.logger.error("📨 Failed to fetch pending messages from NSE database, continuing with app-DB results only: \(error)")
                    }
                } else {
                    Self.logger.info("📨 Skipping NSE database fetch — user-notifications stack is not available in this extension session")
                }
            }

            if direction.searchSent {
                if let ids = discussionIdentifiers {
                    Self.logger.info("📨 Fetching sent messages across \(ids.count) matched discussion(s)")
                    sentMessages = try await PersistedMessageSent.fetchLastSentINMessages(discussionIdentifiers: ids, searchTerms: searchTerms, startDate: startDate, endDate: endDate)
                } else {
                    Self.logger.info("📨 Fetching sent messages across all discussions")
                    sentMessages = try await PersistedMessageSent.fetchLastSentINMessages(searchTerms: searchTerms, startDate: startDate, endDate: endDate)
                }
            }

            let inMessages = Self.mergeByDate(receivedMessages, sentMessages, cap: 100)
            Self.logger.info("📨 Response messages count=\(inMessages.count) (received=\(receivedMessages.count), sent=\(sentMessages.count))")
            response = INSearchForMessagesIntentResponse(code: .success, userActivity: nil)
            response.messages = inMessages

        } catch {

            Self.logger.fault("📨 handle failed: \(error)")
            response = INSearchForMessagesIntentResponse(code: .failure, userActivity: nil)

        }

        return response

    }

}


// MARK: - Private helpers

extension SearchForMessagesIntentHandler {
    
    /// Resolves a list of persons, propagating a shared owned-identity constraint extracted from any
    /// `isMe` person that carries a known `ObvCryptoId`. If two `isMe` persons carry conflicting
    /// crypto IDs the query is contradictory and every result is `.unsupported()`.
    private func resolvePersons(persons: [INPerson]) async throws -> [INPersonResolutionResult] {

        var ownedCryptoIdConstraint: ObvCryptoId? = nil
        for person in persons where person.isMe {
            let customId = person.customIdentifier ?? person.siriMatches?.first?.customIdentifier
            guard let customId, let cryptoId = ObvCryptoId(customId) else { continue }
            if let existing = ownedCryptoIdConstraint, existing != cryptoId {
                Self.logger.error("📨 Conflicting owned crypto IDs in persons list — returning unsupported for all")
                return Array(repeating: .unsupported(), count: persons.count)
            }
            ownedCryptoIdConstraint = cryptoId
        }

        var result: [INPersonResolutionResult] = []
        for person in persons {
            result.append(try await resolvePerson(person: person, restrictedTo: ownedCryptoIdConstraint))
        }
        return result

    }


    /// Resolves a single `INPerson` to a canonical Olvid `INPerson` carrying our internal identifier.
    ///
    /// - If `person.isMe`: resolves against `PersistedObvOwnedIdentity`. A `customIdentifier`
    ///   encoding an `ObvCryptoId` is verified directly (rejected if it conflicts with
    ///   `ownedCryptoId`). When `ownedCryptoId` is set but no `customIdentifier` is present, that
    ///   profile is returned directly; otherwise all non-hidden profiles are returned (`.success` if
    ///   unique, `.disambiguation` if multiple).
    /// - Otherwise: resolves against `PersistedObvContactIdentity` (any OneToOne status). A
    ///   `customIdentifier` encoding an `ObvContactIdentifier` is verified directly and rejected if
    ///   its embedded `ownedCryptoId` conflicts with `ownedCryptoId`. For display-name searches the
    ///   search is scoped to `ownedCryptoId` when set, otherwise it spans all non-hidden owned
    ///   identities (`.success` on exact match, `.confirmationRequired` on fuzzy, `.disambiguation`
    ///   on multiple matches).
    private func resolvePerson(person: INPerson, restrictedTo ownedCryptoId: ObvCryptoId?) async throws -> INPersonResolutionResult {

        Self.logger.info("📨 Resolving person '\(person.displayName, privacy: .private)'")

        if person.isMe {

            if let customId = person.customIdentifier ?? person.siriMatches?.first?.customIdentifier,
               let resolvedId = ObvCryptoId(customId) {
                if let ownedCryptoId, resolvedId != ownedCryptoId {
                    Self.logger.error("📨 isMe person's ObvCryptoId conflicts with owned identity constraint")
                    return .unsupported()
                }
                Self.logger.info("📨 Person has CryptoId customIdentifier, verifying against database")
                guard let ownedINPerson = try await PersistedObvOwnedIdentity.getOwnedIdentityAsINPerson(ownedCryptoId: resolvedId) else {
                    Self.logger.error("📨 Owned Identity not found in database")
                    return .unsupported()
                }
                return .success(with: ownedINPerson)
            } else if let ownedCryptoId {
                Self.logger.info("📨 isMe person has no customIdentifier, fetching constrained owned identity")
                guard let ownedINPerson = try await PersistedObvOwnedIdentity.getOwnedIdentityAsINPerson(ownedCryptoId: ownedCryptoId) else {
                    Self.logger.error("📨 Constrained owned identity not found in database")
                    return .unsupported()
                }
                return .success(with: ownedINPerson)
            } else {
                Self.logger.info("📨 isMe person has no customIdentifier, returning all non-hidden profiles")
                let ownedINPersons = try await PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentitiesAsINPerson()
                switch ownedINPersons.count {
                case ...0:
                    return .unsupported()
                case 1:
                    return .success(with: ownedINPersons.first!)
                default:
                    return .disambiguation(with: ownedINPersons)
                }
            }

        } else {

            if let customId = person.customIdentifier ?? person.siriMatches?.first?.customIdentifier,
               let contactIdentifier = ObvContactIdentifier(customId) {
                if let ownedCryptoId, contactIdentifier.ownedCryptoId != ownedCryptoId {
                    Self.logger.error("📨 Contact '\(person.displayName, privacy: .private)' ownedCryptoId conflicts with constraint")
                    return .unsupported()
                }
                Self.logger.info("📨 Person has ObvContactIdentifier customIdentifier, verifying against database")
                // .any: message search spans all contacts regardless of one-to-one status.
                guard let contactINPerson = try await PersistedObvContactIdentity.getContactAsINPerson(contactIdentifier: contactIdentifier, whereOneToOneStatusIs: .any) else {
                    Self.logger.error("📨 Contact '\(person.displayName, privacy: .private)' not found in database")
                    return .unsupported()
                }
                Self.logger.info("📨 Contact verified, returning success")
                return .success(with: contactINPerson)
            } else {
                let searchQuery: String
                if !person.displayName.isEmpty {
                    searchQuery = person.displayName
                } else if let siriMatch = person.siriMatches?.first, !siriMatch.displayName.isEmpty {
                    searchQuery = siriMatch.displayName
                    Self.logger.info("📨 displayName empty, falling back to siriMatches displayName '\(searchQuery, privacy: .private)'")
                } else {
                    Self.logger.info("📨 Person has no customIdentifier and no display name, returning unsupported")
                    return .unsupported()
                }

                Self.logger.info("📨 Falling back to display-name search for '\(searchQuery, privacy: .private)'")
                let contacts: [INPerson]
                if let ownedCryptoId {
                    contacts = try await PersistedObvContactIdentity.getAllReachableContactsAsINPerson(searchText: searchQuery, ownedCryptoId: ownedCryptoId)
                } else {
                    contacts = try await PersistedObvContactIdentity.getAllReachableContactsOfNonHiddenOwnedIdentitiesAsINPerson(searchText: searchQuery)
                }
                Self.logger.info("📨 Found \(contacts.count) contact(s) for query '\(searchQuery, privacy: .private)'")

                switch contacts.count {
                case ...0:
                    return .unsupported()
                case 1:
                    let contact = contacts.first!
                    let isExactMatch = contact.displayName.caseInsensitiveCompare(searchQuery) == .orderedSame
                    Self.logger.info("📨 Single match (exact=\(isExactMatch)), returning \(isExactMatch ? "success" : "confirmationRequired")")
                    return isExactMatch ? .success(with: contact) : .confirmationRequired(with: contact)
                default:
                    Self.logger.info("📨 Multiple matches, requesting disambiguation")
                    return .disambiguation(with: contacts)
                }
            }

        }

    }

    
    /// Returns the set of discussions to search within, derived from direct conversation identifiers,
    /// resolved group names, and resolved sender/recipient contacts.
    ///
    /// Returns `nil` when no constraints are present (caller should search all discussions),
    /// an empty set when constraints produce no matching discussions, and a non-empty set otherwise.
    ///
    /// `conversationIdentifiers` and `speakableGroupNames` are always unioned (their individual
    /// operators are not applied — union is the only meaningful semantics for distinct identifiers).
    /// `senders` are combined with `sendersOperator` and `recipients` with `recipientsOperator`:
    /// `.any` produces a union; `.all` produces an intersection; `.none` is treated as `.any`.
    /// All non-nil constraint groups are then intersected with each other.
    /// `isMe` persons are skipped for discussion scoping — they don't narrow the discussion set.
    private func getDiscussionIdentifiers(
        conversationIdentifiers: [String]?,
        speakableGroupNames: [INSpeakableString]?,
        senders: [INPerson]?,
        sendersOperator: INConditionalOperator,
        recipients: [INPerson]?,
        recipientsOperator: INConditionalOperator
    ) async throws -> Set<ObvDiscussionIdentifier>? {

        // Direct identifiers — union of decoded conversationIdentifiers and group name vocabularyIdentifiers
        var decoded = Set<ObvDiscussionIdentifier>()
        for id in conversationIdentifiers ?? [] {
            if let d = ObvDiscussionIdentifier(id) {
                // Direct form: the `conversationIdentifier` we set on `INMessage` / `INSendMessageIntent`,
                // which is exactly an `ObvDiscussionIdentifier.description`.
                decoded.insert(d)
            } else if let d = ObvUserNotificationThread(threadIdentifier: id)?.discussionIdentifier {
                // Thread-identifier form: for a message search, iOS hands us back the
                // posting notification's `threadIdentifier` (the notification-grouping key) rather than the
                // `INSendMessageIntent.conversationIdentifier`. That string is namespaced, so it doesn't
                // decode directly — recover the discussion from it via the shared `ObvUserNotificationThread`.
                decoded.insert(d)
            }
        }
        for groupName in speakableGroupNames ?? [] {
            if let v = groupName.vocabularyIdentifier, let d = ObvDiscussionIdentifier(v) { decoded.insert(d) }
        }
        let directIdentifiers: Set<ObvDiscussionIdentifier>? = decoded.isEmpty ? nil : decoded

        // Sender-based identifiers
        let senderContactIds: [ObvContactIdentifier] = (senders ?? []).compactMap { person in
            guard !person.isMe, let value = person.personHandle?.value else { return nil }
            return ObvContactIdentifier(value)
        }
        let senderIdentifiers = try await discussionIdentifiers(for: senderContactIds, combining: sendersOperator)

        // Recipient-based identifiers
        let recipientContactIds: [ObvContactIdentifier] = (recipients ?? []).compactMap { person in
            guard !person.isMe, let value = person.personHandle?.value else { return nil }
            return ObvContactIdentifier(value)
        }
        let recipientIdentifiers = try await discussionIdentifiers(for: recipientContactIds, combining: recipientsOperator)

        // Intersect all non-nil constraint groups
        var result: Set<ObvDiscussionIdentifier>? = directIdentifiers
        for constraint in [senderIdentifiers, recipientIdentifiers].compactMap({ $0 }) {
            result = result.map { $0.intersection(constraint) } ?? constraint
        }
        return result

    }


    /// Applies `op` across the discussion sets of each contact: `.all` intersects, everything else unions.
    /// Returns `nil` when `contactIds` is empty (no constraint contributed).
    private func discussionIdentifiers(for contactIds: [ObvContactIdentifier], combining op: INConditionalOperator) async throws -> Set<ObvDiscussionIdentifier>? {
        guard !contactIds.isEmpty else { return nil }
        switch op {
        case .all:
            var intersection: Set<ObvDiscussionIdentifier>? = nil
            for contactId in contactIds {
                let ids = try await PersistedObvContactIdentity.getAllDiscussionIdentifiers(contactIdentifier: contactId)
                intersection = intersection.map { $0.intersection(ids) } ?? ids
            }
            return intersection
        default:
            var union = Set<ObvDiscussionIdentifier>()
            for contactId in contactIds {
                union.formUnion(try await PersistedObvContactIdentity.getAllDiscussionIdentifiers(contactIdentifier: contactId))
            }
            return union
        }
    }

    
    /// Decides whether to look in `PersistedMessageReceived`, `PersistedMessageSent`, or both,
    /// based on SiriKit semantics:
    /// - `senders` carries the people the messages came FROM, so `isMe` in senders → search Sent.
    /// - `recipients` carries the people the messages went TO, so non-`isMe` in recipients → search Sent.
    /// - Conversely, non-`isMe` senders or `isMe` recipients → search Received.
    /// - "Only `isMe`" case (every constrained person is the owned identity, no third party) → search
    ///   both, so notes-to-self in self-only group discussions (stored only in `PersistedMessageSent`)
    ///   surface under "messages to me" as well as "messages from me".
    /// - No constraints at all → Received only (matches the prior behavior for "read my messages").
    /// - `restrictToNewMessages` forces Received only: only inbound messages have an unread state.
    private static func searchDirection(senders: [INPerson]?, recipients: [INPerson]?, restrictToNewMessages: Bool) -> (searchReceived: Bool, searchSent: Bool) {

        if restrictToNewMessages {
            return (searchReceived: true, searchSent: false)
        }

        let sendersHasMe = senders?.contains(where: { $0.isMe }) ?? false
        let sendersHasOther = senders?.contains(where: { !$0.isMe }) ?? false
        let recipientsHasMe = recipients?.contains(where: { $0.isMe }) ?? false
        let recipientsHasOther = recipients?.contains(where: { !$0.isMe }) ?? false

        let onlyMeInvolved = (sendersHasMe || recipientsHasMe) && !sendersHasOther && !recipientsHasOther
        if onlyMeInvolved {
            return (searchReceived: true, searchSent: true)
        }

        let searchSent = sendersHasMe || recipientsHasOther
        let searchReceived = sendersHasOther || recipientsHasMe

        if !searchReceived && !searchSent {
            return (searchReceived: true, searchSent: false)
        }

        return (searchReceived: searchReceived, searchSent: searchSent)

    }


    /// Resolves `INDateComponentsRange.startDateComponents` / `endDateComponents` to absolute
    /// `Date` values using the current calendar. Either side returns `nil` when the corresponding
    /// `DateComponents` is `nil` or cannot be resolved against the calendar, producing an
    /// open-ended range on that side in the downstream fetch.
    private static func dateRange(from range: INDateComponentsRange?) -> (start: Date?, end: Date?) {
        guard let range else { return (nil, nil) }
        let calendar = Calendar.current
        let start = range.startDateComponents.flatMap { ($0.calendar ?? calendar).date(from: $0) }
        let end = range.endDateComponents.flatMap { ($0.calendar ?? calendar).date(from: $0) }
        return (start, end)
    }


    /// Keeps the `cap` most recent INMessages across both lists (by `dateSent`) and returns them in
    /// ascending date order, so Siri reads them oldest-first. Messages without a `dateSent` are
    /// treated as `.distantPast` and therefore drop out first when the cap is applied.
    private static func mergeByDate(_ a: [INMessage], _ b: [INMessage], cap: Int) -> [INMessage] {
        let all = (a + b).sorted { ($0.dateSent ?? .distantPast) > ($1.dateSent ?? .distantPast) }
        let capped = Array(all.prefix(cap))
        return capped.sorted { ($0.dateSent ?? .distantPast) < ($1.dateSent ?? .distantPast) }
    }


    /// Returns the subset of `messages` whose identifier is NOT present in the app database.
    ///
    /// NSE-DB rows are not purged immediately after being drained into the app database. Without
    /// this filter, a message that was already read (status `.read` or `.unread` in the app DB)
    /// would re-appear from the NSE DB on the next Siri query, causing it to be read aloud again.
    /// Messages whose identifier cannot be parsed are kept (safe default).
    private func filterOutMessagesExistingInAppDatabase(_ messages: [INMessage]) async throws -> [INMessage] {
        guard !messages.isEmpty else { return [] }
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<[INMessage], any Error>, context: NSManagedObjectContext) in
            var result: [INMessage] = []
            for message in messages {
                guard let identifier = ObvMessageAppIdentifier(message.identifier) else {
                    result.append(message)
                    continue
                }
                let existsInAppDB = try PersistedMessage.getMessage(messageAppIdentifier: identifier, within: context) != nil
                if !existsInAppDB {
                    result.append(message)
                }
            }
            continuation.resume(returning: result)
        }
    }


    /// Resolves Siri's explicit message scoping to the exact `INMessage`s requested. Sources each
    /// message from the app database first (full content via ``PersistedMessageReceived/inMessages`` —
    /// text, attachments, location, with any sender edit applied) and falls back to the NSE database
    /// payload for any message not yet drained into the app DB. Returns the messages in ascending date
    /// order (oldest-first), matching the main fetch path so Siri reads them in order.
    ///
    /// - `messageIdentifierStrings`: values from `intent.identifiers` — `ObvMessageAppIdentifier`
    ///   descriptions we previously handed Siri in `INMessage.identifier`; parsed directly.
    /// - `notificationRequestIdentifiers`: values from `intent.notificationIdentifiers` —
    ///   `UNNotificationRequest` identifiers, resolved to `ObvMessageAppIdentifier`s via the NSE
    ///   database. Requires `nseStackAvailable`; when the user-notifications stack is down they cannot
    ///   be resolved and are skipped (we return whatever `identifiers` produced — never the backlog).
    private func fetchINMessagesScopedToExplicitIdentifiers(messageIdentifierStrings: [String], notificationRequestIdentifiers: [String]) async throws -> [INMessage] {

        var targets = Set<ObvMessageAppIdentifier>(messageIdentifierStrings.compactMap { ObvMessageAppIdentifier($0) })

        if !notificationRequestIdentifiers.isEmpty {
            if nseStackAvailable {
                // Force-consume user-notifications history first, so the lookup doesn't read a stale row
                // cache that misses a notification the NSE just inserted (same concern as the
                // pending-message fetch in `handle(intent:)`).
                await nseHistoryMerger?.mergePendingTransactionsAndWait()
                let resolved = try await PersistedUserNotification.fetchMessageAppIdentifiers(forRequestIdentifiers: Set(notificationRequestIdentifiers))
                Self.logger.info("📨 Resolved \(resolved.count) message identifier(s) from \(notificationRequestIdentifiers.count) notification identifier(s)")
                targets.formUnion(resolved)
            } else {
                Self.logger.info("📨 Cannot resolve notificationIdentifiers — user-notifications stack unavailable")
            }
        }

        guard !targets.isEmpty else { return [] }

        // App database first (richest representation: text, attachments, location, applied edits),
        // falling back to the NSE-database payload for any target not yet drained into the app DB.
        let appDBMessages = try await PersistedMessageReceived.fetchReceivedINMessages(messageAppIdentifiers: targets)
        let resolvedInAppDB = Set(appDBMessages.compactMap { ObvMessageAppIdentifier($0.identifier) })
        let missing = targets.subtracting(resolvedInAppDB)

        var inMessages = appDBMessages
        if !missing.isEmpty, nseStackAvailable {
            let nseMessages = try await PersistedUserNotification.fetchINMessages(forMessageAppIdentifiers: missing)
            inMessages.append(contentsOf: nseMessages)
        }

        return inMessages.sorted { ($0.dateSent ?? .distantPast) < ($1.dateSent ?? .distantPast) }

    }


}

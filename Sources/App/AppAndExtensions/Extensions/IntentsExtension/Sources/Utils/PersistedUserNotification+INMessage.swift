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
import Intents
import CoreData
import ObvAppTypes
import ObvCommunicationInteractor
import ObvTypes
import ObvUICoreData
import ObvUserNotificationsDatabase


extension PersistedUserNotification {

    /// A pending received-message notification reduced to what the Intents extension needs to build an
    /// `INMessage`: the message/discussion identifiers and the original (plus optional update) payload.
    fileprivate typealias Pending = (messageAppIdentifier: ObvMessageAppIdentifier,
                                     discussionIdentifier: ObvDiscussionIdentifier,
                                     obvMessage: ObvMessage,
                                     obvMessageUpdate: ObvMessage?)

    /// Returns text-only `INMessage`s for pending received-message notifications stored in the NSE
    /// database whose corresponding `PersistedMessageReceived` doesn't yet exist in the app database.
    ///
    /// The NSE-DB fetch applies the `discussionIdentifiers` / `startDate` / `endDate` filters at the
    /// SQL level (see ``getPendingReceivedMessagesForIntents(discussionIdentifiers:startDate:endDate:fetchLimit:within:)``).
    /// Identifiers listed in `excludingMessageAppIdentifiers` (rows already returned by the app-DB
    /// query) are stripped post-fetch as a race safety net. Bodies are decoded from `messagePayload`
    /// and `searchTerms` are then applied as case- and diacritic-insensitive substring matches (all
    /// terms must match). Finally, sender `INPerson`, group name and recipients are resolved against
    /// the app database in a single context. Attachments are not produced — they haven't been
    /// downloaded at the NSE stage.
    static func fetchPendingINMessages(
        discussionIdentifiers: Set<ObvDiscussionIdentifier>?,
        excludingMessageAppIdentifiers: Set<ObvMessageAppIdentifier>,
        searchTerms: [String]?,
        startDate: Date?,
        endDate: Date?,
        fetchLimit: Int
    ) async throws -> [INMessage] {

        // 1) Fetch pending rows from the NSE database.
        let pendings: [Pending] = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Pending], any Error>) in
            ObvUserNotificationsStack.shared.performBackgroundTask { context in
                do {
                    let rows = try PersistedUserNotification.getPendingReceivedMessagesForIntents(
                        discussionIdentifiers: discussionIdentifiers,
                        excludingMessageAppIdentifiers: excludingMessageAppIdentifiers,
                        startDate: startDate,
                        endDate: endDate,
                        fetchLimit: fetchLimit,
                        within: context)
                    continuation.resume(returning: rows)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // 2) Decode bodies (applying the search-term filter) and resolve to INMessage.
        return try await buildINMessages(from: pendings, searchTerms: searchTerms)

    }


    /// Resolves notification request identifiers (`UNNotificationRequest.identifier`, i.e. the strings
    /// the system passes in `INSearchForMessagesIntent.notificationIdentifiers`) to the app message
    /// identifiers of the received messages they represent, by querying the NSE database. See
    /// ``PersistedUserNotification/getMessageAppIdentifiers(forRequestIdentifiers:within:)`` for the
    /// filtering applied (received messages only, `.newMessage` category, regardless of read/drain
    /// state). Returns an empty array for an empty input.
    static func fetchMessageAppIdentifiers(forRequestIdentifiers requestIdentifiers: Set<String>) async throws -> [ObvMessageAppIdentifier] {
        guard !requestIdentifiers.isEmpty else { return [] }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ObvMessageAppIdentifier], any Error>) in
            ObvUserNotificationsStack.shared.performBackgroundTask { context in
                do {
                    let ids = try PersistedUserNotification.getMessageAppIdentifiers(forRequestIdentifiers: requestIdentifiers, within: context)
                    continuation.resume(returning: ids)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }


    /// Builds text-only `INMessage`s from the NSE database for the given `messageAppIdentifiers`,
    /// using each notification's stored payload. Used by the scoped Siri path as a
    /// fallback for messages that were requested by identifier but have no `PersistedMessageReceived`
    /// in the app database yet. Identifiers with no matching `.shown` received-message notification are
    /// skipped. Unlike ``fetchPendingINMessages`` no search-term / date filtering applies — Siri
    /// asked for these specific messages.
    static func fetchINMessages(forMessageAppIdentifiers messageAppIdentifiers: Set<ObvMessageAppIdentifier>) async throws -> [INMessage] {
        guard !messageAppIdentifiers.isEmpty else { return [] }

        // 1) Fetch payloads from the NSE database by explicit identifier.
        let pendings: [Pending] = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Pending], any Error>) in
            ObvUserNotificationsStack.shared.performBackgroundTask { context in
                do {
                    var rows: [Pending] = []
                    for messageAppIdentifier in messageAppIdentifiers {
                        guard let row = try PersistedUserNotification.getPendingReceivedMessageForIntents(messageAppIdentifier: messageAppIdentifier, within: context) else {
                            continue
                        }
                        rows.append((messageAppIdentifier: messageAppIdentifier,
                                     discussionIdentifier: row.discussionIdentifier,
                                     obvMessage: row.obvMessage,
                                     obvMessageUpdate: row.obvMessageUpdate))
                    }
                    continuation.resume(returning: rows)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // 2) Decode bodies and resolve to INMessage.
        return try await buildINMessages(from: pendings, searchTerms: nil)

    }


    /// Decodes the (latest) body for each pending row — applying `searchTerms` when provided — then
    /// resolves sender `INPerson`, group name and recipients against the app database in a single
    /// context, producing one text `INMessage` per row. Rows whose body is empty/undecodable, that
    /// fail the search-term filter, or whose discussion belongs to a hidden owned profile are dropped.
    private static func buildINMessages(from pendings: [Pending], searchTerms: [String]?) async throws -> [INMessage] {

        guard !pendings.isEmpty else { return [] }

        struct Decoded {
            let messageAppIdentifier: ObvMessageAppIdentifier
            let discussionIdentifier: ObvDiscussionIdentifier
            let contactIdentifier: ObvContactIdentifier
            let body: String
            let dateSent: Date
        }
        let decoded: [Decoded] = pendings.compactMap { pending in
            let latest = pending.obvMessageUpdate ?? pending.obvMessage
            guard let body = decodeBody(messagePayload: latest.messagePayload, isUpdate: pending.obvMessageUpdate != nil),
                  !body.isEmpty else {
                return nil
            }
            if let searchTerms, !searchTerms.isEmpty {
                let allMatch = searchTerms.allSatisfy { term in
                    term.isEmpty || body.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                }
                guard allMatch else { return nil }
            }
            return Decoded(messageAppIdentifier: pending.messageAppIdentifier,
                           discussionIdentifier: pending.discussionIdentifier,
                           contactIdentifier: pending.obvMessage.fromContactIdentity,
                           body: body,
                           dateSent: latest.messageUploadTimestampFromServer)
        }

        guard !decoded.isEmpty else { return [] }

        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<[INMessage], any Error>, context: NSManagedObjectContext) in
            var inMessages: [INMessage] = []
            for d in decoded {
                guard let discussion = try PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: d.discussionIdentifier, within: context),
                      discussion.ownedIdentity?.isHidden == false else {
                    continue
                }
                let contact = try PersistedObvContactIdentity.get(persisted: d.contactIdentifier, whereOneToOneStatusIs: .any, within: context)
                let sender = try? contact?.toINPerson(withImage: false)
                let groupName: INSpeakableString? = discussion.isOneToOne ? nil : INSpeakableString(spokenPhrase: discussion.title)
                let recipients: [INPerson]? = discussion.isOneToOne ? nil : (try? discussion.contactsINPerson)
                inMessages.append(INMessage(
                    identifier: d.messageAppIdentifier.description,
                    conversationIdentifier: d.discussionIdentifier.description,
                    content: d.body,
                    dateSent: d.dateSent,
                    sender: sender,
                    recipients: recipients,
                    groupName: groupName,
                    messageType: .text))
            }
            continuation.resume(returning: inMessages)
        }

    }


    /// Extracts the body from a decoded `messagePayload`. For an update payload the body lives at
    /// `updateMessageJSON.newBodyAndMentions.body`; for an original message it lives at
    /// `message.bodyAndMentions.body`.
    private static func decodeBody(messagePayload: Data, isUpdate: Bool) -> String? {
        guard let json = try? PersistedItemJSON.jsonDecode(messagePayload) else { return nil }
        if isUpdate {
            return json.updateMessageJSON?.newBodyAndMentions?.body
        }
        return json.message?.bodyAndMentions?.body
    }

}

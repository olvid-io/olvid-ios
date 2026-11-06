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
import CoreData
import OSLog
import ObvAppCoreConstants
import ObvAppTypes
import ObvCoreDataStack
import ObvTypes
import ObvUICoreData
import OlvidUtils

/// Handles `INSendMessageIntent` within the Intents extension.
///
/// Supports sending a text or audio message to one or more discussions directly from Siri or
/// CarPlay, without launching the main app.
///
/// **Supported addressing modes**
/// - **Individual recipients** — "Send Hello to Alice and Bob": each name is resolved to its
///   one-to-one discussion independently. The same message is sent to every resolved discussion.
/// - **Group by spoken name** — "Send Hello to the Family group": the group name is resolved via
///   ``resolveSpeakableGroupName(for:)`` to a single group discussion.
/// - **Known conversation** — triggered programmatically (e.g. a CarPlay tap) with a pre-set
///   `conversationIdentifier`; resolved immediately without any name search.
///
/// **Intent lifecycle**
/// 1. ``resolveRecipients(for:)`` — routes to one of the three addressing modes above. For group
///    sends, delegates to ``resolveSpeakableGroupName(for:)`` and returns `.notRequired()`.
/// 2. ``resolveSpeakableGroupName(for:)`` — searches group discussions by spoken phrase; returns
///    an `INSpeakableString` whose `vocabularyIdentifier` encodes the `ObvDiscussionIdentifier`.
/// 3. ``resolveOutgoingMessageType(for:)`` — accepts `.outgoingMessageText` and
///    `.outgoingMessageAudio`; defaults any other value (including `.unknown`) to `.outgoingMessageText`.
/// 4. ``resolveContent(for:)`` — requires a non-empty text body for text messages; marks content
///    as not required for audio messages (the audio file is the message).
/// 5. ``confirm(intent:)`` — verifies that all resolved recipients share the same owned identity;
///    returns `.ready` if so, `.failure` if they span multiple profiles or none resolved.
/// 6. ``handle(intent:)`` — sends the message to every resolved discussion. All sends are
///    attempted even if one fails; `.failure` is returned only if at least one send threw.
final class SendMessageIntentHandler: NSObject {
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "SendMessageIntentHandler")
    
    private let coordinator: IntentCoordinator
    
    init(coordinator: IntentCoordinator) {
        self.coordinator = coordinator
    }
    
}


// MARK: - Implementing INSendMessageIntentHandling

extension SendMessageIntentHandler: INSendMessageIntentHandling {

    func resolveRecipients(for intent: INSendMessageIntent) async -> [INSendMessageRecipientResolutionResult] {

        Self.logger.info("💬🏁 Resolving \(intent.recipients?.count ?? 0) recipient(s) for INSendMessageIntent")

        // Specific known conversation (e.g. tapped from CarPlay)
        if let conversationIdentifier = intent.conversationIdentifier,
           let discussionIdentifier = ObvDiscussionIdentifier(conversationIdentifier) {
            Self.logger.info("💬 Using conversationIdentifier path")
            do {
                guard let inPerson = try await PersistedDiscussion
                    .discussionAsINPersonFromDiscussionIdentifier(discussionIdentifier) else {
                    Self.logger.error("💬 Discussion not found for conversationIdentifier")
                    return [.unsupported(forReason: .noHandleForLabel)]
                }
                Self.logger.info("💬 Resolved discussion via conversationIdentifier")
                return [.success(with: inPerson)]
            } catch {
                Self.logger.fault("💬 Failed to fetch discussion for conversationIdentifier: \(error)")
                return [.unsupported(forReason: .noHandleForLabel)]
            }
        }

        // Group send — resolveSpeakableGroupName handles the group; no individual recipients needed
        if intent.speakableGroupName != nil {
            Self.logger.info("💬 speakableGroupName is set, recipients not required for group send")
            return [.notRequired()]
        }

        // One or more individual recipients — resolve each one independently
        let recipients = intent.recipients ?? []
        guard !recipients.isEmpty else {
            Self.logger.info("💬 No recipients and no conversationIdentifier/speakableGroupName, asking Siri for a value")
            return [.needsValue()]
        }

        Self.logger.info("💬 Resolving \(recipients.count) individual recipient(s)")
        var results: [INSendMessageRecipientResolutionResult] = []
        for recipient in recipients {
            results.append(await resolveRecipient(recipient))
        }
        Self.logger.info("💬 Returning \(results.count) resolution result(s)")
        return results

    }


    /// Resolves the `speakableGroupName` field of an `INSendMessageIntent`.
    ///
    /// Returns `.notRequired()` when `intent.speakableGroupName` is nil (the user addressed
    /// individual recipients instead of a group). Otherwise delegates to
    /// `PersistedDiscussion.resolveGroupName(_:)`.
    func resolveSpeakableGroupName(for intent: INSendMessageIntent) async -> INSpeakableStringResolutionResult {

        Self.logger.info("💬🏁 Resolving speakableGroupName for INSendMessageIntent")

        guard let groupName = intent.speakableGroupName else {
            Self.logger.info("💬 No speakableGroupName set, returning notRequired")
            return .notRequired()
        }

        Self.logger.info("💬 Resolving group name '\(groupName.spokenPhrase, privacy: .private)'")
        return await PersistedDiscussion.resolveGroupName(groupName)

    }


    func resolveOutgoingMessageType(for intent: INSendMessageIntent) async -> INOutgoingMessageTypeResolutionResult {
        switch intent.outgoingMessageType {
        case .outgoingMessageText, .outgoingMessageAudio:
            return .success(with: intent.outgoingMessageType)
        default:
            // .unknown and any future cases default to text so Siri never stalls on type resolution.
            return .success(with: .outgoingMessageText)
        }
    }


    func resolveContent(for intent: INSendMessageIntent) async -> INStringResolutionResult {
        switch intent.outgoingMessageType {
        case .outgoingMessageText:
            guard let text = intent.content, !text.isEmpty else { return .needsValue() }
            return .success(with: text)
        case .outgoingMessageAudio:
            let audioFiles = (intent.attachments ?? []).compactMap { $0.audioMessageFile }
            return audioFiles.isEmpty ? .needsValue() : .notRequired()
        default:
            return .needsValue()
        }
    }


    func confirm(intent: INSendMessageIntent) async -> INSendMessageIntentResponse {
        Self.logger.info("💬🏁 Confirming INSendMessageIntent")

        var ownedCryptoIds = Set<ObvCryptoId>()

        if let conversationIdentifier = intent.conversationIdentifier,
           let discussionId = ObvDiscussionIdentifier(conversationIdentifier) {
            // Single known discussion (e.g. CarPlay tap) — profile constraint trivially satisfied.
            ownedCryptoIds.insert(discussionId.ownedCryptoId)
        } else if let vocabularyIdentifier = intent.speakableGroupName?.vocabularyIdentifier,
                  let discussionId = ObvDiscussionIdentifier(vocabularyIdentifier) {
            // Group send — single discussion, profile constraint trivially satisfied.
            ownedCryptoIds.insert(discussionId.ownedCryptoId)
        } else {
            // Individual recipients — verify all belong to the same owned profile.
            for recipient in intent.recipients ?? [] {
                guard let value = recipient.personHandle?.value,
                      let discussionId = ObvDiscussionIdentifier(value) else {
                    Self.logger.error("💬 A resolved recipient is missing its discussion identifier in confirm")
                    return INSendMessageIntentResponse(code: .failure, userActivity: nil)
                }
                ownedCryptoIds.insert(discussionId.ownedCryptoId)
            }
        }

        guard ownedCryptoIds.count == 1 else {
            if ownedCryptoIds.isEmpty {
                Self.logger.fault("💬 No recipients resolved to a discussion — confirm should not be reached without resolved recipients")
            } else {
                Self.logger.error("💬 Recipients span \(ownedCryptoIds.count) profiles — cannot send a single message across profiles")
            }
            return INSendMessageIntentResponse(code: .failure, userActivity: nil)
        }

        Self.logger.info("💬 All recipients belong to the same profile, returning .ready")
        return INSendMessageIntentResponse(code: .ready, userActivity: nil)
    }


    func handle(intent: INSendMessageIntent) async -> INSendMessageIntentResponse {

        Self.logger.info("💬🏁 Handling INSendMessageIntent")

        // For a group send, the resolved group is carried in speakableGroupName.vocabularyIdentifier.
        // For individual sends, each recipient's personHandle.value carries a discussion identifier.
        let discussionIdentifiers: [ObvDiscussionIdentifier]

        if let vocabularyIdentifier = intent.speakableGroupName?.vocabularyIdentifier,
           let discussionIdentifier = ObvDiscussionIdentifier(vocabularyIdentifier) {
            Self.logger.info("💬 Group send via resolved speakableGroupName")
            discussionIdentifiers = [discussionIdentifier]
        } else {
            let recipients = intent.recipients ?? []
            guard !recipients.isEmpty else {
                Self.logger.error("💬 No recipients and no resolved speakableGroupName")
                return INSendMessageIntentResponse(code: .failure, userActivity: nil)
            }
            // Invariant: resolveRecipient stuffed an ObvDiscussionIdentifier into each recipient's personHandle.value.
            let resolved = recipients.compactMap { $0.personHandle?.value.flatMap(ObvDiscussionIdentifier.init) }
            guard resolved.count == recipients.count else {
                Self.logger.error("💬 Could not extract a discussion identifier for every recipient (\(resolved.count)/\(recipients.count) resolved)")
                return INSendMessageIntentResponse(code: .failure, userActivity: nil)
            }
            discussionIdentifiers = resolved
        }

        Self.logger.info("💬 Sending to \(discussionIdentifiers.count) discussion(s)")

        var anyFailed = false

        switch intent.outgoingMessageType {

        case .outgoingMessageText:
            guard let content = intent.content else {
                Self.logger.error("💬 No content for text message")
                return INSendMessageIntentResponse(code: .failure, userActivity: nil)
            }
            let outcomes = await coordinator.sendMessage(
                discussionIdentifiers: discussionIdentifiers,
                textBody: content)
            for (_, result) in outcomes {
                if case .failure(let error) = result {
                    Self.logger.error("💬 Failed to send text message to discussion: \(error)")
                    anyFailed = true
                }
            }

        case .outgoingMessageAudio:
            let audioFiles = (intent.attachments ?? []).compactMap { $0.audioMessageFile }
            // Siri's contract is at most one audio attachment per INSendMessageIntent. The .fault log surfaces
            // any future contract change in prod; the assert catches it during dev/QA.
            if audioFiles.count > 1 {
                Self.logger.fault("💬 Siri unexpectedly handed us \(audioFiles.count) audio attachments; only the first will be used")
            }
            assert(audioFiles.count <= 1, "Siri contract: at most one audio attachment per INSendMessageIntent")
            guard let audioFile = audioFiles.first else {
                Self.logger.error("💬 No audio file for audio message")
                return INSendMessageIntentResponse(code: .failure, userActivity: nil)
            }
            let outcomes = await coordinator.sendMessage(
                discussionIdentifiers: discussionIdentifiers,
                textBody: nil,
                audioFile: audioFile)
            for (_, result) in outcomes {
                if case .failure(let error) = result {
                    Self.logger.error("💬 Failed to send audio message to discussion: \(error)")
                    anyFailed = true
                }
            }

        default:
            Self.logger.error("💬 Unsupported outgoing message type")
            return INSendMessageIntentResponse(code: .failure, userActivity: nil)

        }

        if anyFailed {
            // INSendMessageIntentResponseCode has no .partial, so any single failure forces the whole response to .failure.
            Self.logger.error("💬 One or more sends failed")
            return INSendMessageIntentResponse(code: .failure, userActivity: nil)
        }
        Self.logger.info("💬 All messages sent successfully")
        return INSendMessageIntentResponse(code: .success, userActivity: nil)

    }

}


// MARK: - Private helpers

extension SendMessageIntentHandler {
    
    /// Resolves a single `INPerson` recipient to the `INPerson` representing its discussion.
    ///
    /// Resolution order:
    /// 1. If `customIdentifier` (or the first Siri match's `customIdentifier`) encodes an
    ///    `ObvContactIdentifier` → look up the contact's one-to-one discussion directly.
    /// 2. If it encodes an `ObvDiscussionIdentifier` → look up that discussion directly.
    /// 3. If `customIdentifier` is absent or unrecognised → fall back to a display-name search
    ///    across all discussions (both one-to-one and group) via ``resolveBySearchQuery(_:)``.
    ///
    /// The returned `INPerson` always carries the target `ObvDiscussionIdentifier` as both its
    /// `personHandle.value` and `customIdentifier`, so ``handle(intent:)`` can extract it without
    /// any additional database lookup.
    private func resolveRecipient(_ recipient: INPerson) async -> INSendMessageRecipientResolutionResult {

        Self.logger.info("💬 Resolving recipient '\(recipient.displayName, privacy: .private)'")

        let customId = recipient.customIdentifier ?? recipient.siriMatches?.first?.customIdentifier

        if let customId {
            do {
                if let contactIdentifier = ObvContactIdentifier(customId) {
                    Self.logger.info("💬 Recipient has ObvContactIdentifier customIdentifier, looking up 1:1 discussion")
                    guard let inPerson = try await PersistedObvContactIdentity
                        .oneToOneDiscussionAsINPersonFromContactIdentifier(contactIdentifier: contactIdentifier) else {
                        Self.logger.error("💬 No 1:1 discussion found for contact '\(recipient.displayName, privacy: .private)'")
                        return .unsupported(forReason: .noHandleForLabel)
                    }
                    Self.logger.info("💬 Resolved 1:1 discussion via ObvContactIdentifier")
                    return .success(with: inPerson)
                } else if let discussionIdentifier = ObvDiscussionIdentifier(customId) {
                    Self.logger.info("💬 Recipient has ObvDiscussionIdentifier customIdentifier, looking up discussion")
                    guard let inPerson = try await PersistedDiscussion
                        .discussionAsINPersonFromDiscussionIdentifier(discussionIdentifier) else {
                        Self.logger.error("💬 No discussion found for ObvDiscussionIdentifier of '\(recipient.displayName, privacy: .private)'")
                        return .unsupported(forReason: .noHandleForLabel)
                    }
                    Self.logger.info("💬 Resolved discussion via ObvDiscussionIdentifier")
                    return .success(with: inPerson)
                } else {
                    Self.logger.error("💬 customIdentifier did not decode as ObvContactIdentifier or ObvDiscussionIdentifier for '\(recipient.displayName, privacy: .private)', falling back to display-name search")
                }
            } catch {
                Self.logger.fault("💬 Failed to fetch discussion for recipient '\(recipient.displayName, privacy: .private)': \(error)")
                return .unsupported(forReason: .noHandleForLabel)
            }
        }

        // Fall back to display-name search
        let searchQuery: String
        if !recipient.displayName.isEmpty {
            searchQuery = recipient.displayName
        } else if let siriMatch = recipient.siriMatches?.first, !siriMatch.displayName.isEmpty {
            searchQuery = siriMatch.displayName
        } else {
            Self.logger.info("💬 Recipient has no customIdentifier and no display name, returning unsupported")
            return .unsupported(forReason: .noHandleForLabel)
        }
        Self.logger.info("💬 Falling back to display-name search for '\(searchQuery, privacy: .private)'")
        return await resolveBySearchQuery(searchQuery)
    }


    /// Searches discussions by display name and returns the matching `INSendMessageRecipientResolutionResult`.
    ///
    /// The search is intentionally two-pass to prioritise direct contacts:
    /// 1. First pass searches **one-to-one** discussions only (`restrictToOneToOneDiscussions: true`).
    ///    This is critical to avoid false disambiguation: if the user says "send a message to Bob"
    ///    and Bob is a one-to-one contact, a search across all discussions would also return every
    ///    group Bob is a member of, flooding the disambiguation list with irrelevant results.
    /// 2. If the first pass finds nothing, the method retries across **all** discussions
    ///    (`restrictToOneToOneDiscussions: false`), which also covers group discussions.
    ///    This handles the case where the user names a group without using a group keyword
    ///    (e.g. "send Hello to Project Team" rather than "send Hello to the Project Team group").
    ///
    /// Callers should always use the default (`restrictToOneToOneDiscussions: true`); the `false`
    /// case is only used by the method itself for the retry.
    private func resolveBySearchQuery(_ query: String, restrictToOneToOneDiscussions: Bool = true) async -> INSendMessageRecipientResolutionResult {
        Self.logger.info("💬 Searching discussions for '\(query, privacy: .private)'")
        // The continuation returns nil when there are no results, signalling that the caller
        // should retry with a broader search kind. This keeps all async logic (the retry call)
        // outside the synchronous continuation body, where spawning a Task would be required.
        let result: INSendMessageRecipientResolutionResult?
        do {
            result = try await withCheckedThrowingContextualContinuation { (continuation, context) in
                let discussions = try PersistedDiscussion.searchDiscussions(searchTerm: query, kind: restrictToOneToOneDiscussions ? .oneToOne : .any, with: context)
                Self.logger.info("💬 Found \(discussions.count) discussion(s) for query '\(query, privacy: .private)'")
                switch discussions.count {
                case ...0:
                    continuation.resume(returning: nil)
                case 1:
                    let discussion = discussions.first!
                    let inPerson = try discussion.toINPerson(withImage: true)
                    let isExactMatch = discussion.title.caseInsensitiveCompare(query) == .orderedSame
                    continuation.resume(returning: isExactMatch ? .success(with: inPerson) : .confirmationRequired(with: inPerson))
                default:
                    // Disambiguation list: drop avatars to keep CPU/memory bounded under CarPlay's
                    // tight extension budget. The single-match branch above keeps `withImage: true`.
                    let persons = discussions.compactMap { try? $0.toINPerson(withImage: false) }
                    if !persons.isEmpty {
                        Self.logger.info("💬 Multiple matches for '\(query, privacy: .private)', requesting disambiguation")
                        continuation.resume(returning: .disambiguation(with: persons))
                    } else {
                        continuation.resume(returning: .unsupported(forReason: .noHandleForLabel))
                    }
                }
            }
        } catch {
            Self.logger.fault("💬 Search failed for query '\(query, privacy: .private)': \(error)")
            return .unsupported(forReason: .noHandleForLabel)
        }
        if let result {
            return result
        }
        // No results in the 1:1 pass — retry across all discussions
        if restrictToOneToOneDiscussions {
            return await resolveBySearchQuery(query, restrictToOneToOneDiscussions: false)
        } else {
            return .unsupported(forReason: .noHandleForLabel)
        }
    }


}

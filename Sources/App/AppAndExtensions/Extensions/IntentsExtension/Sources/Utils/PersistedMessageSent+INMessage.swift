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
import ObvAppTypes
import CoreData
import ObvCommunicationInteractor
import ObvUICoreData


extension PersistedMessageSent {

    /// Returns up to 100 of the most recent outbound messages across `discussionIdentifiers`,
    /// expanded into `INMessage` values (one per content kind: text, location, image, audio, link,
    /// file). Sent messages have no "unread" state, so there is no equivalent of
    /// `restrictToNewMessages`. Optional `searchTerms` filter by case- and diacritic-insensitive
    /// body substring (all terms must match); optional `startDate`/`endDate` clamp the message
    /// `timestamp` to the inclusive range. The 100-message cap applies globally across the matched
    /// discussions, not per discussion.
    static func fetchLastSentINMessages(discussionIdentifiers: Set<ObvDiscussionIdentifier>, searchTerms: [String]? = nil, startDate: Date? = nil, endDate: Date? = nil) async throws -> [INMessage] {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<[INMessage], any Error>, context: NSManagedObjectContext) in
            // Siri-sourced identifiers may include discussions whose owned profile has since been hidden; strip them.
            let nonHiddenOwnedCryptoIds = Set(try PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: context).map(\.cryptoId))
            let filteredDiscussionIdentifiers = discussionIdentifiers.filter { nonHiddenOwnedCryptoIds.contains($0.ownedCryptoId) }
            guard !filteredDiscussionIdentifiers.isEmpty else {
                return continuation.resume(returning: [])
            }
            let persistedMessages = try PersistedMessageSent.getLastSentMessagesWithinDiscussions(
                discussionScope: .restricted(to: filteredDiscussionIdentifiers),
                searchTerms: searchTerms,
                startDate: startDate,
                endDate: endDate,
                fetchLimit: 100,
                within: context
            )
            let inMessages = persistedMessages.compactMap(\.inMessages).flatMap { $0 }
            return continuation.resume(returning: inMessages)
        }
    }

    /// Returns up to 100 of the most recent outbound messages across all non-hidden owned identities,
    /// expanded into `INMessage` values. Optional `searchTerms` filter by case- and diacritic-insensitive
    /// body substring (all terms must match); optional `startDate`/`endDate` clamp the message
    /// `timestamp` to the inclusive range. Counterpart to ``PersistedMessageReceived/fetchLastReceivedINMessages(restrictToNewMessages:searchTerms:startDate:endDate:)``.
    static func fetchLastSentINMessages(searchTerms: [String]? = nil, startDate: Date? = nil, endDate: Date? = nil) async throws -> [INMessage] {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<[INMessage], any Error>, context: NSManagedObjectContext) in
            let persistedMessages = try PersistedMessageSent.getLastSentMessagesWithinDiscussions(
                discussionScope: .any(restrictToNonHiddenProfiles: true),
                searchTerms: searchTerms,
                startDate: startDate,
                endDate: endDate,
                fetchLimit: 100,
                within: context
            )
            let inMessages = persistedMessages.compactMap(\.inMessages).flatMap { $0 }
            return continuation.resume(returning: inMessages)
        }
    }

}


extension PersistedMessageSent {

    /// Materializes this sent message as one or more `INMessage` instances — one per non-empty content
    /// kind (text, location, images, video, audio, link previews, other files). `sender` is the owned
    /// identity, `recipients` are the discussion's contacts (the one-to-one peer, or the group's other
    /// members). Returns an empty array for wiped messages and polls.
    ///
    /// This mirrors the received side: `PersistedMessageSent` now exposes `fyleMessageJoinWithStatusesOfVideoType`
    /// and its `fyleMessageJoinWithStatusesOfOtherTypes` excludes image+audio+video+preview, so videos
    /// surface to Siri as `.mediaVideo` (not `.file`) and never appear twice across buckets.
    var inMessages: [INMessage] {

        var messages: [INMessage] = []

        let groupName: INSpeakableString?

        if let persistedDiscussion = discussion, !persistedDiscussion.isOneToOne {
            groupName = INSpeakableString(spokenPhrase: persistedDiscussion.title)
        } else {
            groupName = nil
        }

        let sender = try? discussion?.ownedIdentity?.toINPerson(withImage: false)
        let recipients = try? discussion?.sentMessageRecipientsINPerson

        guard let messageAppIdentifier = try? self.messageAppIdentifier.description else {
            return messages
        }

        let conversationIdentifier = try? discussion?.discussionIdentifier.description
        let textBody = textBody
        let date = timestamp

        guard !isWiped, !isPoll else {
            return messages
        }

        // 1: Create a message with the content
        if let textBody, !textBody.isEmpty, !self.isLocationMessage {
            messages.append(
                INMessage(identifier: messageAppIdentifier,
                          conversationIdentifier: conversationIdentifier,
                          content: textBody,
                          dateSent: date,
                          sender: sender,
                          recipients: recipients,
                          groupName: groupName,
                          messageType: .text)
            )
        }

        // 2: create a message for location
        if self.isLocationMessage {
            messages.append(
                INMessage(identifier: messageAppIdentifier,
                          conversationIdentifier: conversationIdentifier,
                          content: nil,
                          dateSent: date,
                          sender: sender,
                          recipients: recipients,
                          groupName: groupName,
                          messageType: .mediaLocation)
            )
        }

        if #available(iOS 17.0, *), let attachments = fyleMessageJoinWithStatus, !attachments.isEmpty {

            // 3: photo attachments
            let photoINFiles = fyleMessageJoinWithStatusesOfImageType.compactMap(\.asINFile)
            if !photoINFiles.isEmpty {
                messages.append(
                    INMessage(identifier: messageAppIdentifier,
                              conversationIdentifier: conversationIdentifier,
                              content: nil,
                              dateSent: date,
                              sender: sender,
                              recipients: recipients,
                              groupName: groupName,
                              messageType: .mediaImage,
                              serviceName: nil,
                              attachmentFiles: photoINFiles)
                )
            }

            // 4: video attachments
            let videoINFiles = fyleMessageJoinWithStatusesOfVideoType.compactMap(\.asINFile)
            if !videoINFiles.isEmpty {
                messages.append(
                    INMessage(identifier: messageAppIdentifier,
                              conversationIdentifier: conversationIdentifier,
                              content: nil,
                              dateSent: date,
                              sender: sender,
                              recipients: recipients,
                              groupName: groupName,
                              messageType: .mediaVideo,
                              serviceName: nil,
                              attachmentFiles: videoINFiles)
                )
            }

            // 5: audio attachments
            let audioINFiles = fyleMessageJoinWithStatusesOfAudioType.compactMap(\.asINFile)
            if !audioINFiles.isEmpty {
                messages.append(
                    INMessage(identifier: messageAppIdentifier,
                              conversationIdentifier: conversationIdentifier,
                              content: nil,
                              dateSent: date,
                              sender: sender,
                              recipients: recipients,
                              groupName: groupName,
                              messageType: .audio,
                              serviceName: nil,
                              attachmentFiles: audioINFiles)
                )
            }

            // 6: link preview attachments
            let previewINFiles = fyleMessageJoinWithStatusesOfPreviewType.compactMap(\.asINFile)
            if !previewINFiles.isEmpty {
                messages.append(
                    INMessage(identifier: messageAppIdentifier,
                              conversationIdentifier: conversationIdentifier,
                              content: nil,
                              dateSent: date,
                              sender: sender,
                              recipients: recipients,
                              groupName: groupName,
                              messageType: .link,
                              serviceName: nil,
                              attachmentFiles: previewINFiles)
                )
            }

            // 7: other attachments
            let othersINFiles = fyleMessageJoinWithStatusesOfOtherTypes.compactMap(\.asINFile)
            if !othersINFiles.isEmpty {
                messages.append(
                    INMessage(identifier: messageAppIdentifier,
                              conversationIdentifier: conversationIdentifier,
                              content: nil,
                              dateSent: date,
                              sender: sender,
                              recipients: recipients,
                              groupName: groupName,
                              messageType: .file,
                              serviceName: nil,
                              attachmentFiles: othersINFiles)
                )
            }
        }

        return messages
    }

}


fileprivate extension PersistedDiscussion {

    /// Recipients to attach to an outbound `INMessage`. For a one-to-one discussion, the discussion's
    /// contact. For a group discussion, the other group members — falling back to the owned identity
    /// (`isMe`) when the group has no other member, so a note-to-self surfaces as "to <self>" rather
    /// than "to no one" and matches `recipients=[isMe]` queries from Siri. Unlike `contactsINPerson`
    /// (used on the inbound side), this returns the one-to-one contact rather than `nil`, so Siri can
    /// read back "to <contact>" for sent messages.
    var sentMessageRecipientsINPerson: [INPerson]? {
        get throws {
            switch try kind {
            case .oneToOne(withContactIdentity: let contactIdentity):
                guard let contactIdentity else { return nil }
                guard let person = try? contactIdentity.toINPerson(withImage: false) else { return nil }
                return [person]
            case .groupV1, .groupV2:
                let others = try contactsINPerson ?? []
                guard others.isEmpty else { return others }
                guard let owned = self.ownedIdentity else { return nil }
                guard let me = try? owned.toINPerson(withImage: false) else { return nil }
                return [me]
            }
        }
    }

}

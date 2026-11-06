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


extension PersistedMessageReceived {

    /// Returns up to 100 of the most recent inbound messages across `discussionIdentifiers`, expanded
    /// into `INMessage` values (one per content kind: text, location, image, video, audio, link,
    /// file). When `restrictToNewMessages` is true, only messages still in the `.new` status are
    /// returned. Optional `searchTerms` filter by case- and diacritic-insensitive body substring
    /// (all terms must match); optional `startDate`/`endDate` clamp the message `timestamp` to the
    /// inclusive range. The 100-message cap applies globally across the matched discussions, not per
    /// discussion.
    static func fetchLastReceivedINMessages(discussionIdentifiers: Set<ObvDiscussionIdentifier>, restrictToNewMessages: Bool, searchTerms: [String]? = nil, startDate: Date? = nil, endDate: Date? = nil) async throws -> [INMessage] {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<[INMessage], any Error>, context: NSManagedObjectContext) in
            // Siri-sourced identifiers may include discussions whose owned profile has since been hidden; strip them.
            let nonHiddenOwnedCryptoIds = Set(try PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: context).map(\.cryptoId))
            let filteredDiscussionIdentifiers = discussionIdentifiers.filter { nonHiddenOwnedCryptoIds.contains($0.ownedCryptoId) }
            guard !filteredDiscussionIdentifiers.isEmpty else {
                return continuation.resume(returning: [])
            }
            let persistedMessages = try PersistedMessageReceived.getLastReceivedMessagesWithinDiscussions(
                discussionScope: .restricted(to: filteredDiscussionIdentifiers),
                restrictToNewMessages: restrictToNewMessages,
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

    /// Returns up to 100 of the most recent inbound messages across all non-hidden owned identities,
    /// expanded into `INMessage` values. When `restrictToNewMessages` is true, only messages still in
    /// the `.new` status are returned. Optional `searchTerms` filter by case- and diacritic-insensitive
    /// body substring (all terms must match); optional `startDate`/`endDate` clamp the message
    /// `timestamp` to the inclusive range. Counterpart to ``PersistedMessageSent/fetchLastSentINMessages(searchTerms:startDate:endDate:)``.
    static func fetchLastReceivedINMessages(restrictToNewMessages: Bool, searchTerms: [String]? = nil, startDate: Date? = nil, endDate: Date? = nil) async throws -> [INMessage] {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<[INMessage], any Error>, context: NSManagedObjectContext) in
            let persistedMessages = try PersistedMessageReceived.getLastReceivedMessagesWithinDiscussions(
                discussionScope: .any(restrictToNonHiddenProfiles: true),
                restrictToNewMessages: restrictToNewMessages,
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

    /// Returns the `INMessage`s for the received messages identified by `messageAppIdentifiers` that
    /// exist in the app database, expanded via ``inMessages`` (text + attachments + location, with
    /// any sender-applied edit already reflected). Identifiers with no corresponding
    /// `PersistedMessageReceived` — e.g. a message not yet drained from the NSE database, or a sent
    /// message — are silently skipped; the caller resolves those elsewhere. Messages belonging to a
    /// hidden owned profile are excluded. Used by the scoped Siri path that honors
    /// `INSearchForMessagesIntent.identifiers` and `notificationIdentifiers`, so the extension returns
    /// exactly the requested messages instead of the whole backlog.
    static func fetchReceivedINMessages(messageAppIdentifiers: Set<ObvMessageAppIdentifier>) async throws -> [INMessage] {
        guard !messageAppIdentifiers.isEmpty else { return [] }
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<[INMessage], any Error>, context: NSManagedObjectContext) in
            var inMessages: [INMessage] = []
            for messageAppIdentifier in messageAppIdentifiers {
                guard let message = try PersistedMessage.getMessage(messageAppIdentifier: messageAppIdentifier, within: context) as? PersistedMessageReceived else {
                    continue
                }
                guard message.discussion?.ownedIdentity?.isHidden == false else {
                    continue
                }
                inMessages.append(contentsOf: message.inMessages)
            }
            return continuation.resume(returning: inMessages)
        }
    }

}


extension PersistedMessageReceived {

    /// Materializes this received message as one or more `INMessage` instances — one per non-empty
    /// content kind (text, location, images, videos, audio, link previews, other files). `sender` is
    /// the contact who sent it; `recipients` are the discussion's other contacts (nil for a one-to-one
    /// discussion). Returns an empty array for messages that are not spokable (wiped, polls,
    /// or ephemeral messages requiring user action).
    var inMessages: [INMessage] {
    
        var messages: [INMessage] = []
        
        let groupName: INSpeakableString?
        
        if let persistedDiscussion = discussion, !persistedDiscussion.isOneToOne  {
            groupName = INSpeakableString(spokenPhrase: persistedDiscussion.title)
        } else {
            groupName = nil
        }
        
        let sender = try? contactIdentity?.toINPerson(withImage: false)
        let recipients = try? discussion?.contactsINPerson
        
        guard let messageAppIdentifier = try? self.messageAppIdentifier.description else {
            return messages
        }
        
        let conversationIdentifier = try? discussion?.discussionIdentifier.description
        let textBody = textBody
        let date = timestamp
        
        guard isSpokable else {
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
            
            //3: create a message for all photo attachments
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
            
            //4: create a message for all video attachments
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
            
            //5: create a message for all audio attachments
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
            
            //6: create a message for all link preview attachments
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
            
            //7: create a message for all other attachments
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

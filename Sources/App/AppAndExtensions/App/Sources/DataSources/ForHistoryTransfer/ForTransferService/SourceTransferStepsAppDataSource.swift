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
import ObvHistoryTransfer
import ObvTypes
import ObvAppTypes
import ObvUICoreData
import ObvSettings


/// This data source is not part of all the centralized data sources as its purpose is not to feed an UI, but to provide all the data required during a message history transfer.
final class SourceTransferStepsAppDataSource {
    
    private let backgroundContext: NSManagedObjectContext
    private let safeAttachmentURLProvider: SafeAttachmentURLProvider
    private let historyTransferDataSourceHelper: HistoryTransferDataSourceHelper
    
    init(backgroundContext: NSManagedObjectContext) {
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.backgroundContext = backgroundContext
        self.safeAttachmentURLProvider = .init(temporaryDirectory: ObvUICoreDataConstants.ContainerURL.forTempFiles.url, backgroundContext: backgroundContext)
        self.historyTransferDataSourceHelper = .init(backgroundContext: backgroundContext)
    }
    
}


// MARK: - Implementing SourceTransferStepsDataSource

extension SourceTransferStepsAppDataSource: SourceTransferStepsDataSource {
    
    /// Called by the source device at the beginning of the history transfer process. We should return all the discussion identifiers (excluding pre-discussions) for the given owned identity.
    func historyTransferRequiresAllDiscussionIdentifiers(_ actor: ObvHistoryTransfer.SourceTransferSteps, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> [ObvAppTypes.ObvDiscussionIdentifier] {
        return try await self.historyTransferDataSourceHelper.getAllDiscussionIdentifiers(ownedCryptoId: ownedCryptoId)
    }
    
    /// Called by the source device at the beginning of the history transfer process. We should return a dictionary where keys are the sha256 of attachments sent or received by the owned identity, and values are their (byte) length.
    ///
    /// ## For received attachments
    /// We restrict to downloaded (thus available) attachments. The file must be fully available on disk.
    func historyTransferRequiresAllHashAndSizesOfFyles(_ actor: ObvHistoryTransfer.SourceTransferSteps, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> [Data : UInt64] {
        return try await historyTransferDataSourceHelper.getAllHashAndSizesOfFyles(ownedCryptoId: ownedCryptoId)
    }
    
    func historyTransferRequiresTitleAndAllMessageIdentifiersOfDiscussion(_ actor: SourceTransferSteps, discussionIdentifier: ObvDiscussionIdentifier) async throws -> (discussionTitle: String, messageIdentifiers: [ObvMessageAppIdentifier]) {
        return try await historyTransferDataSourceHelper.getTitleAndAllMessageIdentifiersOfDiscussion(discussionIdentifier: discussionIdentifier)
    }
    
    
    func historyTransferRequiresMessages(_ actor: ObvHistoryTransfer.SourceTransferSteps, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, messageIdentifiers: [ObvAppTypes.ObvMessageAppIdentifier]) async throws -> ObvHistoryTransfer.SourceTransferSteps.MessagesToSend {
        return try await historyTransferRequiresMessages(discussionIdentifier: discussionIdentifier, messageIdentifiers: messageIdentifiers)
    }
    
    
    func historyTransferRequiresSafeAttachmentURL(_ actor: SourceTransferSteps, sha256: Data) async throws -> URL {
        return try await self.safeAttachmentURLProvider.createSafeAttachmentURL(sha256: sha256)
    }
    
    func historyTransferNoLongerRequiresSafeAttachmentURL(_ actor: SourceTransferSteps, sha256: Data, url: URL) async throws {
        try await self.safeAttachmentURLProvider.deleteSafeAttachmentURL(sha256: sha256, safeFileURL: url)
    }

}


// MARK: - Errors

extension SourceTransferStepsAppDataSource {
    
    enum ObvError: Error {
        case couldNotFindDiscussion
        case unexpectedMessageKind
        case shouldNotTransferSensitiveMessage
        case attachmentError
        case messageNotFound
    }
    
}


// MARK: - Private helpers

extension SourceTransferStepsAppDataSource {
    
    
    private func historyTransferRequiresMessages(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, messageIdentifiers: [ObvAppTypes.ObvMessageAppIdentifier]) async throws -> ObvHistoryTransfer.SourceTransferSteps.MessagesToSend {
        let backgroundContext = self.backgroundContext
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ObvHistoryTransfer.SourceTransferSteps.MessagesToSend, any Error>) in
            backgroundContext.perform {
                do {
                    guard try PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: backgroundContext) != nil else {
                        return continuation.resume(returning: .discussionNotFound)
                    }
                    var found = [JsonMessageInThread]()
                    var notFound = [ObvMessageAppIdentifier]()
                    for messageIdentifier in messageIdentifiers {
                        do {
                            guard let message = try PersistedMessage.getMessage(
                                messageAppIdentifier: messageIdentifier,
                                within: backgroundContext) else {
                                throw ObvError.messageNotFound
                            }
                            let msg = try JsonMessageInThread(message: message)
                            found.append(msg)
                        } catch {
                            notFound.append(messageIdentifier)
                        }
                    }
                    let valueToReturn: SourceTransferSteps.MessagesToSend = .messages(found: found, notFound: notFound)
                    return continuation.resume(returning: valueToReturn)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
}


// MARK: - Private helper for safe attachments URL

extension SourceTransferStepsAppDataSource {
    
    private actor SafeAttachmentURLProvider {
        
        private let temporaryDirectory: URL
        private let backgroundContext: NSManagedObjectContext
        
        init(temporaryDirectory: URL, backgroundContext: NSManagedObjectContext) {
            self.temporaryDirectory = temporaryDirectory.appending(path: "ObvSafeAttachmentsForHistoryTransfer", directoryHint: .isDirectory)
            self.backgroundContext = backgroundContext
            try? FileManager.default.removeItem(at: self.temporaryDirectory)
        }
        
        func createSafeAttachmentURL(sha256: Data) async throws -> URL {
            let backgroundContext = self.backgroundContext
            let safeFileURL: URL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, any Error>) in
                backgroundContext.perform {
                    do {
                        guard let fyle = try Fyle.get(sha256: sha256, within: backgroundContext) else { throw ObvError.fyleNotFound }
                        let originalFileURL = fyle.url
                        guard FileManager.default.isReadableFile(atPath: originalFileURL.path) else { throw ObvError.fileIsNotReadable }
                        // The original file can be read. We create a hard link to this file in a temporary directory.
                        let safeAttachmentDirectoryURL = try Self.createSafeAttachmentDirectoryURL(sha256: sha256, temporaryDirectory: self.temporaryDirectory)
                        let safeFileURL = safeAttachmentDirectoryURL.appending(path: UUID().uuidString)
                        try FileManager.default.linkItem(at: originalFileURL, to: safeFileURL)
                        return continuation.resume(returning: safeFileURL)
                    } catch {
                        assertionFailure()
                        return continuation.resume(throwing: error)
                    }
                }
            }
            return safeFileURL
        }
        
        
        func deleteSafeAttachmentURL(sha256: Data, safeFileURL: URL) async throws {
            let safeAttachmentDirectoryURL = try Self.createSafeAttachmentDirectoryURL(sha256: sha256, temporaryDirectory: self.temporaryDirectory)
            guard safeAttachmentDirectoryURL == safeFileURL.deletingLastPathComponent() else { assertionFailure(); throw ObvError.unexpectedSafeFileURL }
            if FileManager.default.isReadableFile(atPath: safeFileURL.path) {
                try FileManager.default.removeItem(at: safeFileURL)
            }
            // We don't check whether the directory is empty
            if FileManager.default.isReadableFile(atPath: safeAttachmentDirectoryURL.path) {
                try FileManager.default.removeItem(at: safeAttachmentDirectoryURL)
            }
        }

        
        private static func createSafeAttachmentDirectoryURL(sha256: Data, temporaryDirectory: URL) throws -> URL {
            let safeAttachmentDirectoryURL = temporaryDirectory
                .appending(path: sha256.hexString(), directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: safeAttachmentDirectoryURL, withIntermediateDirectories: true)
            return safeAttachmentDirectoryURL
        }
            
        enum ObvError: Error {
            case fyleNotFound
            case fileIsNotReadable
            case unexpectedSafeFileURL
        }
        
    }
    
}


// MARK: - Private helpers

private extension ObvHistoryTransfer.JsonMessageInThread {
    
    init(message: PersistedMessage) throws {
        
        guard !message.readOnce && message.visibilityDuration == nil else {
            assertionFailure()
            throw SourceTransferStepsAppDataSource.ObvError.shouldNotTransferSensitiveMessage
        }
        
        let kind: JsonMessageInThread.Kind
        let replyTo: MessageReferenceJSON?
        let expirationLimitedExistence: TimeInterval?
        let location: LocationJSON?
        let messageIdentifierFromEngine: JsonMessageInThread.UidFromServer
        switch message.kind {
        case .sent:
            guard let sentMessage = message as? PersistedMessageSent else {
                assertionFailure()
                throw SourceTransferStepsAppDataSource.ObvError.unexpectedMessageKind
            }
            kind = .sent(status: .init(status: sentMessage.status))
            if let _messageIdentifierFromEngine = sentMessage.messageIdentifierFromEngine {
                messageIdentifierFromEngine = .known(_messageIdentifierFromEngine)
            } else {
                messageIdentifierFromEngine = .unknown
            }
            replyTo = sentMessage.messageRepliedTo?.toMessageReferenceJSON()
            expirationLimitedExistence = sentMessage.initialExistenceDuration
            location = try sentMessage.locationContinuousSent?.toLocationJSON() ?? sentMessage.locationOneShotSent?.toLocationJSON()
        case .received:
            guard let receivedMessage = message as? PersistedMessageReceived else {
                assertionFailure()
                throw SourceTransferStepsAppDataSource.ObvError.unexpectedMessageKind
            }
            messageIdentifierFromEngine = .known(receivedMessage.messageIdentifierFromEngine)
            kind = .received
            replyTo = receivedMessage.messageRepliedTo?.toMessageReferenceJSON()
            expirationLimitedExistence = receivedMessage.initialExistenceDuration
            location = try receivedMessage.locationContinuousReceived?.toLocationJSON() ?? receivedMessage.locationOneShotReceived?.toLocationJSON()
        case .system, .none:
            assertionFailure()
            throw SourceTransferStepsAppDataSource.ObvError.unexpectedMessageKind
        }
        
        let pollVotes: [JsonPollVoteForMessage]
        if let poll = message.poll {
            pollVotes = poll.candidates.flatMap { candidate in
                return candidate.votes.compactMap { .init(vote: $0) }
            }
        } else {
            pollVotes = []
        }
        
        let bodyAndMentionsToSend: StringAndUserMentions?
        if let textBodyToSend = message.textBodyToSend {
            let mentions = message.mentions.compactMap({ try? $0.userMention })
            bodyAndMentionsToSend = .init(body: textBodyToSend, mentions: mentions)
        } else {
            bodyAndMentionsToSend = nil
        }

        self.init(senderSequenceNumber: message.senderSequenceNumber,
                  timestamp: message.timestamp,
                  messageIdentifierFromEngine: messageIdentifierFromEngine,
                  kind: kind,
                  bodyAndMentions: bodyAndMentionsToSend,
                  replyTo: replyTo,
                  expirationLimitedExistence: expirationLimitedExistence,
                  forwarded: message.forwarded,
                  edited: message.isEdited,
                  location: location,
                  poll: try message.poll?.toPollJSON(),
                  reactions: message.reactions.compactMap({ .init(reaction: $0) }),
                  pollVotes: pollVotes,
                  attachments: try message.fyleMessageJoinWithStatus?.map{ try .init(join: $0) } ?? [])

    }
    
}


private extension ObvHistoryTransfer.JsonMessageInThread.Kind.SentMessageStatus {
    
    init(status: PersistedMessageSent.MessageStatus) {
        switch status {
        case .sentFromAnotherOwnedDevice: self = .sentFromAnotherOwnedDevice
        case .hasNoRecipient: self = .sentFromAnotherOwnedDevice
        case .couldNotBeSentToOneOrMoreRecipients: self = .couldNotBeSentToOneOrMoreRecipients
        case .fullyDeliveredAndFullyRead: self = .fullyDeliveredAndFullyRead
        case .fullyDeliveredAndPartiallyRead: self = .fullyDeliveredAndPartiallyRead
        case .fullyDeliveredAndNotRead: self = .fullyDeliveredAndNotRead
        case .partiallyDeliveredAndPartiallyRead: self = .partiallyDeliveredAndPartiallyRead
        case .partiallyDeliveredNotRead: self = .partiallyDeliveredNotRead
        case .sent: self = .sent
        case .processing: self = .sentFromAnotherOwnedDevice
        case .unprocessed: self = .sentFromAnotherOwnedDevice
        }
    }
    
}


private extension ObvHistoryTransfer.JsonReactionToMessage {
    
    init?(reaction: PersistedMessageReaction) {
        guard let emoji = reaction.emoji else { return nil }
        let sender: ObvCryptoId
        if let reactionSent = reaction as? PersistedMessageReactionSent {
            guard let ownedCryptoId = try? reactionSent.message?.messageAppIdentifier.ownedCryptoId else {
                return nil
            }
            sender = ownedCryptoId
        } else if let reactionReceived = reaction as? PersistedMessageReactionReceived {
            guard let contactCryptoId = reactionReceived.contact?.cryptoId else {
                return nil
            }
            sender = contactCryptoId
        } else {
            return nil
        }
        
        self.init(emoji: emoji,
                  sender: sender,
                  timestamp: reaction.timestamp)
    }
    
}


private extension ObvHistoryTransfer.JsonPollVoteForMessage {
    
    init?(vote: PersistedPollVote) {
        
        guard let candidate = vote.candidate?.uuid else { return nil }
        let sender: ObvCryptoId
        if let voteSent = vote as? PersistedPollVoteSent {
            guard let ownedCryptoId = try? voteSent.candidate?.poll?.message?.messageAppIdentifier.ownedCryptoId else {
                return nil
            }
            sender = ownedCryptoId
        } else if let voteReceived = vote as? PersistedPollVoteReceived {
            guard let contactCryptoId = voteReceived.contact?.cryptoId else {
                return nil
            }
            sender = contactCryptoId
        } else {
            return nil
        }
        
        self.init(candidate: candidate,
                  voted: vote.voted,
                  version: vote.version,
                  sender: sender,
                  timestamp: vote.timestamp)
        
    }
    
}


private extension ObvHistoryTransfer.JsonAttachment {
    
    init(join: FyleMessageJoinWithStatus) throws {
        
        guard let message = join.message,
              let fyleMessageJoinWithStatus = message.fyleMessageJoinWithStatus,
              let number: Int = fyleMessageJoinWithStatus.firstIndex(of: join) else {
            assertionFailure()
            throw SourceTransferStepsAppDataSource.ObvError.attachmentError
        }
        
        guard let fyle = join.fyle else {
            assertionFailure()
            throw SourceTransferStepsAppDataSource.ObvError.attachmentError
        }
        
        self.init(sha256: fyle.sha256,
                  number: number,
                  size: Int(join.totalByteCount),
                  mimeType: join.contentType.preferredMIMEType ?? "application/octet-stream",
                  filename: join.fileName)
        
    }
    
}

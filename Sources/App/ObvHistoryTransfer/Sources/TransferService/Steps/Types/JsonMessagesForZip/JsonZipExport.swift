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
import ObvTypes
import ObvAppTypes


struct JsonZipExport {
    
    let ownedCryptoId: ObvCryptoId
    let sha256s: [Data: UInt64] // each key is a sha256, the corresponding value is the length of the file

    /// This saves the title for discussions, which is only useful when restoring for locked discussions that do not exist yet on the target device
    let discussions: [JsonZipDiscussion]

    /// This field is not actually used when importing a zip history transfer, it is only used for the discussion/profile HTML export
    /// It also contains an entry for the ownedCryptoId.
    let contacts: [JsonZipContact]
    
    let messages: [JsonZipMessages]
    
    static let discussionAndMessagesJsonFileName = "discussions_and_messages.json"
    static let attachmentsDirectoryName = "files"
    
    init(ownedCryptoId: ObvCryptoId) {
        self.ownedCryptoId = ownedCryptoId
        self.sha256s = [:]
        self.discussions = []
        self.contacts = []
        self.messages = []
    }
    
    private init(ownedCryptoId: ObvCryptoId,
                 sha256s: [Data : UInt64],
                 discussions: [JsonZipDiscussion],
                 contacts: [JsonZipContact],
                 messages: [JsonZipMessages]) {
        self.ownedCryptoId = ownedCryptoId
        self.sha256s = sha256s
        self.discussions = discussions
        self.contacts = contacts
        self.messages = messages
    }
    
}


// MARK: - Implementing Codable

extension JsonZipExport: Codable {
    
    private enum CodingKeys: String, CodingKey {
        case ownedCryptoId = "bytesOwnedIdentity"
        case sha256s = "sha256s"
        case discussions = "discussions"
        case contacts = "contacts"
        case messages = "messages"
    }

    
    public func encode(to encoder: Encoder) throws {
        
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(ownedCryptoId, forKey: .ownedCryptoId)
        
        let dict: [String: UInt64] = .init(sha256s, keyMapping: { $0.base64EncodedString() }, valueMapping: { $0 })
        try container.encode(dict, forKey: .sha256s)

        try container.encode(discussions, forKey: .discussions)
        try container.encode(contacts, forKey: .contacts)
        try container.encode(messages, forKey: .messages)

    }
    
    public init(from decoder: Decoder) throws {
        do {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            do {
                
                self.ownedCryptoId = try values.decode(ObvCryptoId.self, forKey: .ownedCryptoId)
                
                let dict: [String: UInt64] = try values.decode([String: UInt64].self, forKey: .sha256s)
                self.sha256s = Dictionary(dict, keyMapping: { $0.base64EncodedToData }, valueMapping: { $0 })
                
                self.discussions = try values.decode([JsonZipDiscussion].self, forKey: .discussions)
                self.contacts = try values.decode([JsonZipContact].self, forKey: .contacts)
                self.messages = try values.decode([JsonZipMessages].self, forKey: .messages)

            }
        } catch {
            assertionFailure()
            throw error
        }
    }

}


// MARK: - Progressively constructing JsonZipExport

extension JsonZipExport {
    
    func addingDiscussions(_ srcDiscussionRanges: SrcDiscussionRanges) -> Self {
        let discussionToAdd = JsonZipDiscussion(srcDiscussionRanges: srcDiscussionRanges)
        var newDiscussions = self.discussions
        newDiscussions.append(discussionToAdd)
        return .init(ownedCryptoId: self.ownedCryptoId,
                     sha256s: self.sha256s,
                     discussions: newDiscussions,
                     contacts: self.contacts,
                     messages: self.messages)
    }
    
    
    func addMessages(_ srcMessages: SrcMessages) -> Self {
        let messagesToAdd = JsonZipMessages(srcMessages: srcMessages)
        var newMessages = self.messages
        newMessages.append(messagesToAdd)
        return .init(ownedCryptoId: self.ownedCryptoId,
                     sha256s: self.sha256s,
                     discussions: self.discussions,
                     contacts: self.contacts,
                     messages: newMessages)
    }
    
    func addingSha256(_ sha256: Data, fileSize: UInt64) -> Self {
        var newSha256s = self.sha256s
        assert(newSha256s[sha256] == nil)
        newSha256s[sha256] = fileSize
        return .init(ownedCryptoId: self.ownedCryptoId,
                     sha256s: newSha256s,
                     discussions: self.discussions,
                     contacts: self.contacts,
                     messages: self.messages)
    }
    
    func settingContacts(newContacts: [JsonZipContact]) -> Self {
        return .init(ownedCryptoId: self.ownedCryptoId,
                     sha256s: self.sha256s,
                     discussions: self.discussions,
                     contacts: newContacts,
                     messages: self.messages)
    }
    
}


// MARK: - Helpers used on destination device

extension JsonZipExport {
    
    var srcDiscussionList: SrcDiscussionList {
        get throws {
            
            let discussionIdentifiers: [ObvDiscussionIdentifier] = try self.discussions
                .map(\.discussionIdentifier)
                .map { try $0.getDiscussionIdentifier(ownedCryptoId: self.ownedCryptoId) }
            
            return .init(discussionIdentifiers: discussionIdentifiers,
                         sha256Map: self.sha256s)
            
        }
    }
    
    
    /// Called on the destination device after unzipping the zip file. Returns a stream of `SrcDiscussionRanges`, one per discussion identifier found in `expectedDiscussionIdentifiers`.
    func getStreamOfSrcDiscussionRanges(ownedCryptoId: ObvCryptoId, expectedDiscussionIdentifiers: [JsonDiscussionIdentifier]) -> AsyncThrowingStream<SrcDiscussionRanges, any Error> {

        let messagesToKeep: [JsonZipMessages] = self.messages.filter({ expectedDiscussionIdentifiers.contains($0.discussionIdentifier) })
        let messagesToKeepForEachDiscussion: [JsonDiscussionIdentifier: [JsonZipMessages]] = Dictionary(grouping: messagesToKeep, by: \.discussionIdentifier)

        let stream = AsyncThrowingStream<SrcDiscussionRanges, any Error> { (continuation: AsyncThrowingStream<SrcDiscussionRanges, any Error>.Continuation) in
            
            for (discussionIdentifier, messagesInDiscussion) in messagesToKeepForEachDiscussion {
                
                do {
                    
                    let discussionTitle: String = self.discussions.first(where: { $0.discussionIdentifier == discussionIdentifier })?.discussionTitle ?? ""
                    let obvDiscussionIdentifier: ObvDiscussionIdentifier = try discussionIdentifier.getDiscussionIdentifier(ownedCryptoId: ownedCryptoId)
                    let obvMessageAppIdentifier: [ObvMessageAppIdentifier] = try messagesInDiscussion.toListOfObvMessagesIdentifiers(ownedCryptoId: ownedCryptoId)
                    
                    let srcDiscussionRanges = try SrcDiscussionRanges(
                        discussionTitle: discussionTitle,
                        discussionIdentifier: obvDiscussionIdentifier,
                        messageIdentifiers: obvMessageAppIdentifier)
                    
                    continuation.yield(srcDiscussionRanges)
                    
                } catch {
                    assertionFailure()
                    return continuation.finish(throwing: error)
                }
                
            }

            return continuation.finish()
            
        }
        return stream
    }
    
    
    func getStreamOfSrcMessages(numberOfExpectedMessages: Int, dstDiscussionExpectedRangesForDiscussion: [JsonDiscussionIdentifier : DstDiscussionExpectedRanges]) -> AsyncThrowingStream<SrcMessages, any Error> {
        
        // The numberOfExpectedMessages is equal to the right-hand side iff this destination device
        // has no messages. In general, this number cannot be larger than the number of available messages in
        // the zip.
        assert(numberOfExpectedMessages <= self.messages.reduce(0, { $0 + $1.messages.count }))
        
        let stream = AsyncThrowingStream<SrcMessages, any Error> { (continuation: AsyncThrowingStream<SrcMessages, any Error>.Continuation) in
            for message in self.messages {
                guard let srcMessages: SrcMessages = message.toSrcMessages(dstDiscussionExpectedRangesForDiscussion: dstDiscussionExpectedRangesForDiscussion) else {
                    continue
                }
                continuation.yield(srcMessages)
            }
            continuation.finish()
        }
        
        return stream
        
    }
    
}

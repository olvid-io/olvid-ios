/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvUICoreDataStructs


// MARK: - Thread safe structure

extension PersistedMessage {
    
    public func toAbstractStructure() throws -> PersistedMessageAbstractStructure {
        guard let discussion else {
            throw ObvUICoreDataError.discussionIsNil
        }
        let discussionKind = try discussion.toStructureKind()
        let repliedToMessage = try messageRepliedTo?.toRepliedToMessageStructure()
        let isPersistedMessageSent = self is PersistedMessageSent
        
        let locationStructure: PersistedLocationStructure?
        if let messageSent = self as? PersistedMessageSent {
            locationStructure = try? (messageSent.locationContinuousSent ?? messageSent.locationOneShotSent)?.toStructure()
        } else if let messageReceived = self as? PersistedMessageReceived {
            locationStructure = try? (messageReceived.locationContinuousReceived ?? messageReceived.locationOneShotReceived)?.toStructure()
        } else if self.isLocationMessage {
            locationStructure = PersistedLocationStructure(type: LocationJSON.LocationSharingType.END_SHARING.rawValue, address: nil)
        } else {
            locationStructure = nil
        }
        
        return .init(senderSequenceNumber: self.senderSequenceNumber,
                     repliedToMessage: repliedToMessage,
                     readOnce: self.readOnce,
                     visibilityDuration: self.visibilityDuration,
                     existenceDuration: (self as? PersistedMessageSent)?.existenceDuration ?? self.initialExistenceDuration,
                     forwarded: self.forwarded,
                     timestamp: self.timestamp,
                     isPersistedMessageSent: isPersistedMessageSent,
                     mentions: mentions.compactMap({ try? $0.toStructure() }),
                     discussionKind: discussionKind,
                     location: locationStructure)
    }
    
    
    public func toRepliedToMessageStructure() throws -> RepliedToMessageStructure {
        guard let ownedCryptoId = discussion?.ownedIdentity?.cryptoId else {
            assertionFailure()
            throw ObvUICoreDataError.ownedIdentityIsNil
        }
        let doesMentionOwnedIdentity = try self.mentions.map({ try $0.mentionnedCryptoId }).contains(ownedCryptoId)
        let isPersistedMessageSent = self is PersistedMessageSent
        return .init(doesMentionOwnedIdentity: doesMentionOwnedIdentity, isPersistedMessageSent: isPersistedMessageSent)
    }
    
}


// MARK: - Thread safe struct

extension PersistedMessageReceived {
    
    public func toStructure() throws -> PersistedMessageReceivedStructure {
        guard let contact = self.contactIdentity else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotExtractRequiredRelationships
        }
        let abstractStructure = try toAbstractStructure()
        return .init(textBody: self.textBody,
                     messageIdentifierFromEngine: self.messageIdentifierFromEngine,
                     contact: try contact.toStructure(),
                     attachmentsCount: fyleMessageJoinWithStatuses.count,
                     attachementImages: fyleMessageJoinWithStatuses.compactMap { $0.obvAttachmentImage() },
                     abstractStructure: abstractStructure,
                     senderThreadIdentifier: self.senderThreadIdentifier,
                     senderSequenceNumber: self.senderSequenceNumber)
    }

}


// MARK: - Thread safe struct

extension PersistedMessageSent {
    
    public func toStructure() throws -> PersistedMessageSentStructure {
        let abstractStructure = try toAbstractStructure()
        return .init(textBody: self.textBody,
                     senderThreadIdentifier: self.senderThreadIdentifier,
                     isEphemeralMessageWithLimitedVisibility: self.isEphemeralMessageWithLimitedVisibility,
                     abstractStructure: abstractStructure)
    }

}

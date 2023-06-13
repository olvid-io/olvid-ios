/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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


// MARK: - Thread safe struct

extension PersistedDiscussionLocalConfiguration {

    public struct Structure {

        public let notificationSound: NotificationSound?
        public let performInteractionDonation: Bool?

        // add doc; discussion setting
        private let _muteNotificationsEndDate: Date?

        private let _mentionNotificationMode: DiscussionMentionNotificationMode

        private let _ownedCryptoId: ObvCryptoId?

        
        private var hasValidMuteNotificationsEndDate: Bool {
            guard let muteNotificationsEndDate = _muteNotificationsEndDate else { return false }
            return muteNotificationsEndDate > Date()
        }

        
        fileprivate init(notificationSound: NotificationSound? = nil, performInteractionDonation: Bool? = nil, muteNotificationsEndDate: Date?, mentionNotificationMode: DiscussionMentionNotificationMode, ownedCryptoId: ObvCryptoId?) {
            self.notificationSound = notificationSound
            self.performInteractionDonation = performInteractionDonation
            self._muteNotificationsEndDate = muteNotificationsEndDate
            self._mentionNotificationMode = mentionNotificationMode
            self._ownedCryptoId = ownedCryptoId
        }


        public func shouldMuteNotification(with message: MessageJSON?, messageRepliedToStructure: PersistedMessage.AbstractStructure?, globalDiscussionNotificationOptions options: ObvMessengerSettings.Discussions.NotificationOptions) -> Bool {
            let mentions: [ObvCryptoId]

            if let message {
                mentions = message
                    .userMentions
                    .map(\.mentionedCryptoId)
            } else {
                mentions = []
            }

            return shouldMuteNotification(mentions, messageRepliedToStructure: messageRepliedToStructure, globalDiscussionNotificationOptions: options)
        }

        
        public func shouldMuteNotification(with mentions: [PersistedUserMention.Structure], messageRepliedToStructure: PersistedMessage.AbstractStructure?, globalDiscussionNotificationOptions options: ObvMessengerSettings.Discussions.NotificationOptions) -> Bool {
            return shouldMuteNotification(mentions.map(\.mentionedCryptoId), messageRepliedToStructure: messageRepliedToStructure, globalDiscussionNotificationOptions: options)
        }

        
        private func shouldMuteNotification(_ mentions: [ObvCryptoId], messageRepliedToStructure: PersistedMessage.AbstractStructure?, globalDiscussionNotificationOptions options: ObvMessengerSettings.Discussions.NotificationOptions) -> Bool {

            guard hasValidMuteNotificationsEndDate else {
                return false
            }

            switch _mentionNotificationMode {
            case .alwaysNotifyWhenMentionned,
                    .globalDefault where options.contains(.alwaysNotifyWhenMentionnedEvenInMutedDiscussion):
                
                guard let _ownedCryptoId else {
                    assertionFailure("discussion doesn't have our owned identity associated, returning default value")
                    return true
                }

                let messageMentionsContainOwnedIdentity = mentions.contains(_ownedCryptoId)
                let messageDoesReplyToMessageThatMentionsOwnedIdentity = messageRepliedToStructure?.doesMentionOwnedIdentity ?? false
                let messageDoesReplyToSentMessage = messageRepliedToStructure?.isPersistedMessageSent ?? false

                return !PersistedMessage.computeDoesMentionOwnedIdentityValue(
                    messageMentionsContainOwnedIdentity: messageMentionsContainOwnedIdentity,
                    messageDoesReplyToMessageThatMentionsOwnedIdentity: messageDoesReplyToMessageThatMentionsOwnedIdentity,
                    messageDoesReplyToSentMessage: messageDoesReplyToSentMessage)
                
            case .neverNotifyWhenDiscussionIsMuted,
                    .globalDefault:
                
                return true
            }

        }
    }

    
    public func toStruct() -> Structure {
        return .init(notificationSound: notificationSound,
                     performInteractionDonation: performInteractionDonation,
                     muteNotificationsEndDate: muteNotificationsEndDate,
                     mentionNotificationMode: mentionNotificationMode,
                     ownedCryptoId: discussion?.ownedIdentity?.cryptoId)
    }
}

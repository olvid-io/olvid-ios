/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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


public extension PersistedMessage {
    
    /// This is typically used to obtain the appropriate text and style for a message in order to show in its discussion cell in the list of recent discussions.
    var subtitle: SubtitleConfiguration {
        if isLocallyWiped {
            return SubtitleConfiguration(text: PersistedMessage.Strings.messageWasWiped, italics: true)
        } else if isRemoteWiped {
            return SubtitleConfiguration(text: PersistedMessage.Strings.lastMessageWasRemotelyWiped, italics: true)
        } else if self is PersistedMessageSystem {
            return SubtitleConfiguration(text: textBody ?? "", italics: true)
        } else if !readOnce && initialExistenceDuration == nil && visibilityDuration == nil {
            
            // If the subtitle is empty, there might be attachments
            if let fyleMessageJoinWithStatus = fyleMessageJoinWithStatus, (textBody ?? "").isEmpty, fyleMessageJoinWithStatus.count > 0 {
                return SubtitleConfiguration(text: PersistedMessage.Strings.countAttachments(fyleMessageJoinWithStatus.count), italics: true)
            } else {
                return SubtitleConfiguration(text: textBody ?? "", italics: false)
            }
        } else {
            // Message with ephemerality, we should be careful
            if let sentMessage = self as? PersistedMessageSent {
                assert(!sentMessage.isWiped)
                // If the subtitle is empty, there might be attachments
                if let fyleMessageJoinWithStatus = sentMessage.fyleMessageJoinWithStatus, (sentMessage.textBody ?? "").isEmpty, fyleMessageJoinWithStatus.count > 0 {
                    return SubtitleConfiguration(text: PersistedMessage.Strings.countAttachments(fyleMessageJoinWithStatus.count), italics: true)
                } else {
                    return SubtitleConfiguration(text: sentMessage.textBody ?? "", italics: false)
                }
            } else if let receivedMessage = self as? PersistedMessageReceived {
                if readOnce || visibilityDuration != nil {
                    // Ephemeral received message with readOnce or limited visibility
                    switch receivedMessage.status {
                    case .new, .unread:
                        return SubtitleConfiguration(text: PersistedMessage.Strings.unreadEphemeralMessage, italics: true)
                    case .read:
                        assert(!isWiped)
                        // If the subtitle is empty, there might be attachments
                        if let fyleMessageJoinWithStatus = fyleMessageJoinWithStatus, (textBody ?? "").isEmpty, fyleMessageJoinWithStatus.count > 0 {
                            return SubtitleConfiguration(text: PersistedMessage.Strings.countAttachments(fyleMessageJoinWithStatus.count), italics: true)
                        } else {
                            return SubtitleConfiguration(text: textBody ?? "", italics: false)
                        }
                    }
                } else {
                    // Ephemeral received message with limited existence only
                    assert(!isWiped)
                    // If the subtitle is empty, there might be attachments
                    if let fyleMessageJoinWithStatus = fyleMessageJoinWithStatus, (textBody ?? "").isEmpty, fyleMessageJoinWithStatus.count > 0 {
                        return SubtitleConfiguration(text: PersistedMessage.Strings.countAttachments(fyleMessageJoinWithStatus.count), italics: true)
                    } else {
                        return SubtitleConfiguration(text: textBody ?? "", italics: false)
                    }
                }
            } else {
                assertionFailure()
                return SubtitleConfiguration(text: "", italics: false)
            }
        }
    }
}

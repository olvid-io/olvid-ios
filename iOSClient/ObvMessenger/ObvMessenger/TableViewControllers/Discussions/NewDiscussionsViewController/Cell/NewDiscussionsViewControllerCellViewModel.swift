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
import CoreData
import ObvUICoreData
import UI_ObvCircledInitials
import ObvSettings
import ObvDesignSystem


@available(iOS 16.0, *)
extension NewDiscussionsViewController.Cell {
    
    struct ViewModel {
        let numberOfNewReceivedMessages: Int
        let circledInitialsConfig: CircledInitialsConfiguration?
        let shouldMuteNotifications: Bool
        let isArchived: Bool
        let title: String
        let subtitle: AttributedString
        let timestampOfLastMessage: String
        let pinnedIndex: Int?
        let style: IdentityColorStyle
        let aNewReceivedMessageDoesMentionOwnedIdentity: Bool
        
        var isPinned: Bool {
            return pinnedIndex != nil
        }
    }
    
}


@available(iOS 16.0, *)
extension NewDiscussionsViewController.Cell.ViewModel {
    
    static func createFromPersistedDiscussion(with discussionId: TypeSafeManagedObjectID<PersistedDiscussion>, within viewContext: NSManagedObjectContext) -> Self? {
        guard let discussion = try? PersistedDiscussion.get(objectID: discussionId.objectID, within: viewContext) else { assertionFailure(); return nil }
        
        var subtitle: AttributedString
        if let illustrativeMessage = discussion.illustrativeMessage {
            subtitle = illustrativeMessage.subtitle
        } else {
            subtitle = AttributedString(localized: "NO_MESSAGE")
            subtitle.font = .italic(forTextStyle: .subheadline)
        }
        
        return Self.init(numberOfNewReceivedMessages: discussion.numberOfNewMessages,
                         circledInitialsConfig: discussion.circledInitialsConfiguration,
                         shouldMuteNotifications: discussion.hasNotificationsMuted,
                         isArchived: discussion.isArchived,
                         title: discussion.title,
                         subtitle: subtitle,
                         timestampOfLastMessage: discussion.timestampOfLastMessage.discussionCellFormat,
                         pinnedIndex: discussion.pinnedIndex,
                         style: ObvMessengerSettings.Interface.identityColorStyle,
                         aNewReceivedMessageDoesMentionOwnedIdentity: discussion.aNewReceivedMessageDoesMentionOwnedIdentity)
    }
    
}


// MARK: Computing a cell subtitle from a PersistedMessage

private extension PersistedMessage {
    
    /// This is typically used to obtain the appropriate text and style for a message in order to show in the list of recent discussions.
    var subtitle: AttributedString {

        let text: AttributedString
        let isSystemMessage: Bool

        if isLocallyWiped {
            
            text = AttributedString(PersistedMessage.Strings.messageWasWiped)
            isSystemMessage = true
            
        } else if isRemoteWiped {
            
            text = AttributedString(PersistedMessage.Strings.messageWasWiped)
            isSystemMessage = true

        } else if self is PersistedMessageSystem {
            
            text = displayableAttributedBody ?? AttributedString(textBody ?? "")
            isSystemMessage = true

        } else if !readOnce && initialExistenceDuration == nil && visibilityDuration == nil {
            
            // If the subtitle is empty, there might be attachments
            if let fyleMessageJoinWithStatus = fyleMessageJoinWithStatus, (textBody ?? "").isEmpty, fyleMessageJoinWithStatus.count > 0 {
                text = AttributedString(PersistedMessage.Strings.countAttachments(fyleMessageJoinWithStatus.count))
                isSystemMessage = true
            } else {
                text = displayableAttributedBody ?? AttributedString(textBody ?? "")
                isSystemMessage = false
            }
            
        } else {
            
            if let sentMessage = self as? PersistedMessageSent {
                
                assert(!sentMessage.isWiped)
                // If the subtitle is empty, there might be attachments
                if let fyleMessageJoinWithStatus = sentMessage.fyleMessageJoinWithStatus, (sentMessage.textBody ?? "").isEmpty, fyleMessageJoinWithStatus.count > 0 {
                    text = AttributedString(PersistedMessage.Strings.countAttachments(fyleMessageJoinWithStatus.count))
                    isSystemMessage = true
                } else {
                    text = displayableAttributedBody ?? AttributedString(textBody ?? "")
                    isSystemMessage = false
                }
                
            } else if let receivedMessage = self as? PersistedMessageReceived {
                
                if readOnce || visibilityDuration != nil {
                    
                    // Ephemeral received message with readOnce or limited visibility
                    switch receivedMessage.status {
                    case .new, .unread:
                        text = AttributedString(PersistedMessage.Strings.unreadEphemeralMessage)
                        isSystemMessage = true
                    case .read:
                        assert(!isWiped)
                        // If the subtitle is empty, there might be attachments
                        if let fyleMessageJoinWithStatus = fyleMessageJoinWithStatus, (textBody ?? "").isEmpty, fyleMessageJoinWithStatus.count > 0 {
                            text = AttributedString(PersistedMessage.Strings.countAttachments(fyleMessageJoinWithStatus.count))
                            isSystemMessage = true
                        } else {
                            text = displayableAttributedBody ?? AttributedString(textBody ?? "")
                            isSystemMessage = false
                        }
                    }
                    
                } else {
                    
                    // Ephemeral received message with limited existence only
                    assert(!isWiped)
                    // If the subtitle is empty, there might be attachments
                    if let fyleMessageJoinWithStatus = fyleMessageJoinWithStatus, (textBody ?? "").isEmpty, fyleMessageJoinWithStatus.count > 0 {
                        text = AttributedString(PersistedMessage.Strings.countAttachments(fyleMessageJoinWithStatus.count))
                        isSystemMessage = true
                    } else {
                        text = displayableAttributedBody ?? AttributedString(textBody ?? "")
                        isSystemMessage = false
                    }
                    
                }
                
            } else {
                
                assertionFailure()
                text = AttributedString("")
                isSystemMessage = true

            }
        }
        
        // Note that we don't need to apply a special style for emphasized, strong, etc.
        // as the SwiftUI view will do the job for us.
        
        return text
            .withStyleForInlinePresentationIntents(isSystemMessage: isSystemMessage)
            .removingLinkAttributes()
        
    }
}


// MARK: - AttributedString helper used when computing a cell subtitle from a PersistedMessage

private extension AttributedString {
    
    func withStyleForInlinePresentationIntents(isSystemMessage: Bool) -> AttributedString {
        let textStyle: UIFont.TextStyle = .subheadline
        var output = self
        if isSystemMessage {
            output.font = .italic(forTextStyle: textStyle)
        } else {
            output.font = UIFont.preferredFont(forTextStyle: textStyle)
        }
        return output
    }
    
    
    /// Remove the links from the AttributedString since we don't want to let the user interact with them from the list of recent discussions.
    func removingLinkAttributes() -> AttributedString {
        var output = self
        output.link = .none
        return output
    }
    
}

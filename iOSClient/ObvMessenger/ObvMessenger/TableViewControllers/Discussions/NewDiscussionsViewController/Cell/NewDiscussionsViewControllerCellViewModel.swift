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
import CoreData
import ObvUICoreData
import UI_CircledInitialsView_CircledInitialsConfiguration

@available(iOS 16.0, *)
extension NewDiscussionsViewController.Cell {
    
    struct ViewModel {
        let numberOfNewReceivedMessages: Int
        let circledInitialsConfig: CircledInitialsConfiguration?
        let shouldMuteNotifications: Bool
        let isArchived: Bool
        let title: String
        let subtitle: String
        let isSubtitleInItalics: Bool
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
        
        let subtitle: String
        let isSubtitleInItalics: Bool
        if let illustrativeMessage = discussion.illustrativeMessage {
            let subtitleConfig = illustrativeMessage.subtitle
            subtitle = subtitleConfig.text
            isSubtitleInItalics = subtitleConfig.italics
        } else {
            subtitle = NSLocalizedString("NO_MESSAGE", comment: "")
            isSubtitleInItalics = true
        }
        
        return Self.init(numberOfNewReceivedMessages: discussion.numberOfNewMessages,
                         circledInitialsConfig: discussion.circledInitialsConfiguration,
                         shouldMuteNotifications: discussion.hasNotificationsMuted,
                         isArchived: discussion.isArchived,
                         title: discussion.title,
                         subtitle: subtitle,
                         isSubtitleInItalics: isSubtitleInItalics,
                         timestampOfLastMessage: discussion.timestampOfLastMessage.discussionCellFormat,
                         pinnedIndex: discussion.pinnedIndex,
                         style: ObvMessengerSettings.Interface.identityColorStyle,
                         aNewReceivedMessageDoesMentionOwnedIdentity: discussion.aNewReceivedMessageDoesMentionOwnedIdentity)
    }
    
}


// MARK: - CustomStringConvertible

@available(iOS 16.0, *)
extension NewDiscussionsViewController.Cell.ViewModel {

    public var description: String {
        return """
            numberOfNewReceivedMessages: \(numberOfNewReceivedMessages)
            circledInitialsConfig: \(String(describing: circledInitialsConfig))
            shouldMuteNotifications: \(shouldMuteNotifications)
            title: \(title)
            subtitle: \(subtitle)
            isSubtitleInItalics: \(isSubtitleInItalics)
            timestampOfLastMessage: \(timestampOfLastMessage)
            pinnedIndex: \(String(describing: pinnedIndex))
        """
    }
    
}

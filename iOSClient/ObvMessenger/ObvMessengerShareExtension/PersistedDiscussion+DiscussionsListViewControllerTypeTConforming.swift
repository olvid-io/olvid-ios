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
  

import CoreData
import Foundation
import ObvUI
import os.log


@available(iOS 16.0, *)
extension PersistedDiscussion: DiscussionsListViewControllerTypeTConforming {
    static func createDiscussionsListCellViewModel(with id: NSManagedObjectID) -> DiscussionsListCellViewModel? {
        guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: id, within: ObvStack.shared.viewContext) else {
            return nil
        }
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
        return DiscussionsListCellViewModel(numberOfNewReceivedMessages: discussion.numberOfNewMessages,
                                            circledInitialsConfig: discussion.circledInitialsConfiguration,
                                            shouldMuteNotifications: discussion.shouldMuteNotifications,
                                            title: discussion.title,
                                            subtitle: subtitle,
                                            isSubtitleInItalics: isSubtitleInItalics,
                                            timestampOfLastMessage: discussion.timestampOfLastMessage.discussionCellFormat)
    }
    
    static func createDiscussionsListShortCellViewModel(with id: NSManagedObjectID) -> DiscussionsListShortCellViewModel? {
        guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: id, within: ObvStack.shared.viewContext) else {
            return nil
        }
        return DiscussionsListShortCellViewModel(numberOfNewReceivedMessages: discussion.numberOfNewMessages,
                                                 circledInitialsConfig: discussion.circledInitialsConfiguration,
                                                 shouldMuteNotifications: discussion.shouldMuteNotifications,
                                                 title: discussion.title)
    }
    
    static func createDiscussionsListSelectionCellViewModel(with id: NSManagedObjectID) -> DiscussionsListSelectionCellViewModel? {
        guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: id, within: ObvStack.shared.viewContext) else {
            return nil
        }
        
        do {
            let subtitle: String?
            let subtitleLineTwo: String?
            
            let kind = try discussion.kind
            switch kind {
            case .oneToOne(withContactIdentity: let identity):
                subtitle = identity?.displayedCompany
                subtitleLineTwo = identity?.displayedPosition
                
            case .groupV2(withGroup: let group):
                if let group {
                    subtitle = String.localizedStringWithFormat(NSLocalizedString("WITH_N_PARTICIPANTS", comment: ""), group.otherMembers.count)
                } else {
                    subtitle = nil
                }
                subtitleLineTwo = nil
                
            case .groupV1(withContactGroup: let group):
                if let group {
                    subtitle = String.localizedStringWithFormat(NSLocalizedString("WITH_N_PARTICIPANTS", comment: ""), group.contactIdentities.count)
                } else {
                    subtitle = nil
                }
                subtitleLineTwo = nil
            }
            return DiscussionsListSelectionCellViewModel(objectId: discussion.objectID,
                                                         title: discussion.title,
                                                         subtitle: subtitle,
                                                         subtitleLineTwo: subtitleLineTwo,
                                                         circledInitialsConfig: discussion.circledInitialsConfiguration)
        } catch {
            os_log("createDiscussionsListSelectionCellViewModel: %@",
                   log: OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: Self.self)),
                   type: .error,
                   error.localizedDescription)
            assertionFailure()
            return nil
        }
    }
}

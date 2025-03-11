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
import Combine
import CoreData
import ObvUICoreData
import os.log
import ObvUIObvCircledInitials
import ObvDesignSystem
import ObvSettings


@available(iOS 16, *)
extension HorizontalListOfSelectedDiscussionsViewController.Cell {
    
    public struct ViewModel: Hashable, Equatable {
        let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
        let title: String
        let subtitle: String?
        let subtitleLineTwo: String?
        let circledInitialsConfig: CircledInitialsConfiguration?
        let style: IdentityColorStyle
    }
    
}


@available(iOS 16.0, *)
extension HorizontalListOfSelectedDiscussionsViewController.Cell.ViewModel {
    
    static func createFromPersistedDiscussion(with discussionId: TypeSafeManagedObjectID<PersistedDiscussion>, within viewContext: NSManagedObjectContext) -> Self? {
        do {
            guard let discussion: PersistedDiscussion = try PersistedDiscussion.get(objectID: discussionId.objectID, within: viewContext) else {
                return nil
            }
            
            let subtitle: String?
            let subtitleLineTwo: String?
            
            let kind = try discussion.kind
            switch kind {
            case .oneToOne(withContactIdentity: let identity):
                subtitle = identity?.displayedCompany
                subtitleLineTwo = identity?.displayedPosition
                
            case .groupV2(withGroup: let group):
                if let group {
                    subtitle = String(localized: "WITH_\(group.otherMembers.count)_PARTICIPANTS")
                } else {
                    subtitle = nil
                }
                subtitleLineTwo = nil
                
            case .groupV1(withContactGroup: let group):
                if let group {
                    subtitle = String(localized: "WITH_\(group.contactIdentities.count)_PARTICIPANTS")
                } else {
                    subtitle = nil
                }
                subtitleLineTwo = nil
            }
            return Self.init(discussionObjectID: discussionId,
                             title: discussion.title,
                             subtitle: subtitle,
                             subtitleLineTwo: subtitleLineTwo,
                             circledInitialsConfig: discussion.circledInitialsConfiguration,
                             style: ObvMessengerSettings.Interface.identityColorStyle)
        } catch {
            os_log("createDiscussionsListSelectionCellViewModel: %@",
                   log: OSLog(subsystem: ObvUIConstants.logSubsystem, category: String(describing: Self.self)),
                   type: .error,
                   error.localizedDescription)
            assertionFailure()
            return nil
        }
    }
}

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
import UIKit


@available(iOS 16.0, *)
final class MessengerDiscussionsListViewController<T: DiscussionsListViewControllerTypeTConforming>: DiscussionsListViewController<T> {
    
    override func createLayout(dataSource: DataSource) -> UICollectionViewLayout {
        let sectionProvider = { [weak self, weak dataSource] (sectionIndex: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in
            
            guard let sectionKind = dataSource?.sectionIdentifier(for: sectionIndex) else { return nil }
            
            let section: NSCollectionLayoutSection
            switch sectionKind {
            case .segmentControl: // list
                let configuration = UICollectionLayoutListConfiguration(appearance: .plain)
                section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
                
            case .discussions: // list
                var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
                configuration.trailingSwipeActionsConfigurationProvider = { [weak self] tvIndexPath in
                    guard let selectedItem = dataSource?.itemIdentifier(for: tvIndexPath) else { return UISwipeActionsConfiguration(actions: []) }
                    switch (selectedItem) {
                    case .persistedDiscussion(let listItemID):
                        let deleteAction = UIContextualAction(style: .destructive, title: CommonString.Word.Delete) { [weak self] (action, view, handler) in
                            guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: listItemID.objectID, within: ObvStack.shared.viewContext) else { return }
                            let payload: (PersistedDiscussion, (Bool) -> Void) = (discussion, handler)
                            self?.coordinator?.eventOccurred(with: .buttonTapped(type: payload))
                        }
                        let markAllAsNotNewAction = UIContextualAction(style: UIContextualAction.Style.normal, title: PersistedMessage.Strings.markAllAsRead) { (action, view, handler) in
                            guard let discussion: PersistedDiscussion = try? PersistedDiscussion.get(objectID: listItemID.objectID, within: ObvStack.shared.viewContext) else { return }
                            ObvMessengerInternalNotification.userWantsToMarkAllMessagesAsNotNewWithinDiscussion(persistedDiscussionObjectID: discussion.objectID, completionHandler: handler)
                                .postOnDispatchQueue()
                        }
                        let configuration = UISwipeActionsConfiguration(actions: [markAllAsNotNewAction, deleteAction])
                        configuration.performsFirstActionWithFullSwipe = false
                        return configuration
                    default:
                        return UISwipeActionsConfiguration(actions: [])
                    }
                }
                section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
            }
            return section
        }
            
        return UICollectionViewCompositionalLayout(sectionProvider: sectionProvider)
    }
}

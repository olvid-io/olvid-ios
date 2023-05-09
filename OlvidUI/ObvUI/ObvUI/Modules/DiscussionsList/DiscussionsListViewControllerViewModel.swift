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
import ObvTypes
import ObvUICoreData
import UIKit


public struct DiscussionsListViewControllerViewModel<T:DiscussionsListViewControllerTypeTConforming> {
    
    public enum DiscussionsListCellType {
        case standard
        case short
    }
    
    public struct Frcs {
        let frcForNonEmptyRecentDiscussionsForOwnedIdentity: NSFetchRequest<T>
        let frcForAllActiveOneToOneDiscussionsSortedByTitleForOwnedIdentity: NSFetchRequest<T>
        let frcForAllGroupDiscussionsSortedByTitleForOwnedIdentity: NSFetchRequest<T>
        
        public init(frcForNonEmpty: NSFetchRequest<T>, frcForAllActive: NSFetchRequest<T>, frcForAllGroup: NSFetchRequest<T>) {
            self.frcForNonEmptyRecentDiscussionsForOwnedIdentity = frcForNonEmpty
            self.frcForAllActiveOneToOneDiscussionsSortedByTitleForOwnedIdentity = frcForAllActive
            self.frcForAllGroupDiscussionsSortedByTitleForOwnedIdentity = frcForAllGroup
        }
    }
    
    public typealias FrcCreationClosure = (ObvCryptoId) -> Frcs

    private(set) var frcForNonEmptyRecentDiscussionsForOwnedIdentity: NSFetchRequest<T>
    private(set) var frcForAllActiveOneToOneDiscussionsSortedByTitleForOwnedIdentity: NSFetchRequest<T>
    private(set) var frcForAllGroupDiscussionsSortedByTitleForOwnedIdentity: NSFetchRequest<T>
    let context: NSManagedObjectContext
    let selectedObjectIds: [TypeSafeManagedObjectID<T>]
    let startInEditMode: Bool
    let coordinator: Coordinator?
    let discussionsListCellType: DiscussionsListCellType
    let frcCreationClosure: FrcCreationClosure
    let withRefreshControl: Bool
    
    var allRequestsAndImages: [(request: NSFetchRequest<T>, image: UIImage)] {
        return [
            (frcForNonEmptyRecentDiscussionsForOwnedIdentity, UIImage(systemIcon: .clock)!),
            (frcForAllActiveOneToOneDiscussionsSortedByTitleForOwnedIdentity, UIImage(systemIcon: .person)!),
            (frcForAllGroupDiscussionsSortedByTitleForOwnedIdentity, UIImage(systemIcon: .person3)!)
        ]
    }
    
    public init(frcCreationClosure: @escaping FrcCreationClosure,
                cryptoId: ObvCryptoId,
                context: NSManagedObjectContext,
                coordinator: Coordinator?,
                discussionsListCellType: DiscussionsListCellType,
                selectedObjectIds: [TypeSafeManagedObjectID<T>] = [],
                withRefreshControl: Bool,
                startInEditMode: Bool = false) {
        
        let frcs = frcCreationClosure(cryptoId)
        self.frcForNonEmptyRecentDiscussionsForOwnedIdentity = frcs.frcForNonEmptyRecentDiscussionsForOwnedIdentity
        self.frcForAllActiveOneToOneDiscussionsSortedByTitleForOwnedIdentity = frcs.frcForAllActiveOneToOneDiscussionsSortedByTitleForOwnedIdentity
        self.frcForAllGroupDiscussionsSortedByTitleForOwnedIdentity = frcs.frcForAllGroupDiscussionsSortedByTitleForOwnedIdentity
        self.frcCreationClosure = frcCreationClosure
        self.context = context
        self.coordinator = coordinator
        self.selectedObjectIds = selectedObjectIds
        self.withRefreshControl = withRefreshControl
        self.startInEditMode = startInEditMode
        self.discussionsListCellType = discussionsListCellType
    }
    
    public mutating func reloadFrcs(using cryptoId: ObvCryptoId) {
        let frcs = frcCreationClosure(cryptoId)
        self.frcForNonEmptyRecentDiscussionsForOwnedIdentity = frcs.frcForNonEmptyRecentDiscussionsForOwnedIdentity
        self.frcForAllActiveOneToOneDiscussionsSortedByTitleForOwnedIdentity = frcs.frcForAllActiveOneToOneDiscussionsSortedByTitleForOwnedIdentity
        self.frcForAllGroupDiscussionsSortedByTitleForOwnedIdentity = frcs.frcForAllGroupDiscussionsSortedByTitleForOwnedIdentity
    }
}

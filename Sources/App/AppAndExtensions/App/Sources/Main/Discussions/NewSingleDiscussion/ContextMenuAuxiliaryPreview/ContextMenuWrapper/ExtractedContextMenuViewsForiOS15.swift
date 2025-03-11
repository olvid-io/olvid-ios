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
 *  but WITHOUT ANY WARRANTY without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import UIKit

@available(iOS, introduced: 15, deprecated: 16, message: "USe ExtractedContextMenuViewsForiOS16 for iOS16+")
struct ExtractedContextMenuViewsForiOS15: ExtractedContextMenuViews {
    
    private var contextMenuContainerViewWrapper: ContextMenuContainerViewWrapper
    private var morphingPlatterViewWrapper: MorphingPlatterViewWrapper
    private var contextMenuActionsListViewWrapper: ContextMenuViewWrapper?
    
    weak var sharedRootView: UIView?
    
    var windowRootView: UIView? {
        self.contextMenuContainerViewWrapper.wrappedObject
    }
    
    var previewRootView: UIView? {
        self.morphingPlatterViewWrapper.wrappedObject
    }
    
    var shadowView: UIView? {
        self.morphingPlatterViewWrapper.platterSoftShadowViewWrapper?.wrappedObject
    }
    
    var listRootView: UIView? {
        self.contextMenuActionsListViewWrapper?.wrappedObject
    }
    
    init?(usingManager contextMenuManager: ContextMenuManager) {
        
        guard let contextMenuContainerViewWrapper = contextMenuManager.contextMenuContainerViewWrapper else { return nil }
        
        self.contextMenuContainerViewWrapper = contextMenuContainerViewWrapper
        
        guard let contextMenuSharedRootView = contextMenuContainerViewWrapper.contextMenuSharedRootView else { return nil }
        
        self.sharedRootView = contextMenuSharedRootView
        
        let morphingPlatterViewWrapper: MorphingPlatterViewWrapper? = contextMenuSharedRootView.subviews.reduce(nil) { $0 ?? .init(objectToWrap: $1) }
        
        guard let morphingPlatterViewWrapper = morphingPlatterViewWrapper else { return nil }
        
        self.morphingPlatterViewWrapper = morphingPlatterViewWrapper
        
        self.contextMenuActionsListViewWrapper = contextMenuSharedRootView.subviews.reduce(nil) { $0 ?? .init(objectToWrap: $1) }
    }
}

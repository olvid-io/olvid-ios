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

@available(iOS 16, *)
struct ExtractedContextMenuViewsForiOS16: ExtractedContextMenuViews {
    
    private var contextMenuContainerViewWrapper: ContextMenuContainerViewWrapper
    private var contextMenuPlatterTransitionViewWrapper: ContextMenuPlatterTransitionViewWrapper
    private var morphingPlatterViewWrapper: MorphingPlatterViewWrapper
    
    private var contextMenuViewWrapper: ContextMenuViewWrapper?
    
    var windowRootView: UIView? {
        self.contextMenuContainerViewWrapper.wrappedObject
    }
    
    var previewRootView: UIView? {
        self.morphingPlatterViewWrapper.wrappedObject
    }
    
    var sharedRootView: UIView? {
        self.contextMenuPlatterTransitionViewWrapper.wrappedObject
    }
    
    var listRootView: UIView? {
        self.contextMenuViewWrapper?.wrappedObject
    }
    
    var shadowView: UIView? {
        self.morphingPlatterViewWrapper.platterSoftShadowViewWrapper?.wrappedObject
    }
    
    init?(usingManager contextMenuManager: ContextMenuManager){
        
        guard let contextMenuContainerViewWrapper = contextMenuManager.contextMenuContainerViewWrapper else { return nil }
        
        self.contextMenuContainerViewWrapper = contextMenuContainerViewWrapper
        
        guard let contextMenuPlatterTransitionViewWrapper = contextMenuContainerViewWrapper.contextMenuPlatterTransitionViewWrapper else { return nil }
        
        self.contextMenuPlatterTransitionViewWrapper = contextMenuPlatterTransitionViewWrapper
        
        guard let morphingPlatterViewWrapper = contextMenuPlatterTransitionViewWrapper.morphingPlatterViewWrapper else { return nil }
        
        self.morphingPlatterViewWrapper = morphingPlatterViewWrapper
        
        let contextMenuViewWrapper = contextMenuPlatterTransitionViewWrapper.contextMenuViewWrapper
        
        self.contextMenuViewWrapper = contextMenuViewWrapper
    }
    
}

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
import ObvUICoreData


protocol ContextMenuManagerDelegate: AnyObject {
    
    // Method used by the ContextMenuManager to fetch the custom view (i.e. the auxiliary preview view) to be displayed alongside the native context menu.
    func contextMenuRequestsAuxiliaryPreview(_ contextMenu: ContextMenuManager, forMessageWithIdentifier messageId: TypeSafeManagedObjectID<PersistedMessage>) -> UIView?
    
}



/// Class used to handle context menu and trigger what is needed in order to display auxiliary view alongside native context menu views.
final class ContextMenuManager {
    
    private var auxiliaryPreviewMenuManager: AuxiliaryPreviewMenuManager?
    
    private var isAuxiliaryPreviewEnabled = true
    
    private var isContextMenuVisible = false
    
    // Custom view we want to display alongside the native context menu view
    private(set) var auxiliaryPreviewView: UIView?
    
    // View that is highlighted and previewed when user is force pressing / long pressing a view.
    private weak var menuTargetView: UIView?
    
    weak var delegate: ContextMenuManagerDelegate?
    
    private weak var contextMenuInteraction: UIContextMenuInteraction?
        
    private var isAuxiliaryPreviewVisible: Bool { auxiliaryPreviewMenuManager?.isAuxiliaryPreviewVisible ?? false }
    
    private let messageId: TypeSafeManagedObjectID<PersistedMessage>
    
    
    // Main wrapper to get in order to extract views used by the native context menu to add the auxiliary preview view
    var contextMenuContainerViewWrapper: ContextMenuContainerViewWrapper? {
      guard let targetView = self.menuTargetView,
            let window = targetView.window
      else { return nil }
      
      return window.subviews.reduce(nil) { (prev, subview) in
        prev ?? ContextMenuContainerViewWrapper(objectToWrap: subview)
      }
    }
    
    
    init(contextMenuInteraction: UIContextMenuInteraction?, menuTargetView: UIView?, messageId: TypeSafeManagedObjectID<PersistedMessage>) {
        self.contextMenuInteraction = contextMenuInteraction
        self.menuTargetView = menuTargetView
        self.messageId = messageId
    }
    
    
    // context menu display begins
    func notifyOnContextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                               willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                               animator: UIContextMenuInteractionAnimating?) {
        
        self.isContextMenuVisible = true
        
        guard self.isAuxiliaryPreviewEnabled,
                let animator = animator, let
                delegate = self.delegate,
              let auxiliaryPreviewView = delegate.contextMenuRequestsAuxiliaryPreview(self, forMessageWithIdentifier: messageId) else {
            return
        }
        
        self.auxiliaryPreviewView = auxiliaryPreviewView
        
        auxiliaryPreviewView.alpha = 0.0
        
        animator.addAnimations {
            let auxiliaryPreviewMenuManager = AuxiliaryPreviewMenuManager(contextMenuManager: self, contextMenuAnimator: animator)
            
            guard let auxiliaryPreviewMenuManager = auxiliaryPreviewMenuManager else { return }
            
            self.auxiliaryPreviewMenuManager = auxiliaryPreviewMenuManager
            
            auxiliaryPreviewMenuManager.notifyOnMenuWillShow()
            
            auxiliaryPreviewView.updateConstraints()
            auxiliaryPreviewView.alpha = 1.0
            auxiliaryPreviewMenuManager.attachAuxiliaryPreview()
            
            auxiliaryPreviewView.layoutIfNeeded()
        }
    }
    
    
    // context menu display will end
    func notifyOnContextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                               willEndFor configuration: UIContextMenuConfiguration,
                                               animator: UIContextMenuInteractionAnimating?) {
        guard self.isAuxiliaryPreviewEnabled,
              self.isAuxiliaryPreviewVisible,
              let animator = animator,
              let auxPreviewManager = self.auxiliaryPreviewMenuManager
        else { return }
        
        auxPreviewManager.notifyOnMenuWillHide()
        
        animator.addAnimations {
            self.auxiliaryPreviewView?.alpha = 0.0
        }
        
        animator.addCompletion {
          self.isContextMenuVisible = false
          self.auxiliaryPreviewMenuManager = nil
          self.auxiliaryPreviewView = nil
        }
    }
}

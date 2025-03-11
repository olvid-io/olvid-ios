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

/// Class used to handle the auxiliary view added to the native context menu
final class AuxiliaryPreviewMenuManager {
    
    private(set) var isAuxiliaryPreviewVisible = false
    
    private var extractedContextMenuViews: ExtractedContextMenuViews?
    
    private weak var window: UIWindow?
    private weak var contextMenuManager: ContextMenuManager?
    private weak var contextMenuAnimator: UIContextMenuInteractionAnimating?
    
    // Parent view where the auxiliary view is added
    private weak var auxiliaryPreviewParentView: UIView?
    
    private var auxiliaryPreviewView: UIView? { self.contextMenuManager?.auxiliaryPreviewView }
    
    
    init?(contextMenuManager contextManager: ContextMenuManager,
                 contextMenuAnimator animator: UIContextMenuInteractionAnimating?) {
        self.contextMenuManager = contextManager
        self.contextMenuAnimator = animator
        
        self.extractContextMenuView()
    }
    
    
    // Boolean checking if we can display the auxiliary view on top of the preview view.
    private func shouldDisplayAuxiliaryOnTop() -> Bool {
        guard let hasMenuItems = extractedContextMenuViews?.hasMenuItems,
              let previewRootView = extractedContextMenuViews?.previewRootView,
              let listRootView = extractedContextMenuViews?.listRootView,
              hasMenuItems
        else { return false }
        
        let previewFrame = previewRootView.frame
        let menuItemsFrame = listRootView.frame
        
        return (menuItemsFrame.midY > previewFrame.midY)
    }
    
    
    func attachAuxiliaryPreview() {
        guard let manager = self.contextMenuManager,
              let auxiliaryPreviewView = manager.auxiliaryPreviewView,
              let auxiliaryPreviewParentView = self.auxiliaryPreviewParentView,
              let windowRootView = self.extractedContextMenuViews?.windowRootView else { return }
        
        // Remove gesture in order for touch events to stop propagating to parent view
        auxiliaryPreviewView.addGestureRecognizer(UITapGestureRecognizer(target: nil, action: nil))
        
        auxiliaryPreviewView.translatesAutoresizingMaskIntoConstraints = false
        
        auxiliaryPreviewParentView.addSubview(auxiliaryPreviewView)
        
        let constraints: [NSLayoutConstraint] = {
            var constraints: [NSLayoutConstraint] = []
            
            // Preview height
            constraints.append(auxiliaryPreviewView.heightAnchor.constraint(equalToConstant: auxiliaryPreviewView.bounds.height))
            
            // vertical constraints
            
            if shouldDisplayAuxiliaryOnTop() {
                constraints.append(auxiliaryPreviewView.bottomAnchor.constraint(equalTo: auxiliaryPreviewParentView.topAnchor, constant: -10.0))
            } else {
                constraints.append(auxiliaryPreviewView.topAnchor.constraint(equalTo: auxiliaryPreviewParentView.bottomAnchor, constant: 10.0))
            }
            
            let auxiliaryWidth: CGFloat = auxiliaryPreviewView.bounds.width
            let windowWidth: CGFloat = windowRootView.bounds.width
            let parentCenterX: CGFloat = auxiliaryPreviewParentView.center.x
            
            let minAuxiliaryX: CGFloat = parentCenterX - (auxiliaryWidth / 2.0)
            let maxAuxiliaryX: CGFloat = parentCenterX + (auxiliaryWidth / 2.0)
            
            var horizontalOffset: CGFloat = 0.0
            
            if maxAuxiliaryX > windowWidth {
                horizontalOffset = -(auxiliaryWidth - auxiliaryPreviewParentView.bounds.width) / 2.0
            } else if minAuxiliaryX < 0.0 {
                horizontalOffset = (auxiliaryWidth - auxiliaryPreviewParentView.bounds.width) / 2.0
            }
            
            // horizontal constraints
            constraints +=  [
                auxiliaryPreviewView.widthAnchor.constraint(equalToConstant: auxiliaryPreviewView.bounds.width),
                auxiliaryPreviewView.centerXAnchor.constraint(equalTo: auxiliaryPreviewParentView.centerXAnchor, constant: horizontalOffset),
            ]
            
            return constraints
        }()
        
        NSLayoutConstraint.activate(constraints)
        
        isAuxiliaryPreviewVisible = true
    }
    
    // Method to extract native context views.
    private func extractContextMenuView() {
        
        guard let manager = self.contextMenuManager else { return }
        
        let contextMenuViews: ExtractedContextMenuViews? = {
            if #available(iOS 16, *) {
                return ExtractedContextMenuViewsForiOS16(usingManager: manager)
            }
            
            if #available(iOS 15, *) {
                return ExtractedContextMenuViewsForiOS15(usingManager: manager)
            }
            
            return nil
        }()
        
        guard let extractedContextMenuViews = contextMenuViews,
              let windowRootView = extractedContextMenuViews.windowRootView,
              let previewRootView = extractedContextMenuViews.previewRootView,
              let window = windowRootView.window else { return }
        self.extractedContextMenuViews = extractedContextMenuViews
        self.window = window
        
        // we are hiding the shadow provided.
        extractedContextMenuViews.shadowView?.subviews.forEach { $0.alpha = 0 }
                
        let isUsingCustomPreview = contextMenuAnimator?.previewViewController != nil
        
        // if we integrate custom preview view, we are adding auxiliary view in preview root view instead of window root view.
        self.auxiliaryPreviewParentView = isUsingCustomPreview ? windowRootView : previewRootView
    }
    
    
    func notifyOnMenuWillShow() {
        self.swizzleViews()
    }
    
    
    func notifyOnMenuWillHide(){
        self.unSwizzleViews()
        self.isAuxiliaryPreviewVisible = false
    }
    
    
    // In order for the user touches to be detected on the auxiliary preview view, we have to swizzle the method to detect touches in order to use our implementation to check if the touch occurs actually on the auxiliary preview view instead of the background view.
    private func swizzleViews() {
        guard !UIView.isSwizzlingApplied,
              let manager = self.contextMenuManager,
              let auxiliaryPreviewView = manager.auxiliaryPreviewView
        else { return }
        UIView.auxPreview = auxiliaryPreviewView
        UIView.swizzlePoint()
    }
    
    
    // We have to un-swizzle the methods to get back the native implementation of point(inside: with) when context menu has been closed.
    private func unSwizzleViews(){
        guard UIView.isSwizzlingApplied else { return }
        // undo swizzling
        UIView.swizzlePoint()
        UIView.auxPreview = nil
    }
    
}


// Fix for preview not receiving touch event
// To handle that, we swizzle implementations for point(inside: with)
fileprivate extension UIView {
    static weak var auxPreview: UIView? = nil
    
    static var isSwizzlingApplied = false
    
    @objc dynamic func _point(inside point: CGPoint,
                              with event: UIEvent?) -> Bool {
        
        guard let auxPreview = UIView.auxPreview else {
            // call original impl.
            return self._point(inside: point, with: event)
        }
        
        let isPointInsideFrameOfAuxPreview: Bool = {
            guard let window = auxPreview.window else { return false }
            
            let auxPreviewFrameAdjustment = auxPreview.convert(auxPreview.bounds, to: window)
            let pointAdjustment = self.convert(point, to: window)
            
            return auxPreviewFrameAdjustment.contains(pointAdjustment)
        }()
        
        let isParentOfAuxPreview = self.subviews.contains { $0 === auxPreview }
        
        guard isParentOfAuxPreview && isPointInsideFrameOfAuxPreview else {
            // call original impl.
            return self._point(inside: point, with: event)
        }
        
        return true
    }
    
    static func swizzlePoint(){
        let selectorOriginal = #selector( point(inside: with:))
        let selectorSwizzled = #selector(_point(inside: with:))
        
        guard let methodOriginal = class_getInstanceMethod(UIView.self, selectorOriginal),
              let methodSwizzled = class_getInstanceMethod(UIView.self, selectorSwizzled)
        else { return }
        
        Self.isSwizzlingApplied.toggle()
        method_exchangeImplementations(methodOriginal, methodSwizzled)
    };
};

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

import UIKit
import PDFKit
import MobileCoreServices
import UniformTypeIdentifiers

class ObvAutoGrowingTextView: UITextView, ViewForDragAndDropDelegate {
    
    var heightConstraint: NSLayoutConstraint? = nil
    var maxHeight: CGFloat? = nil

    weak var growingTextViewDelegate: ObvAutoGrowingTextViewDelegate?
    
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    private func setup() {
        let gestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressGesture(recognizer:)))
        self.addGestureRecognizer(gestureRecognizer)
        // Add a transparent view on top of this view, allowing to support drag and drop
        let viewForDragAndDrop = ViewForDragAndDrop()
        viewForDragAndDrop.frame = self.bounds
        viewForDragAndDrop.delegate = self
        self.addSubview(viewForDragAndDrop)
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: contentSize.width, height: contentSize.height)
    }
    
    // Each time the text changes in a way that might require scrolling, layoutSubviews() is called.
    override func layoutSubviews() {
        super.layoutSubviews()
        if let heightConstraint = self.heightConstraint {
            let newHeight = min(maxHeight ?? intrinsicContentSize.height, intrinsicContentSize.height)
            if heightConstraint.constant != newHeight {
                heightConstraint.constant = newHeight
                scrollRectToVisible(CGRect(x: 0, y: intrinsicContentSize.height-1, width: 1, height: 1), animated: false)
            }
        }
    }
    
}


// MARK: - Handling paste actions

extension ObvAutoGrowingTextView {
    
    @objc func handleLongPressGesture(recognizer: UIGestureRecognizer) {
        if let recognizerView = recognizer.view,
            let recognizerSuperView = recognizerView.superview {
            
            let menuController = UIMenuController.shared
            menuController.showMenu(from: recognizerSuperView, rect: recognizerView.frame)
            recognizerView.becomeFirstResponder()
            
            
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(UIResponderStandardEditActions.paste(_:)),
             #selector(UIResponderStandardEditActions.copy(_:)),
             #selector(UIResponderStandardEditActions.select(_:)),
             #selector(UIResponderStandardEditActions.cut(_:)),
             Selector(("replace:")),
             #selector(UIResponderStandardEditActions.selectAll(_:)):
            return true
        default:
            return false
        }
    }

    override func paste(_ sender: Any?) {
        // If there is pasted text, we do not consider any other item.
        // In case we copy/paste from the Notes app, there is text *and* a .webarchive attachment that we do not want to attach.
        if !UIPasteboard.general.hasStrings {
            growingTextViewDelegate?.userPastedItemsWithoutText(in: self)
        }
        super.paste(sender)
    }
    
    
    func userPasted(itemProviders: [NSItemProvider]) {
        growingTextViewDelegate?.userPasted(itemProviders: itemProviders)
    }

}


final class ViewForDragAndDrop: UIView {
    
    weak var delegate: ViewForDragAndDropDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        self.pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [UTType.data.identifier])
    }
    
    override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
        // We assume that we can always drop/past the item
        return true
    }
    
    override func paste(itemProviders: [NSItemProvider]) {
        delegate?.userPasted(itemProviders: itemProviders)
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let event = event else { return superview }
        switch event.type {
        case .motion,
             .presses,
             .remoteControl,
             .touches:
            return superview
        default:
            // For a drop, the event.type.rawValue is 9, but this is undocumented
            return self
        }
    }

}


protocol ViewForDragAndDropDelegate: AnyObject {
    
    func userPasted(itemProviders: [NSItemProvider])
    
}

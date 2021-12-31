/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import MobileCoreServices


final class AutoGrowingTextView: UITextViewFixed {

    private var heightConstraint: NSLayoutConstraint!
    private var minHeightConstraint: NSLayoutConstraint!
    private var maxHeightConstraint: NSLayoutConstraint!

    private let sizingTextView = UITextViewFixed()
    
    weak var autoGrowingTextViewDelegate: AutoGrowingTextViewDelegate?
    
    var maxHeight: CGFloat {
        get { maxHeightConstraint.constant }
        set {
            guard maxHeight != newValue else { return }
            maxHeightConstraint.constant = newValue
            setNeedsLayout()
        }
    }

    
    override init() {
        super.init()
        
        self.isScrollEnabled = true
        
        self.maxHeightConstraint = self.heightAnchor.constraint(lessThanOrEqualToConstant: 150)
        self.maxHeightConstraint.priority = .required
        self.maxHeightConstraint.isActive = true
        self.heightConstraint = self.heightAnchor.constraint(equalToConstant: 100)
        self.heightConstraint.priority = .required
        self.heightConstraint.isActive = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var intrinsicContentSize: CGSize {
        sizingTextView.text = self.text
        sizingTextView.font = self.font
        sizingTextView.setNeedsLayout()
        sizingTextView.layoutIfNeeded()
        let size = sizingTextView.sizeThatFits(CGSize(width: self.frame.width, height: .greatestFiniteMagnitude))
        return size
    }
    
    // Each time the text changes in a way that might require scrolling, layoutSubviews() is called.
    override func layoutSubviews() {
        super.layoutSubviews()
        let newHeight = min(maxHeight, intrinsicContentSize.height)
        if heightConstraint.constant != newHeight {
            heightConstraint.constant = newHeight
        }
    }
    
}


// MARK: - Handle pasting of attachments for the draft

extension AutoGrowingTextView {
        
    /// Called when the user performs an action on the text view. If the action is a "paste" and the general pasteboard only contains items (i.e., attachments),
    /// we always accept to show the action. Otherwise, we let our superview decide. In the first case, we handle the actual pasting in the
    /// `override func paste(_ sender: Any?)`
    /// implemented bellow.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(UIResponderStandardEditActions.paste(_:)) && UIPasteboard.general.string == nil && !UIPasteboard.general.itemProviders.isEmpty {
            return true
        } else {
            return super.canPerformAction(action, withSender: sender)
        }
    }
    
    /// When the user performs a "paste" action and the general pasteboard only contains items (i.e., attachments), we transfer the pasted items to our
    /// delegate. Otherwise, we let our superview handle the action.
    override func paste(_ sender: Any?) {
        if UIPasteboard.general.string == nil && !UIPasteboard.general.itemProviders.isEmpty {
            assert(autoGrowingTextViewDelegate != nil)
            autoGrowingTextViewDelegate?.userPastedItemProviders(in: self, itemProviders: UIPasteboard.general.itemProviders)
        } else {
            super.paste(sender)
        }
    }
    
    
}


protocol AutoGrowingTextViewDelegate: AnyObject {
    func userPastedItemProviders(in autoGrowingTextView: AutoGrowingTextView, itemProviders: [NSItemProvider])
}

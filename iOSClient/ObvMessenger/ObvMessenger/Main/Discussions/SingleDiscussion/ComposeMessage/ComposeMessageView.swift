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

class ComposeMessageView: UIView {
    
    static let nibName = "ComposeMessageView"
        
    // Views
    
    @IBOutlet weak var visualEffectView: UIVisualEffectView!
    @IBOutlet weak var containerView: UIView!
    @IBOutlet weak var textViewContainerView: UIView!
    @IBOutlet weak var textFieldBackgroundView: TextFieldBackgroundView!
    @IBOutlet weak var textView: ObvAutoGrowingTextView!
    @IBOutlet weak var sendButton: ObvButtonBorderless!
    @IBOutlet weak var placeholderTextView: UITextView!
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var plusButton: UIButton!
    @IBOutlet weak var replyToStackView: UIStackView!
    @IBOutlet weak var replyToNameLabel: UILabel!
    @IBOutlet weak var replyToBodyLabel: UILabel!
    @IBOutlet weak var replyToCancelButton: UIButton!
    @IBOutlet weak var textViewBottomPaddingHeightConstraint: NSLayoutConstraint!
    
    // Constraints
    
    @IBOutlet weak var textViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var collectionViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var visualEffectViewWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var containerViewWidthConstraint: NSLayoutConstraint!
    
    // Variables
    
    private var observationTokens = [NSKeyValueObservation]()
    private var isFreezed = false
    
    // Delegates
    
    weak var documentPickerDelegate: ComposeMessageViewDocumentPickerDelegate? {
        didSet {
            plusButton.isHidden = (documentPickerDelegate == nil)
        }
    }

    weak var sendMessageDelegate: ComposeMessageViewSendMessageDelegate? {
        didSet {
            sendButton.isHidden = (sendMessageDelegate == nil)
        }
    }
    
    var dataSource: ComposeMessageDataSource? {
        didSet {
            loadDataSource()
        }
    }
    
    // Computed variables
    
    override var intrinsicContentSize: CGSize {
        return CGSize.zero // Use autolayout ;-)
    }
    
    @IBAction func deleteReplyToTapped(_ sender: Any) {
        try? dataSource?.deleteReplyTo(completionHandler: { [weak self] (error) in
            DispatchQueue.main.async {
                self?.loadReplyTo()
            }
        })
    }
    
    deinit {
        dataSource?.saveBodyText(body: self.textView.text)
    }

    func setWidth(to width: CGFloat) {
        visualEffectViewWidthConstraint.constant = width
        // We substract the right safeAreaInsets to the container width, since its right side is pinned to the safe arrea. This is important, e.g.,  on an iPhone 11 Pro Max in landscape.
        containerViewWidthConstraint.constant = width - 4 - (window?.safeAreaInsets.right ?? 0)
        self.setNeedsLayout()
    }
    
}


// MARK: View lifecycle

extension ComposeMessageView {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.autoresizingMask = [.flexibleHeight]
        configureViews()
        
        containerView.accessibilityIdentifier = "containerView"
    }
    
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // This method is particularly important when displaying the compose message view in an iPad in split view.
        // In that case, this view does not span the entire screen since its width is equal to that of the detail view.
        // This method allows to let the user interaction "pass through" when she did not touch a view located in the container view (which corresponds to the "visible" portion of this compose message view).
        guard containerView.frame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }

    
    private func configureViews() {
        
        visualEffectView.effect = UIBlurEffect(style: .regular)
        
        plusButton.isHidden = true
        plusButton.tintColor = AppTheme.shared.colorScheme.obvYellow
        plusButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        
        textViewContainerView.backgroundColor = .clear
        textFieldBackgroundView.backgroundColor = .clear
        textFieldBackgroundView.fillColor = appTheme.colorScheme.secondarySystemBackground
        textFieldBackgroundView.strokeColor = appTheme.colorScheme.systemFill
        
        textView.maxHeight = 100
        textViewHeightConstraint.constant = 0 // Must be set here, will be reset by the ObvAutoGrowingTextView
        textView.heightConstraint = self.textViewHeightConstraint
        textView.textColor = AppTheme.shared.colorScheme.secondaryLabel
        textView.delegate = self
        textView.growingTextViewDelegate = self
        
        textViewBottomPaddingHeightConstraint.constant = 3
        
        placeholderTextView.isEditable = false
        placeholderTextView.text = Strings.placeholderText
        placeholderTextView.textColor = appTheme.colorScheme.placeholderText
        placeholderTextView.isSelectable = false
        
        sendButton.isHidden = true
        sendButton.isEnabled = false
        sendButton.setTitle(nil, for: .normal)
        sendButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        let configuration = UIImage.SymbolConfiguration(scale: .large)
        let image = UIImage(systemName: "paperplane.fill", withConfiguration: configuration)
        sendButton.setImage(image, for: .normal)
        
        replyToStackView.isHidden = true

        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.isHidden = dataSource?.collectionViewIsEmpty ?? true
        let token = collectionView.observe(\.contentSize) { [weak self] (_, _) in
            self?.collectionViewContentSizeChanged()
        }
        observationTokens.append(token)
        collectionViewHeightConstraint.constant = FyleCollectionViewCell.intrinsicHeight
        
        replyToCancelButton.tintColor = .red
        
        configureGestureRecognizers()
        
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }
    
    
    private func configureGestureRecognizers() {
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapPerformed(recognizer:)))
        self.addGestureRecognizer(tapGesture)
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressPerformed(recognizer:)))
        self.addGestureRecognizer(longPress)
        
    }
 
    @objc func tapPerformed(recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let location = recognizer.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: location) else { return }
        dataSource?.tapPerformed(on: indexPath)
    }
    
    @objc func longPressPerformed(recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        let location = recognizer.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: location) else { return }
        dataSource?.longPress(on: indexPath)
    }
    
}


// MARK: - Reacting to collection view changes

extension ComposeMessageView {
    
    private func collectionViewContentSizeChanged() {
        refreshSendButton()
        let collectionShouldHide = dataSource?.collectionViewIsEmpty ?? true
        guard collectionView.isHidden != collectionShouldHide else { return }
        // If we reach this point, we should toggle the isHidden property of the collection view
        // We do not use a UIViewPropertyAnimator here, under iOS 12.1.4, this creates an improper computation of the bottom safeAreInset
        UIView.animate(withDuration: 0.5, delay: 0.0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.0, options: [], animations: { [weak self] in
            self?.collectionView.isHidden = collectionShouldHide
        })
    }
    
}

// MARK: - UITextViewDelegate

extension ComposeMessageView: UITextViewDelegate {
    
    func textViewDidChange(_ textView: UITextView) {
        placeholderTextView.isHidden = !textView.text.isEmpty
        refreshSendButton()
    }
    
    
    private func refreshSendButton() {
        
        if !textView.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            sendButton.isEnabled = true
        } else if collectionView.numberOfItems(inSection: 0) > 0 {
            sendButton.isEnabled = true
        } else {
            sendButton.isEnabled = false
        }
        
    }

    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        return !self.isFreezed
    }
    
}


// MARK: - User actions

extension ComposeMessageView {
    
    @IBAction func plusButtonTapped(_ sender: Any) {
        guard let button = sender as? UIButton else { return }
        assert(button == plusButton)
        self.textView.resignFirstResponder()
        documentPickerDelegate?.addAttachment(button)
    }
    
    @IBAction func sendButtonTapped(_ sender: Any) {
        sendMessageDelegate?.userWantsToSendMessageInComposeMessageView(self)
    }

}


// MARK: - Freezing/Unfreezing

extension ComposeMessageView {
    
    func freeze() {
        self.isFreezed = true
        self.plusButton.isEnabled = false
        self.sendButton.isEnabled = false
    }
    
    
    func unfreeze() {
        refreshSendButton()
        self.plusButton.isEnabled = true
        self.isFreezed = false
    }
    
    
    func clearText() {
        self.textView.text = ""
        textViewDidChange(self.textView)
    }
}


// MARK: - Using the ComposeMessageDataSource

extension ComposeMessageView {
    
    func loadDataSource() {
        guard let dataSource = self.dataSource else { return }
        if dataSource.collectionView == nil {
            dataSource.collectionView = self.collectionView
        }
        self.textView.text = dataSource.body
        self.textViewDidChange(textView)
        loadReplyTo()
    }
    
    func loadReplyTo() {
        guard let dataSource = self.dataSource else { return }
        if let (displayName, messageElement) = dataSource.replyTo {
            replyToStackView.isHidden = false
            replyToNameLabel.text = displayName
            replyToBodyLabel.text = messageElement.replyToDescription
            replyToBodyLabel.font = messageElement.font
        } else {
            replyToStackView.isHidden = true
            replyToNameLabel.text = nil
            replyToBodyLabel.text = nil
            replyToBodyLabel.font = nil
        }
    }
    
}


// MARK: - ObvAutoGrowingTextViewDelegate

extension ComposeMessageView: ObvAutoGrowingTextViewDelegate {
    
    func userPasted(itemProviders: [NSItemProvider]) {
        documentPickerDelegate?.addAttachments(itemProviders: itemProviders)
    }
    
    func userPastedItemsWithoutText(in: ObvAutoGrowingTextView) {
        documentPickerDelegate?.addAttachmentFromPasteboard()
    }
    
}

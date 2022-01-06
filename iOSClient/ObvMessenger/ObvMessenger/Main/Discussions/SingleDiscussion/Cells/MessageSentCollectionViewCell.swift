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
import CoreData


final class MessageSentCollectionViewCell: MessageCollectionViewCell {
    
    static let identifier = "MessageSentCollectionViewCell"
    
    let sentStatusLabel = UILabel()
    let sentStatusImageView = UIImageView()
    private var hideProgresses = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func setup() {
        super.setup()
        
        mainStackView.alignment = .trailing
        
        roundedRectView.backgroundColor = appTheme.colorScheme.sentCellBackground
        
        replyToRoundedRectContentView.backgroundColor = AppTheme.shared.colorScheme.sentCellReplyToBackground
        replyToRoundedRectView.backgroundColor = AppTheme.shared.colorScheme.sentCellReplyToBackground
        replyToTextView.textColor = AppTheme.shared.colorScheme.sentCellReplyToBody
        replyToTextView.linkTextAttributes = [NSAttributedString.Key.foregroundColor: AppTheme.shared.colorScheme.sentCellReplyToLink,
                                              NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue,
                                              NSAttributedString.Key.underlineColor: AppTheme.shared.colorScheme.sentCellReplyToLink]
        
        
        bodyTextView.textColor = AppTheme.shared.colorScheme.sentCellBody
        bodyTextView.backgroundColor = .clear
        bodyTextView.linkTextAttributes = [NSAttributedString.Key.foregroundColor: AppTheme.shared.colorScheme.sentCellLink,
                                           NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue,
                                           NSAttributedString.Key.underlineColor: AppTheme.shared.colorScheme.sentCellLink]

        
        sentStatusLabel.accessibilityIdentifier = "sentStatusLabel"
        sentStatusLabel.font = UIFont.preferredFont(forTextStyle: UIFont.TextStyle.caption1)
        sentStatusLabel.textColor = dateLabel.textColor
        bottomStackView.insertArrangedSubview(sentStatusLabel, at: 0)


        sentStatusImageView.accessibilityIdentifier = "sentStatusImageView"
        sentStatusImageView.tintColor = sentStatusLabel.textColor
        bottomStackView.insertArrangedSubview(sentStatusImageView, at: 0)
        
        if #available(iOS 13, *) {
            bottomStackView.insertArrangedSubview(messageEditedStatusImageView, at: 0)
        } else {
            bottomStackView.insertArrangedSubview(messageEditedStatusLabel, at: 0)
        }
        bottomStackView.addArrangedSubview(dateLabel)

        countdownStack.alignment = .trailing
        
        setupConstraints()
        prepareForReuse()
    }
    
    
    func setupConstraints() {
        let constraints = [
            mainStackView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: roundedRectView.trailingAnchor)
        ]
        NSLayoutConstraint.activate(constraints)
    }
 
    
    override func prepareForReuse() {
        super.prepareForReuse()
        sentStatusLabel.text = nil
        hideProgresses = false
    }

    
    func prepare(with message: PersistedMessageSent, withDateFormatter dateFormatter: DateFormatter, hideProgresses: Bool) {
        self.hideProgresses = hideProgresses
        if hideProgresses {
            sentStatusImageView.isHidden = true
            sentStatusLabel.isHidden = true
        } else {
            refreshSentStatus(with: message)
        }
        super.prepare(with: message, attachments: message.fyleMessageJoinWithStatuses, withDateFormatter: dateFormatter, hideProgresses: hideProgresses)
        refreshMessageReceivedCellCountdown()
    }
    
    /// Calling this method refreshes this cell's subviews, using the same message
    override func refresh() {
        debugPrint("Refresh MessageSentCollectionViewCell")
        if let messageSent = super.message as? PersistedMessageSent {
            refreshSentStatus(with: messageSent)
        }
        super.refresh()
    }
    
    
    private func refreshSentStatus(with message: PersistedMessageSent) {
        if #available(iOS 13, *) {
            sentStatusImageView.image = imageForMessageStatus(message.status)
        } else {
            sentStatusLabel.text = characterForMessageStatus(message.status)
        }
    }
    
    
    private func characterForMessageStatus(_ status: PersistedMessageSent.MessageStatus) -> String {
        switch status {
        case .unprocessed:
            return "⌚︎"
        case .processing:
            return "⇮"
        case .sent:
            return "✓"
        case .delivered:
            return "✓✓"
        case .read:
            return "read"
        }
    }
    
    @available(iOS 13, *)
    private func imageForMessageStatus(_ status: PersistedMessageSent.MessageStatus) -> UIImage {
        let configuration = UIImage.SymbolConfiguration(textStyle: UIFont.TextStyle.footnote, scale: .small)
        switch status {
        case .unprocessed:
            return UIImage(systemName: "hourglass", withConfiguration: configuration)!
        case .processing:
            return UIImage(systemName: "hare", withConfiguration: configuration)!
        case .sent:
            return UIImage(systemName: "checkmark.circle", withConfiguration: configuration)!
        case .delivered:
            return UIImage(systemName: "checkmark.circle.fill", withConfiguration: configuration)!
        case .read:
            return UIImage(systemName: "eye.fill", withConfiguration: configuration)!
        }
    }
}


// MARK: - Refreshing countdowns for ephemeral messages

extension MessageSentCollectionViewCell {
    
    func refreshMessageReceivedCellCountdown() {
        guard let message = self.message as? PersistedMessageSent else { assertionFailure(); return }
        assert(message.managedObjectContext?.concurrencyType == .mainQueueConcurrencyType)
        guard message.isEphemeralMessage else { return }
        guard !message.isWiped else {
            removeCountdownStack()
            return
        }
        // Make sure the countdownStack is shown
        showCountdownStack()
        // Show appropriate countdown
        switch (message.readOnce, message.expirationForSentLimitedVisibility, message.expirationForSentLimitedExistence) {
        case (true, .none, .none):
            refreshCellCountdownForReadOnce()
        case (false, .some(let visibilityExpiration), .none):
            refreshCellCount(expirationDate: visibilityExpiration.expirationDate, countdownImageView: countdownImageViewVisibility)
        case (true, .some(let visibilityExpiration), .none):
            refreshCellCount(expirationDate: visibilityExpiration.expirationDate, countdownImageView: countdownImageViewReadOnce)
        case (false, .none, .some(let existenceExpiration)):
            refreshCellCount(expirationDate: existenceExpiration.expirationDate, countdownImageView: countdownImageViewExpiration)
        case (true, .none, .some(let existenceExpiration)):
            refreshCellCount(expirationDate: existenceExpiration.expirationDate, countdownImageView: countdownImageViewReadOnce)
        case (false, .some(let visibilityExpiration), .some(let existenceExpiration)):
            if existenceExpiration.expirationDate > visibilityExpiration.expirationDate {
                refreshCellCount(expirationDate: visibilityExpiration.expirationDate, countdownImageView: countdownImageViewVisibility)
            } else {
                refreshCellCount(expirationDate: existenceExpiration.expirationDate, countdownImageView: countdownImageViewExpiration)
            }
        case (true, .some(let visibilityExpiration), .some(let existenceExpiration)):
            let expirationDate = min(visibilityExpiration.expirationDate, existenceExpiration.expirationDate)
            refreshCellCount(expirationDate: expirationDate, countdownImageView: countdownImageViewReadOnce)
        default:
            removeCurrentCountdownImageView()
            countdownLabel.text = nil
        }
    }
    
    
    private func showCountdownStack() {
        guard !countdownStackIsShown else { return }
        roundedRectView.addSubview(countdownStack)
        NSLayoutConstraint.activate([
            countdownStack.topAnchor.constraint(equalTo: roundedRectView.topAnchor),
            countdownStack.trailingAnchor.constraint(equalTo: roundedRectView.leadingAnchor, constant: -4.0),
        ])
        removeCurrentCountdownImageView()
        if countdownStack.subviews.isEmpty {
            countdownStack.addArrangedSubview(countdownLabel)
        }
    }

}

extension MessageSentCollectionViewCell: CellWithMessage {

    var viewForTargetedPreview: UIView {
        self.roundedRectView
    }
    
    var persistedMessage: PersistedMessage? { message }

    var persistedMessageObjectID: TypeSafeManagedObjectID<PersistedMessage>? {
        message?.typedObjectID
    }
    
    var persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>? { nil } // Not used within the old discussion screen

    var textViewToCopy: UITextView? {
        guard isCopyActionAvailable else { return nil }
        return bodyTextView
    }

    var textToCopy: String? {
        guard let text = bodyTextView.text else { return nil }
        guard !text.isEmpty else { return nil }
        return text
    }

    var isSharingActionAvailable: Bool {
        guard let message = self.message else { return false }
        return !message.readOnce
    }

    var isCopyActionAvailable: Bool {
        guard let message = persistedMessage else { return false }
        return message.textBody != nil && !message.readOnce
    }

    var isReplyToActionAvailable: Bool {
        guard let sentMessage = message as? PersistedMessageSent else { return false }
        let discussion = sentMessage.discussion
        guard !(discussion is PersistedDiscussionOneToOneLocked || discussion is PersistedDiscussionGroupLocked) else { return false }
        if sentMessage.readOnce {
            return sentMessage.status == .read
        }
        return true
    }

    var isInfoActionAvailable: Bool {
        guard let sentMessage = message as? PersistedMessageSent else { return false }
        if !sentMessage.unsortedRecipientsInfos.isEmpty { return true }
        if !sentMessage.metadata.isEmpty { return true }
        return false
    }
    var infoViewController: UIViewController? {
        guard isInfoActionAvailable else { return nil }
        let rcv = SentMessageInfosViewController()
        rcv.sentMessage = (message as! PersistedMessageSent)
        return rcv
    }
    
    var isDeleteActionAvailable: Bool { true }
    
    var isEditBodyActionAvailable: Bool {
        guard let sentMessage = message as? PersistedMessageSent else { return false }
        return sentMessage.textBodyCanBeEdited
    }

    var isCallActionAvailable: Bool { false }

}

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


final class MessageReceivedCollectionViewCell: MessageCollectionViewCell {
 
    static let identifier = "MessageReceivedCollectionViewCell"

    let authorNameLabel = UILabelWithLineFragmentPadding()
    let authorNameLabelPaddingView = UIView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    
    override func setup() {
        super.setup()
        
        mainStackView.alignment = .leading
        
        roundedRectView.backgroundColor = AppTheme.shared.colorScheme.receivedCellBackground
        
        replyToRoundedRectContentView.backgroundColor = AppTheme.shared.colorScheme.receivedCellReplyToBackground
        replyToRoundedRectView.backgroundColor = AppTheme.shared.colorScheme.receivedCellReplyToBackground
        replyToTextView.textColor = AppTheme.shared.colorScheme.receivedCellReplyToBody
        replyToTextView.linkTextAttributes = [NSAttributedString.Key.foregroundColor: AppTheme.shared.colorScheme.receivedCellReplyToBody,
                                               NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue,
                                               NSAttributedString.Key.underlineColor: AppTheme.shared.colorScheme.receivedCellReplyToBody]

        bodyTextView.textColor = AppTheme.shared.colorScheme.receivedCellBody
        bodyTextView.linkTextAttributes = [NSAttributedString.Key.foregroundColor: AppTheme.shared.colorScheme.receivedCellLink,
                                           NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue,
                                           NSAttributedString.Key.underlineColor: AppTheme.shared.colorScheme.receivedCellLink]

        authorNameLabelPaddingView.accessibilityIdentifier = "authorNameLabelPaddingView"
        authorNameLabelPaddingView.translatesAutoresizingMaskIntoConstraints = false
        authorNameLabelPaddingView.backgroundColor = .clear
        roundedRectStackView.insertArrangedSubview(authorNameLabelPaddingView, at: 0)

        authorNameLabel.accessibilityIdentifier = "authorNameLabel"
        authorNameLabel.translatesAutoresizingMaskIntoConstraints = false
        authorNameLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        authorNameLabelPaddingView.addSubview(authorNameLabel)

        countdownStack.alignment = .leading

        bottomStackView.addArrangedSubview(dateLabel)
        if #available(iOS 13, *) {
            bottomStackView.addArrangedSubview(messageEditedStatusImageView)
        } else {
            bottomStackView.addArrangedSubview(messageEditedStatusLabel)
        }

        setupConstraints()
        prepareForReuse()
    }
    
    
    func setupConstraints() {
        let constraints = [
            mainStackView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            mainStackView.leadingAnchor.constraint(equalTo: roundedRectView.leadingAnchor),
            authorNameLabel.topAnchor.constraint(equalTo: authorNameLabelPaddingView.topAnchor, constant: 2.0),
            authorNameLabel.trailingAnchor.constraint(equalTo: authorNameLabelPaddingView.trailingAnchor, constant: -4.0),
            authorNameLabel.bottomAnchor.constraint(equalTo: authorNameLabelPaddingView.bottomAnchor, constant: 0.0),
            authorNameLabel.leadingAnchor.constraint(equalTo: authorNameLabelPaddingView.leadingAnchor, constant: 4.0),
        ]
        NSLayoutConstraint.activate(constraints)
        
        authorNameLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        
    }
    
    
    override func prepareForReuse() {
        super.prepareForReuse()
        authorNameLabelPaddingView.isHidden = true
        authorNameLabel.text = nil
        authorNameLabel.textColor = .clear
    }
    
    
    func prepare(with message: PersistedMessageReceived, withDateFormatter dateFormatter: DateFormatter) {
        let displayAuthor = message.discussion is PersistedGroupDiscussion || message.discussion is PersistedDiscussionGroupLocked
        if displayAuthor {
            authorNameLabelPaddingView.isHidden = false
            authorNameLabel.text = message.contactIdentity?.customDisplayName ?? message.contactIdentity?.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName) ?? CommonString.deletedContact
            authorNameLabel.textColor = message.contactIdentity?.cryptoId.textColor ?? appTheme.colorScheme.secondaryLabel
        } else {
            authorNameLabel.isHidden = true
        }
        super.prepare(with: message, attachments: message.fyleMessageJoinWithStatuses, withDateFormatter: dateFormatter, hideProgresses: false)
        refreshMessageReceivedCellCountdown()
        refreshBodyTextViewColor()
    }
    
    
    /// Calling this method refreshes this cell's subviews, using the same message
    override func refresh() {
        if let refreshedAttachments = message?.fyleMessageJoinWithStatus, !refreshedAttachments.isEmpty, self.attachments.isEmpty {
            // This happens when the messages was obtained through a user notification. In that case, the attachments are initially nil.
            // When the message is eventually downloaded from the server, we get the attachments that we set now.
            // The actual update of the collection view showing these attachments is done in the superclass.
            self.attachments = refreshedAttachments
        }
        refreshBodyTextViewColor()
        super.refresh()
    }

    private func refreshBodyTextViewColor() {
        if let message = message,
           case .tapToRead = MessageCollectionViewCell.extractMessageElements(from: message) {
            bodyTextView.textColor = AppTheme.shared.colorScheme.tapToRead
        } else {
            bodyTextView.textColor = AppTheme.shared.colorScheme.receivedCellBody
        }
    }

}

// MARK: - Refreshing countdowns for ephemeral messages

extension MessageReceivedCollectionViewCell {
    
    func refreshMessageReceivedCellCountdown() {
        guard let message = self.message as? PersistedMessageReceived else { assertionFailure(); return }
        guard message.isEphemeralMessage else { return }
        if message.status == .read {
            // Make sure the countdownStack is shown
            showCountdownStack()
            // After interaction, we always display a countdown image and possibly a countdown
            switch (message.readOnce, message.expirationForReceivedLimitedVisibility, message.expirationForReceivedLimitedExistence) {
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
        } else {
            // Before interaction, display expiration countdown if appropriate or remove any
            guard let existenceExpiration = message.expirationForReceivedLimitedExistence else {
                removeCurrentCountdownImageView()
                countdownLabel.text = nil
                return
            }
            // Make sure the countdownStack is shown
            showCountdownStack()
            refreshCellCount(expirationDate: existenceExpiration.expirationDate, countdownImageView: countdownImageViewExpiration)
        }
    }

        
    private func showCountdownStack() {
        guard !countdownStackIsShown else { return }
        roundedRectView.addSubview(countdownStack)
        NSLayoutConstraint.activate([
            countdownStack.topAnchor.constraint(equalTo: roundedRectView.topAnchor),
            countdownStack.leadingAnchor.constraint(equalTo: roundedRectView.trailingAnchor, constant: 4.0),
        ])
        removeCurrentCountdownImageView()
        if countdownStack.subviews.isEmpty {
            countdownStack.addArrangedSubview(countdownLabel)
        }
    }
    
}


extension MessageReceivedCollectionViewCell: CellWithMessage {

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
        guard let receivedMessage = self.message as? PersistedMessageReceived else { return false }
        guard !receivedMessage.readOnce else { return false }
        if receivedMessage.isEphemeralMessage {
            return receivedMessage.status == .read
        } else {
            return true
        }
    }

    var isCopyActionAvailable: Bool {
        guard let message = persistedMessage else { return false }
        return message.textBody != nil && !message.readOnce
    }

    var isReplyToActionAvailable: Bool {
        guard let receivedMessage = message as? PersistedMessageReceived else { return false }
        let discussion = receivedMessage.discussion
        guard !(discussion is PersistedDiscussionOneToOneLocked || discussion is PersistedDiscussionGroupLocked) else { return false }
        if receivedMessage.readOnce {
            return receivedMessage.status == .read
        }
        return true
    }

    var isInfoActionAvailable: Bool {
        guard let receivedMessage = message as? PersistedMessageReceived else { return false }
        if !receivedMessage.metadata.isEmpty { return true }
        return false
    }
    var infoViewController: UIViewController? {
        guard isInfoActionAvailable else { return nil }
        let rcv = ReceivedMessageInfosViewController()
        rcv.receivedMessage = (message as! PersistedMessageReceived)
        return rcv
    }
    
    var isEditBodyActionAvailable: Bool { false }
    
    var isDeleteActionAvailable: Bool { true }

    var isCallActionAvailable: Bool { false }

    var isDeleteOwnReactionActionAvailable: Bool { false }
}

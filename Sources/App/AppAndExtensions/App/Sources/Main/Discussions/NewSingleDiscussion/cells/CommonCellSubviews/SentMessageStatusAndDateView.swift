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

import ObvUI
import ObvUICoreData
import UIKit
import ObvSystemIcon


final class SentMessageStatusAndDateView: ViewForOlvidStack {
    
    override var isPopable: Bool { return false }
    
    func setDate(to date: Date) {
        let dateString = date.formattedForOlvidMessage()
        guard labelForDate.text != dateString else { return }
        labelForDate.text = dateString
    }
    
    func setStatus(to status: PersistedMessageSent.MessageStatus, showEditedStatus: Bool, messageHasMoreThanOneRecipient: Bool) {
        hideStatus()
        statusImages[status]?[messageHasMoreThanOneRecipient]?.showInStack = true
        // Special case, we do not want to show any status image when the status is "hasNoRecipient"
        if status == .hasNoRecipient {
            statusImages[status]?[messageHasMoreThanOneRecipient]?.showInStack = false
        }
        editedStatusImageView.showInStack = showEditedStatus        
    }
    
    private func hideStatus() {
        for imageView in statusImages.values {
            for messageHasMoreThanOneRecipient in [true, false] {
                imageView[messageHasMoreThanOneRecipient]?.showInStack = false
            }
        }
        editedStatusImageView.showInStack = false
    }
    
    private static func symbolIconForStatus(_ status: PersistedMessageSent.MessageStatus, messageHasMoreThanOneRecipient: Bool) -> any SymbolIcon {
        return status.getSymbolIcon(messageHasMoreThanOneRecipient: messageHasMoreThanOneRecipient)
    }
    
    private static let textStyleForStatusImage = UIFont.TextStyle.caption1
    private static let tintColorForStatusImage = UIColor.secondaryLabel
    
    private static func imageForStatus(_ status: PersistedMessageSent.MessageStatus, messageHasMoreThanOneRecipient: Bool) -> UIImage? {
        let config = UIImage.SymbolConfiguration(font: UIFont.preferredFont(forTextStyle: textStyleForStatusImage))
        return UIImage(symbolIcon: SentMessageStatusAndDateView.symbolIconForStatus(status, messageHasMoreThanOneRecipient: messageHasMoreThanOneRecipient), withConfiguration: config)
    }
    

    private let stack = OlvidHorizontalStackView(gap: 6.0, side: .bothSides, debugName: "Sent message status and date view stack view", showInStack: true)
    private let labelForDate = UILabelForOlvidStack()
    private let editedStatusImageView = UIImageViewForOlvidStack()

    
    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }
    

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    private let trailingPadding = CGFloat(4)

    private var statusImages = [PersistedMessageSent.MessageStatus: [Bool: UIImageViewForOlvidStack]]()
    
    private func setupInternalViews() {

        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        stack.addArrangedSubview(labelForDate)
        labelForDate.textColor = .secondaryLabel
        labelForDate.font = UIFont.preferredFont(forTextStyle: .caption1)
        labelForDate.numberOfLines = 0
        labelForDate.adjustsFontForContentSizeCategory = true

        stack.addArrangedSubview(editedStatusImageView)
        let config = UIImage.SymbolConfiguration(font: UIFont.preferredFont(forTextStyle: SentMessageStatusAndDateView.textStyleForStatusImage))
        editedStatusImageView.image = UIImage(systemIcon: .pencil(.circle), withConfiguration: config)
        editedStatusImageView.contentMode = .scaleAspectFit
        editedStatusImageView.showInStack = false
        editedStatusImageView.tintColor = .secondaryLabel
        
        for status in PersistedMessageSent.MessageStatus.allCases {
            var imagesForStatus = [Bool: UIImageViewForOlvidStack]()
            for messageHasMoreThanOneRecipient in [true, false] {
                let imageView = UIImageViewForOlvidStack()
                stack.addArrangedSubview(imageView)
                imageView.image = SentMessageStatusAndDateView.imageForStatus(status, messageHasMoreThanOneRecipient: messageHasMoreThanOneRecipient)
                imageView.contentMode = .scaleAspectFit
                imageView.tintColor = .secondaryLabel
                imagesForStatus[messageHasMoreThanOneRecipient] = imageView
                imageView.showInStack = false
            }
            statusImages[status] = imagesForStatus
        }
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.topAnchor),
            stack.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -trailingPadding),
            stack.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: self.leadingAnchor),
        ])

        let heightConstraint = self.heightAnchor.constraint(equalTo: labelForDate.heightAnchor)
        heightConstraint.priority = .defaultLow
        NSLayoutConstraint.activate([heightConstraint])

    }
        
}

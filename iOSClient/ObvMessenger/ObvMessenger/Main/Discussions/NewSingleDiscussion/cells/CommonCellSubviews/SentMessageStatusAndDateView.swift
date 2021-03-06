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

@available(iOS 14.0, *)
final class SentMessageStatusAndDateView: ViewForOlvidStack {
    
    func setDate(to date: Date) {
        let dateString = dateFormatter.string(from: date)
        guard label.text != dateString else { return }
        label.text = dateString
    }
    
    func setStatus(to status: PersistedMessageSent.MessageStatus, showEditedStatus: Bool) {
        for imageView in statusImages.values {
            imageView.showInStack = false
        }
        statusImages[status]?.showInStack = true
        
        editedStatusImageView.showInStack = showEditedStatus        
    }
    
    private static func symbolIconForStatus(_ status: PersistedMessageSent.MessageStatus) -> ObvSystemIcon {
        switch status {
        case .unprocessed: return .hourglass
        case .processing: return .hare
        case .sent: return .checkmarkCircle
        case .delivered: return .checkmarkCircleFill
        case .read: return .eyeFill
        }
    }
    
    private static let textStyleForStatusImage = UIFont.TextStyle.caption1
    private static let tintColorForStatusImage = UIColor.secondaryLabel
    
    private static func imageForStatus(_ status: PersistedMessageSent.MessageStatus) -> UIImage? {
        let config = UIImage.SymbolConfiguration(font: UIFont.preferredFont(forTextStyle: textStyleForStatusImage))
        return UIImage(systemIcon: SentMessageStatusAndDateView.symbolIconForStatus(status), withConfiguration: config)
    }
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .none
        df.timeStyle = .short
        df.locale = Locale.current
        return df
    }()

    
    private let stack = OlvidHorizontalStackView(gap: 6.0, side: .bothSides, debugName: "Sent message status and date view stack view", showInStack: true)
    private let label = UILabelForOlvidStack()
    private let editedStatusImageView = UIImageViewForOlvidStack()

    
    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }
    

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    private let trailingPadding = CGFloat(4)

    private var statusImages = [PersistedMessageSent.MessageStatus: UIImageViewForOlvidStack]()
    
    private func setupInternalViews() {

        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        stack.addArrangedSubview(editedStatusImageView)
        let config = UIImage.SymbolConfiguration(font: UIFont.preferredFont(forTextStyle: SentMessageStatusAndDateView.textStyleForStatusImage))
        editedStatusImageView.image = UIImage(systemIcon: .pencilCircleFill, withConfiguration: config)
        editedStatusImageView.contentMode = .scaleAspectFit
        editedStatusImageView.showInStack = false
        editedStatusImageView.tintColor = .secondaryLabel
        
        for status in PersistedMessageSent.MessageStatus.allCases {
            let imageView = UIImageViewForOlvidStack()
            stack.addArrangedSubview(imageView)
            imageView.image = SentMessageStatusAndDateView.imageForStatus(status)
            imageView.contentMode = .scaleAspectFit
            imageView.tintColor = .secondaryLabel
            statusImages[status] = imageView
            imageView.showInStack = false
        }

        stack.addArrangedSubview(label)
        label.textColor = .secondaryLabel
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.numberOfLines = 0
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.topAnchor),
            stack.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -trailingPadding),
            stack.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: self.leadingAnchor),
        ])

        let heightConstraint = self.heightAnchor.constraint(equalTo: label.heightAnchor)
        heightConstraint.priority = .defaultLow
        NSLayoutConstraint.activate([heightConstraint])

    }
        
}

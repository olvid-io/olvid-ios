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

@available(iOS 13.0, *)
final class WipedView: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator {
    
    enum Configuration: Equatable, Hashable {
        case locallyWiped
        case remotelyWiped(deleterName: String?)
    }
    
    private var currentConfiguration: Configuration?
    
    func setConfiguration(_ newConfiguration: Configuration) {
        guard self.currentConfiguration != newConfiguration else { return }
        self.currentConfiguration = newConfiguration
        refresh()
    }
    
    private func refresh() {
        switch currentConfiguration {
        case .locallyWiped:
            label.text = Strings.wiped
        case .remotelyWiped(deleterName: let deleterName):
            label.text = Strings.remotelyWiped(deleterName)
        case .none:
            assertionFailure()
            label.text = Strings.wiped
        }
    }

    var textColor: UIColor? {
        get { label.textColor }
        set { label.textColor = newValue }
    }

    var bubbleColor: UIColor? {
        get { bubble.backgroundColor }
        set { bubble.backgroundColor = newValue }
    }

    var maskedCorner: UIRectCorner {
        get { bubble.maskedCorner }
        set { bubble.maskedCorner = newValue }
    }

    private let label = UILabel()
    private let bubble = BubbleView()
    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side
    
    init(expirationIndicatorSide side: ExpirationIndicatorView.Side) {
        self.expirationIndicatorSide = side
        super.init(frame: .zero)
        setupInternalViews()
    }
    

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupInternalViews() {
        
        addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(expirationIndicator)
        expirationIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        bubble.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = UIFont.italic(forTextStyle: .body)
        label.textColor = .label
        
        let verticalInset = MessageCellConstants.bubbleVerticalInset
        let horizontalInsets = MessageCellConstants.bubbleHorizontalInsets
        
        let constraints = [
            bubble.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: self.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: horizontalInsets),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -horizontalInsets),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: verticalInset),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -verticalInset),
        ]
        
        constraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(constraints)
        
        label.setContentCompressionResistancePriority(.required, for: .vertical)

        setupConstraintsForExpirationIndicator(gap: MessageCellConstants.gapBetweenExpirationViewAndBubble)

    }
    
    private struct Strings {
        
        static let remotelyWiped: (String?) -> String = { (deleterName: String?) in
            if let deleterName = deleterName {
                return String.localizedStringWithFormat(NSLocalizedString("WIPED_MESSAGE_BY_%@", comment: ""), deleterName)
            } else {
                return NSLocalizedString("Remotely wiped", comment: "")
            }
        }
        
        static let wiped = NSLocalizedString("WIPED_MESSAGE", comment: "")

    }

}

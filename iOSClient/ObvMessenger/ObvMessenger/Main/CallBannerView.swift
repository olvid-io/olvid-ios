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

import Foundation
import UIKit

final class CallBannerView: UIView {

    // MARK: - Initializers
    
    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private let label = UILabel()

    private func setupInternalViews() {
        self.backgroundColor = AppTheme.shared.colorScheme.callBarColor

        self.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = CommonString.Title.touchToReturnToCall
        label.textAlignment = .center
        label.font = fontForLabel
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.textColor = .white
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapPerformed))
        self.addGestureRecognizer(tap)

        setupConstraints()
    }

    private var fontForLabel: UIFont {
        UIFont.rounded(forTextStyle: .body)
    }

    private let verticalPadding = CGFloat(8)

    private func setupConstraints() {
        
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: self.topAnchor, constant: verticalPadding),
            label.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -verticalPadding),
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor),
        ])
        
    }

    @objc func tapPerformed(recognizer: UITapGestureRecognizer) {
        ObvMessengerInternalNotification.toggleCallView.postOnDispatchQueue()
    }
}

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
import ObvUI
import UIKit
import ObvUICoreData
import ObvDesignSystem


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
        label.adjustsFontForContentSizeCategory = true
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
            self.heightAnchor.constraint(equalToConstant: 44), // iOS guidelines for a button size
            label.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor, multiplier: 1.0, constant: verticalPadding),
            label.heightAnchor.constraint(lessThanOrEqualTo: self.heightAnchor, multiplier: 1.0, constant: verticalPadding),
        ])
        
    }

    @objc func tapPerformed(recognizer: UITapGestureRecognizer) {
        VoIPNotification.showCallView.postOnDispatchQueue()
    }
}

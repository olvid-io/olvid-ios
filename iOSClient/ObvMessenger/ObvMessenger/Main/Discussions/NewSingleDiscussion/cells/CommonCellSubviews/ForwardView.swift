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
import ObvUICoreData

@available(iOS 14.0, *)
final class ForwardView: ViewForOlvidStack {

    private let label = UILabel()
    private let forwardImageView = UIImageView()

    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }


    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupInternalViews() {

        addSubview(forwardImageView)
        forwardImageView.translatesAutoresizingMaskIntoConstraints = false

        let config = UIImage.SymbolConfiguration(font: UIFont.preferredFont(forTextStyle: .caption1))
        forwardImageView.image = UIImage(systemIcon: ObvMessengerConstants.forwardIcon, withConfiguration: config)
        forwardImageView.contentMode = .scaleAspectFit
        forwardImageView.tintColor = .secondaryLabel

        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false

        label.text = CommonString.Word.Forwarded
        label.textColor = .secondaryLabel
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.numberOfLines = 0 // Important, otherwise the label does not defines its height
        label.adjustsFontForContentSizeCategory = true

        NSLayoutConstraint.activate([
            forwardImageView.topAnchor.constraint(equalTo: self.topAnchor),
            forwardImageView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            forwardImageView.leadingAnchor.constraint(equalTo: self.leadingAnchor),

            label.leadingAnchor.constraint(equalTo: forwardImageView.trailingAnchor, constant: 2.0),
            label.topAnchor.constraint(equalTo: self.topAnchor),
            label.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
    }


}

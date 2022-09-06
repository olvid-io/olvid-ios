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


final class ContactNameView: ViewForOlvidStack {
    
    var name: String? {
        get { label.text }
        set {
            guard label.text != newValue else { return }
            label.text = newValue
            setNeedsLayout()
        }
    }

    var color: UIColor? {
        get { label.textColor }
        set { label.textColor = newValue }
    }

    private let label = UILabel()
    private let height = CGFloat(30)
    
    init() {
        super.init(frame: .zero)
        setDefaultValues()
        setupInternalViews()
    }
    

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    private func setDefaultValues() {
        self.name = nil
        self.color = .label
    }
    
    private func setupInternalViews() {
        
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = MessageCellConstants.fontForContactName
        label.numberOfLines = 1
        label.adjustsFontForContentSizeCategory = true

        let leadingPadding = CGFloat(4)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: self.topAnchor),
            label.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: leadingPadding),
        ])

        let sizeConstraints = [
            self.heightAnchor.constraint(equalToConstant: height),
        ]
        NSLayoutConstraint.activate(sizeConstraints)

    }
}

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


final class UILabelForOlvidStack: ViewForOlvidStack {
    
    let label = UILabel()
    
    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }

    var text: String? {
        get { label.text }
        set {
            guard label.text != newValue else { return }
            label.text = newValue
        }
    }

    var attributedText: NSAttributedString? {
        get { label.attributedText }
        set { label.attributedText = newValue }
    }

    var font: UIFont? {
        get { label.font }
        set { label.font = newValue }
    }

    var textColor: UIColor? {
        get { label.textColor }
        set { label.textColor = newValue }
    }

    var numberOfLines: Int {
        get { label.numberOfLines }
        set { label.numberOfLines = newValue }
    }
    
    var textAlignment: NSTextAlignment {
        get { label.textAlignment }
        set { label.textAlignment = newValue }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var adjustsFontForContentSizeCategory: Bool {
        get { label.adjustsFontForContentSizeCategory }
        set { label.adjustsFontForContentSizeCategory = newValue }
    }
    
    func setupInternalViews() {
        
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.adjustsFontForContentSizeCategory = true
        
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
        ])
        
    }
    
}

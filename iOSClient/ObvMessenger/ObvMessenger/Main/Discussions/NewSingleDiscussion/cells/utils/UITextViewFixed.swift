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

class UITextViewFixed: UITextView {

    private var defaultTintColor: UIColor?
    private var defaultTextColor: UIColor?

    init() {
        super.init(frame: .zero, textContainer: nil)
        defaultTintColor = self.tintColor
        defaultTextColor = self.textColor
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setup()
    }
    
    func setup() {
        textContainerInset = UIEdgeInsets.zero
        textContainer.lineFragmentPadding = 0
    }
    
}


// MARK: - Looking like a disabled Text View


extension UITextViewFixed {
    
    func lookLikeNotEditable() {
        self.textColor = .secondaryLabel
        self.tintColor = .clear
    }
    
    func lookLikeEditable() {
        self.textColor = .label // It is the defaultTextColor
        self.tintColor = defaultTintColor
    }
    
}

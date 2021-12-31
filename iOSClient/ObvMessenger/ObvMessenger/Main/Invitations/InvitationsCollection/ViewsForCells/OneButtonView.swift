/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

class OneButtonView: UIView {

    static let nibName = "OneButtonView"

    var buttonTitle: String? = "" {
        didSet {
            trailingButton.setTitle(buttonTitle, for: .normal)
            leadingButton.setTitle(buttonTitle, for: .normal)
        }
    }
    var buttonAction: (() -> Void)? = nil

    // Views

    @IBOutlet weak var leadingButton: UIButton!
    @IBOutlet weak var trailingButton: UIButton!
    
}

// MARK: - awakeFromNib

extension OneButtonView {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        translatesAutoresizingMaskIntoConstraints = false
        useTrailingButton()
    }
    
    func useLeadingButton() {
        leadingButton.isHidden = false
        trailingButton.isHidden = true
    }
    
    func useTrailingButton() {
        leadingButton.isHidden = true
        trailingButton.isHidden = false
    }
}


extension OneButtonView {
    
    @IBAction func buttonPressed(_ sender: UIButton) {
        buttonAction?()
    }
    
}

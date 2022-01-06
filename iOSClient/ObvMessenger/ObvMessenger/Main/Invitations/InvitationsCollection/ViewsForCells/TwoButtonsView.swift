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

class TwoButtonsView: UIView {

    static let nibName = "TwoButtonsView"
    
    // Vars
    
    var buttonTitle1: String = "" { didSet { button1?.setTitle(buttonTitle1.uppercased(), for: .normal) }}
    var buttonTitle2: String = "" { didSet { button2?.setTitle(buttonTitle2.uppercased(), for: .normal) }}
    var button1Action: (() -> Void)? = nil
    var button2Action: (() -> Void)? = nil
    
    // Views
    
    @IBOutlet weak var stackView: UIStackView!
    @IBOutlet weak var button1: UIButton!
    @IBOutlet weak var button2: UIButton!
    
}

// MARK: - awakeFromNib

extension TwoButtonsView {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        translatesAutoresizingMaskIntoConstraints = false
    }
    
}


extension TwoButtonsView {
    
    @IBAction func button1Pressed(_ sender: UIButton) {
        button1Action?()
    }
    
    @IBAction func button2Pressed(_ sender: UIButton) {
        button2Action?()
    }

}

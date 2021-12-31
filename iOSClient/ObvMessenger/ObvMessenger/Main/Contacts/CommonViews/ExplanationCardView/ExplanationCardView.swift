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

class ExplanationCardView: UIView {

    static let nibName = "ExplanationCardView"
    
    // Views
    
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var bodyLabel: UILabel!
    @IBOutlet weak var buttonStackSuperView: UIStackView!
    @IBOutlet weak var mainStackView: UIStackView!
    @IBOutlet weak var obvRoundedRectView: ObvRoundedRectView!
    @IBOutlet weak var buttonStackView: UIStackView!
    @IBOutlet weak var iconImageView: UIImageView!
    
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.translatesAutoresizingMaskIntoConstraints = false
        self.layer.masksToBounds = false
        self.backgroundColor = .clear
        buttonStackSuperView.isHidden = true
        
        obvRoundedRectView.withShadow = true
        
        titleLabel.textColor = appTheme.colorScheme.label
        bodyLabel.textColor = appTheme.colorScheme.secondaryLabel
        obvRoundedRectView.backgroundColor = appTheme.colorScheme.tertiarySystemBackground
        
    }
    
    
    func addButton(_ button: UIButton) {
        buttonStackSuperView.isHidden = false
        buttonStackView.addArrangedSubview(button)
    }

}

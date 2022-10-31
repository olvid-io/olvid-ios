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
import ObvEngine
import ObvTypes
import ObvCrypto

class OlvidCardView: UIView {

    static let nibName = "OlvidCardView"

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var buttonStackView: UIStackView!
    @IBOutlet weak var buttonStackSuperView: UIStackView!
    @IBOutlet weak var mainStackView: UIStackView!
    @IBOutlet weak var cardTypeLabel: UILabel!
    @IBOutlet weak var cardTypeView: UIView!
    @IBOutlet weak var obvRoundedRectView: ObvRoundedRectView!
    @IBOutlet weak var circlePlaceholder: UIView!
    
    // Subviews set in awakeFromNib
    
    var circledInitials: CircledInitials!

    override func awakeFromNib() {
        super.awakeFromNib()
        self.translatesAutoresizingMaskIntoConstraints = false
        self.layer.masksToBounds = false
        self.backgroundColor = .clear
        buttonStackSuperView.isHidden = true
        
        titleLabel.textColor = appTheme.colorScheme.label
        subtitleLabel.textColor = appTheme.colorScheme.secondaryLabel
        obvRoundedRectView.backgroundColor = appTheme.colorScheme.tertiarySystemBackground
        
        obvRoundedRectView.withShadow = true
        
        circledInitials = (Bundle.main.loadNibNamed(CircledInitials.nibName, owner: nil, options: nil)!.first as! CircledInitials)
        circlePlaceholder.backgroundColor = .clear
        circlePlaceholder.addSubview(circledInitials)
        circlePlaceholder.pinAllSidesToSides(of: circledInitials)

    }
    
    
    enum CardTypeStyle {
        case red
        case green
    }
    
}


extension OlvidCardView {
    
    func configure(with groupDetails: ObvGroupDetails, groupUid: UID, cardTypeText: String, cardTypeStyle: CardTypeStyle) {
        self.titleLabel.text = groupDetails.coreDetails.name
        self.subtitleLabel.text = groupDetails.coreDetails.description
        
        circledInitials.identityColors = AppTheme.shared.groupColors(forGroupUid: groupUid)
        if let photoURL = groupDetails.photoURL {
            circledInitials.showPhoto(fromUrl: photoURL)
        } else {
            circledInitials.showImage(fromImage: AppTheme.shared.images.groupImage)
        }

        self.cardTypeLabel.text = cardTypeText
        switch cardTypeStyle {
        case .red:
            self.cardTypeView.backgroundColor = AppTheme.appleBadgeRedColor
            self.cardTypeLabel.textColor = .white
        case .green:
            self.cardTypeView.backgroundColor = appTheme.colorScheme.green
            self.cardTypeLabel.textColor = .white
        }
        self.cardTypeView.layer.maskedCorners = [.layerMaxXMaxYCorner, .layerMinXMinYCorner]
        self.cardTypeView.layer.cornerRadius = ObvRoundedRectView.defaultCornerRadius
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }
    
    func configure(with identityDetails: ObvIdentityDetails, cryptoId: ObvCryptoId, cardTypeText: String, cardTypeStyle: CardTypeStyle) {
        self.titleLabel.text = identityDetails.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
        self.subtitleLabel.text = identityDetails.coreDetails.getDisplayNameWithStyle(.positionAtCompany)
        
        circledInitials.showCircledText(from: identityDetails.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName))
        circledInitials.identityColors = cryptoId.colors
        circledInitials.showPhoto(fromUrl: identityDetails.photoURL)
        
        self.cardTypeLabel.text = cardTypeText
        switch cardTypeStyle {
        case .red:
            self.cardTypeView.backgroundColor = AppTheme.appleBadgeRedColor
            self.cardTypeLabel.textColor = .white
        case .green:
            self.cardTypeView.backgroundColor = appTheme.colorScheme.green
            self.cardTypeLabel.textColor = .white
        }
        self.cardTypeView.layer.maskedCorners = [.layerMaxXMaxYCorner, .layerMinXMinYCorner]
        self.cardTypeView.layer.cornerRadius = ObvRoundedRectView.defaultCornerRadius
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }
    
    func addButton(_ button: UIButton) {
        buttonStackSuperView.isHidden = false
        buttonStackView.addArrangedSubview(button)
    }

}

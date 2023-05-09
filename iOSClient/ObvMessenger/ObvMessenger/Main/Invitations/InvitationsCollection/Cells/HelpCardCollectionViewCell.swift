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

import ObvUI
import UIKit


class HelpCardCollectionViewCell: ObvCardCollectionViewCell, InvitationCollectionCell {

    static let nibName = "HelpCardCollectionViewCell"
    static let identifier = "HelpCardCollectionViewCellIdentifier"
    
    private var widthConstraint: NSLayoutConstraint!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var explanationLabel: UILabel!
    
}

// MARK: - awakeFromNib

extension HelpCardCollectionViewCell {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.contentView.translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
        self.widthConstraint = self.contentView.widthAnchor.constraint(equalToConstant: 50.0)
        self.widthConstraint.isActive = true
        
        titleLabel.textColor = AppTheme.shared.colorScheme.label
        explanationLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
    }
}

// MARK: - Configuring the cell

extension HelpCardCollectionViewCell {
    
    func setWidth(to newWidth: CGFloat) {
        widthConstraint.constant = newWidth
    }
    
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        setNeedsLayout()
        layoutIfNeeded()
        let size = contentView.systemLayoutSizeFitting(layoutAttributes.size)
        var newFrame = layoutAttributes.frame
        newFrame.size = size
        layoutAttributes.frame = newFrame
        return layoutAttributes
    }
        
}

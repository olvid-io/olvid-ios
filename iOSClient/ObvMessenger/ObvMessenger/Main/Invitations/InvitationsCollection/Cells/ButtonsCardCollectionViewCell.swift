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

class ButtonsCardCollectionViewCell: ObvCardCollectionViewCell, InvitationCollectionCell, CellContainingHeaderView, CellContainingTwoButtonsView {

    static let nibName = "ButtonsCardCollectionViewCell"
    static let identifier = "buttonsCardCollectionViewCellIdentifier"

    // Views
    
    @IBOutlet weak var placeholderView: UIView!
    @IBOutlet weak var topPlaceholderView: UIView!
    @IBOutlet weak var bottomPlaceholderView: UIView!
    
    // Constraints

    private var widthConstraint: NSLayoutConstraint!

    // Subviews set in awakeFromNib
    
    var cellHeaderView: CellHeaderView!
    var twoButtonsView: TwoButtonsView!

}


// MARK: - awakeFromNib

extension ButtonsCardCollectionViewCell {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.accessibilityIdentifier = "ButtonsCardCollectionViewCell"
        self.contentView.translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
        self.widthConstraint = self.contentView.widthAnchor.constraint(equalToConstant: 50.0)
        self.widthConstraint.isActive = true
        instantiateAndPlaceTheCellHeaderView()
        instantiateAndPlaceTheTwoButtonsView()
    }
 
    private func instantiateAndPlaceTheCellHeaderView() {
        topPlaceholderView.backgroundColor = .clear
        cellHeaderView = (Bundle.main.loadNibNamed(CellHeaderView.nibName, owner: nil, options: nil)!.first as! CellHeaderView)
        topPlaceholderView.addSubview(cellHeaderView)
        topPlaceholderView.pinAllSidesToSides(of: cellHeaderView)
    }
    
    private func instantiateAndPlaceTheTwoButtonsView() {
        bottomPlaceholderView?.backgroundColor = .clear
        twoButtonsView = (Bundle.main.loadNibNamed(TwoButtonsView.nibName, owner: nil, options: nil)!.first as! TwoButtonsView)
        bottomPlaceholderView.addSubview(twoButtonsView)
        bottomPlaceholderView.pinAllSidesToSides(of: twoButtonsView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cellHeaderView.prepareForReuse()
    }

}

// MARK: - Setting the width and accessing the size

extension ButtonsCardCollectionViewCell {
    
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

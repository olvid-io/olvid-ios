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

class SasAcceptedCardCollectionViewCell: ObvCardCollectionViewCell, InvitationCollectionCell, CellContainingHeaderView, CellContainingSasAcceptedView, CellContainingOneButtonView {
    
    static let nibName = "SasAcceptedCardCollectionViewCell"
    static let identifier = "sasAcceptedCardCollectionViewCellIdentifier"
    
    // Views
    
    @IBOutlet weak var placeholderView: UIView!
    @IBOutlet weak var topPlaceholderView: UIView!
    @IBOutlet weak var middlePlaceholderView: UIView!
    @IBOutlet weak var bottomPlaceholderView: UIView!
    
    // Constraints

    private var widthConstraint: NSLayoutConstraint!

    // Subviews set in awakeFromNib
    
    var cellHeaderView: CellHeaderView!
    var sasAcceptedView: SasAcceptedView!
    var oneButtonView: OneButtonView?
    
}

// MARK: - awakeFromNib

extension SasAcceptedCardCollectionViewCell {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.accessibilityIdentifier = "SasAcceptedCardCollectionViewCell"
        self.contentView.translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
        self.widthConstraint = self.contentView.widthAnchor.constraint(equalToConstant: 50.0)
        self.widthConstraint.isActive = true
        instantiateAndPlaceTheCellHeaderView()
        instantiateAndPlaceTheSasAcceptedView()
        instantiateAndPlaceTheOneButtonView()
    }

    private func instantiateAndPlaceTheCellHeaderView() {
        topPlaceholderView.backgroundColor = .clear
        cellHeaderView = (Bundle.main.loadNibNamed(CellHeaderView.nibName, owner: nil, options: nil)!.first as! CellHeaderView)
        topPlaceholderView.addSubview(cellHeaderView)
        topPlaceholderView.pinAllSidesToSides(of: cellHeaderView)
    }

    private func instantiateAndPlaceTheSasAcceptedView() {
        middlePlaceholderView.backgroundColor = .clear
        sasAcceptedView = (Bundle.main.loadNibNamed(SasAcceptedView.nibName, owner: nil, options: nil)!.first as! SasAcceptedView)
        middlePlaceholderView.addSubview(sasAcceptedView)
        middlePlaceholderView.pinAllSidesToSides(of: sasAcceptedView)
    }

    private func instantiateAndPlaceTheOneButtonView() {
        bottomPlaceholderView?.backgroundColor = .clear
        oneButtonView = Bundle.main.loadNibNamed(OneButtonView.nibName, owner: nil, options: nil)!.first as! OneButtonView?
        bottomPlaceholderView?.addSubview(oneButtonView!)
        bottomPlaceholderView?.pinAllSidesToSides(of: oneButtonView!)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cellHeaderView.prepareForReuse()
    }

}

// MARK: - Setting the width and accessing the size

extension SasAcceptedCardCollectionViewCell {
    
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

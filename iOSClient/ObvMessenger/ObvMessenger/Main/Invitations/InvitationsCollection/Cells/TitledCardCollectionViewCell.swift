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

final class TitledCardCollectionViewCell: ObvCardCollectionViewCell, InvitationCollectionCell, CellContainingHeaderView, CellContainingOneButtonView {
    
    static let nibName = "TitledCardCollectionViewCell"
    static let identifier = "titledCardCollectionViewCellIdentifier"
    
    // Views
    
    @IBOutlet weak var placeholderView: UIView!
    @IBOutlet weak var topPlaceholderView: UIView!
    @IBOutlet weak var bottomPlaceholderView: UIView?
    
    // Vars set in awakeFromNib
    
    private var widthConstraint: NSLayoutConstraint!
    var cellHeaderView: CellHeaderView!
    var oneButtonView: OneButtonView?
}

// MARK: - awakeFromNib

extension TitledCardCollectionViewCell {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.contentView.translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
        self.widthConstraint = self.contentView.widthAnchor.constraint(equalToConstant: 50.0)
        self.widthConstraint.isActive = true
        instantiateAndPlaceTheCellHeaderView()
        instantiateAndPlaceTheOneButtonView()
    }
    
    
    private func instantiateAndPlaceTheCellHeaderView() {
        // We add a CellHeaderView and pin it to the 4 hedges of the main placeholder view
        topPlaceholderView.backgroundColor = .clear
        cellHeaderView = (Bundle.main.loadNibNamed(CellHeaderView.nibName, owner: nil, options: nil)!.first as! CellHeaderView)
        topPlaceholderView.addSubview(cellHeaderView)
        topPlaceholderView.pinAllSidesToSides(of: cellHeaderView)
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

extension TitledCardCollectionViewCell {
    
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

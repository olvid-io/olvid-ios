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

class SasCardCollectionViewCell: ObvCardCollectionViewCell, InvitationCollectionCell, CellContainingHeaderView, CellContainingSasView {
    
    static let nibName = "SasCardCollectionViewCell"
    static let identifier = "sasCardCollectionViewCellIdentifier"
    
    // Views
    
    @IBOutlet weak var placeholderView: UIView!
    @IBOutlet weak var topPlaceholderView: UIView!
    @IBOutlet weak var bottomPlaceholderView: UIView!

    // Constraints

    private var widthConstraint: NSLayoutConstraint!

    // Subviews set in awakeFromNib
    
    var cellHeaderView: CellHeaderView!
    var sasView: SasView!
    
}


// MARK: - awakeFromNib

extension SasCardCollectionViewCell {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.accessibilityIdentifier = "SasCardCollectionViewCell"
        self.contentView.translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
        self.widthConstraint = self.contentView.widthAnchor.constraint(equalToConstant: 50.0)
        self.widthConstraint.isActive = true
        instantiateAndPlaceTheCellHeaderView()
        instantiateAndPlaceTheSasView()
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(cellWasTapped))
        self.addGestureRecognizer(tapGestureRecognizer)
    }

    private func instantiateAndPlaceTheCellHeaderView() {
        topPlaceholderView.backgroundColor = .clear
        cellHeaderView = (Bundle.main.loadNibNamed(CellHeaderView.nibName, owner: nil, options: nil)!.first as! CellHeaderView)
        topPlaceholderView.addSubview(cellHeaderView)
        topPlaceholderView.pinAllSidesToSides(of: cellHeaderView)
    }

    private func instantiateAndPlaceTheSasView() {
        bottomPlaceholderView?.backgroundColor = .clear
        sasView = (Bundle.main.loadNibNamed(SasView.nibName, owner: nil, options: nil)!.first as! SasView)
        bottomPlaceholderView.addSubview(sasView)
        bottomPlaceholderView.pinAllSidesToSides(of: sasView)
    }
    
    @objc func cellWasTapped() {
        _ = sasView.resignFirstResponder()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        cellHeaderView.prepareForReuse()
    }

}


// MARK: - Setting the width and accessing the size

extension SasCardCollectionViewCell {
    
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

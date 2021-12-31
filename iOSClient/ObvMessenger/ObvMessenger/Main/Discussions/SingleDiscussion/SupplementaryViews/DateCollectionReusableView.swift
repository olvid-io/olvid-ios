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

final class DateCollectionReusableView: UICollectionReusableView {
    
    static let identifier = "DateCollectionReusableView"
    
    let bodyCell = UIView()
    let label = UILabel()
    var alphaIsLocked = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    
    private func setup() {
        
        self.clipsToBounds = true
        self.autoresizesSubviews = true
        self.isUserInteractionEnabled = false
        
        bodyCell.translatesAutoresizingMaskIntoConstraints = false
        bodyCell.layer.cornerRadius = 13.0
        bodyCell.backgroundColor = AppTheme.shared.colorScheme.primary400.withAlphaComponent(0.9)
        self.addSubview(bodyCell)
        
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.backgroundColor = .clear
        label.textColor = AppTheme.shared.colorScheme.whiteTextHighEmphasis
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        bodyCell.addSubview(label)
        
        setupConstraints()
        
    }
    
    
    private func setupConstraints() {
        let constraints = [
            label.topAnchor.constraint(equalTo: bodyCell.topAnchor, constant: 8.0),
            label.trailingAnchor.constraint(equalTo: bodyCell.trailingAnchor, constant: -8.0),
            label.bottomAnchor.constraint(equalTo: bodyCell.bottomAnchor, constant: -8.0),
            label.leadingAnchor.constraint(equalTo: bodyCell.leadingAnchor, constant: 8.0),
            bodyCell.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            bodyCell.topAnchor.constraint(equalTo: self.topAnchor),
            bodyCell.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            bodyCell.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ]
        NSLayoutConstraint.activate(constraints)
        
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        label.text = nil
        alphaIsLocked = false
    }
    
    override var alpha: CGFloat {
        get {
            return super.alpha
        }
        set {
            guard !alphaIsLocked else { return }
            super.alpha = newValue
        }
    }
    
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        
        var fittingSize = UIView.layoutFittingCompressedSize
        fittingSize.width = layoutAttributes.size.width
        let size = systemLayoutSizeFitting(fittingSize, withHorizontalFittingPriority: .defaultHigh, verticalFittingPriority: .defaultLow)
        var adjustedFrame = layoutAttributes.frame
        adjustedFrame.size.height = size.height
        layoutAttributes.frame = adjustedFrame
        
        return layoutAttributes
        
    }
    
}

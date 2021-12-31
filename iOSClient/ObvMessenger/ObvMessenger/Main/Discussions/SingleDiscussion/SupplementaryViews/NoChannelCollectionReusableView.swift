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

class NoChannelCollectionReusableView: UICollectionReusableView {
    
    static let identifier = "NoChannelCollectionReusableView"
    
    let label = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setup() {
        
        self.clipsToBounds = true
        self.autoresizesSubviews = true
        
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = AppTheme.shared.colorScheme.label
        label.textAlignment = .center
        self.addSubview(label)
        
        setupConstraints()
    }
    
    
    private func setupConstraints() {
        let constraints = [
            label.topAnchor.constraint(equalTo: self.topAnchor),
            label.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor)
        ]
        NSLayoutConstraint.activate(constraints)
    }
    
    func configure(with text: String) {
        self.label.text = text
    }
    
}


extension NoChannelCollectionReusableView {
    
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

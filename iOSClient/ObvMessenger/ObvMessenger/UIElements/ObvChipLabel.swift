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
import ObvDesignSystem


final class ObvChipLabel: UIView {

    static let defaultTextColor = AppTheme.shared.colorScheme.label
    var chipColor = AppTheme.shared.colorScheme.systemFill

    var text: String? {
        get { return label.text }
        set { label.text = newValue }
    }
    
    var textColor: UIColor {
        get { return label.textColor }
        set { label.textColor = newValue }
    }
    
    
    
    private let horizontalPadding: CGFloat = 8.0
    private let verticalPadding: CGFloat = 4.0
    private let label = UILabel()


    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
        self.commonInit()

    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.commonInit()
    }

    override var intrinsicContentSize: CGSize {
        let height = self.label.intrinsicContentSize.height + self.verticalPadding * 2
        let width = max(self.label.intrinsicContentSize.width + self.horizontalPadding * 2, height)
        return CGSize(width: width, height: height)
    }
    
    func commonInit() {
        self.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.preferredFont(forTextStyle: UIFont.TextStyle.footnote)
        label.textAlignment = .center
        self.addSubview(label)
        self.backgroundColor = .clear
        NSLayoutConstraint(item: self,
                           attribute: .top,
                           relatedBy: .equal,
                           toItem: label,
                           attribute: .top,
                           multiplier: 1.0,
                           constant: -verticalPadding).isActive = true
        NSLayoutConstraint(item: self,
                           attribute: .trailing,
                           relatedBy: .equal,
                           toItem: label,
                           attribute: .trailing,
                           multiplier: 1.0,
                           constant: horizontalPadding).isActive = true
        NSLayoutConstraint(item: self,
                           attribute: .bottom,
                           relatedBy: .equal,
                           toItem: label,
                           attribute: .bottom,
                           multiplier: 1.0,
                           constant: verticalPadding).isActive = true
        NSLayoutConstraint(item: self,
                           attribute: .leading,
                           relatedBy: .equal,
                           toItem: label,
                           attribute: .leading,
                           multiplier: 1.0,
                           constant: -horizontalPadding).isActive = true
        self.setNeedsLayout()
    }

    
    override func draw(_ rect: CGRect) {
        let circle = UIBezierPath.init(roundedRect: self.bounds, cornerRadius: horizontalPadding)
        chipColor.setFill()
        circle.fill()
        super.draw(rect)
    }
    
}

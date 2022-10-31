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

/// This `UIButton` subclass is the UIKit equivalent of the `OlvidButton` used in our SwiftUI structs.
final class ObvImageButton: UIButton {

    convenience init() {
        self.init(frame: .zero)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        layer.cornerRadius = 12.0
        layer.cornerCurve = .continuous
        resetColors()
        titleEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
    }
    
    
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        let newHeight = max(50.0, size.height)
        let newWidth = size.width
        return CGSize(width: newWidth, height: newHeight)
    }
    
    override var isEnabled: Bool {
        get {
            return super.isEnabled
        }
        set {
            super.isEnabled = newValue
            setup()
        }
    }
    

    override func setTitle(_ title: String?, for state: UIControl.State) {
        super.setTitle(title, for: state)
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).withSize(17).withDesign(.rounded)?.withSymbolicTraits(.traitBold) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).withSize(17)
        self.titleLabel?.font = UIFont(descriptor: fontDescriptor, size: 17)
    }
    

    func setImage(_ systemIcon: ObvSystemIcon, for state: UIControl.State) {
        self.setImage(UIImage(systemIcon: systemIcon), for: state)
    }
    
    
    override var isHighlighted: Bool {
        get { return super.isHighlighted }
        set { super.isHighlighted = newValue; resetColors() }
    }
    
    
    override var isSelected: Bool {
        get { return super.isSelected }
        set { super.isSelected = newValue; resetColors() }
    }

    
    internal func resetColors() {
        setTitleColor(.white, for: .normal)
        setTitleColor(.white.withAlphaComponent(0.2), for: .highlighted)
        adjustsImageWhenHighlighted = false
        if !isEnabled {
            self.backgroundColor = AppTheme.shared.colorScheme.secondarySystemFill
        } else {
            if isHighlighted || isSelected {
                self.tintColor = .white.withAlphaComponent(0.2)
                self.backgroundColor = AppTheme.shared.colorScheme.olvidLight.withAlphaComponent(0.2)
            } else {
                self.tintColor = .white
                self.backgroundColor = AppTheme.shared.colorScheme.olvidLight
            }
        }
    }

}

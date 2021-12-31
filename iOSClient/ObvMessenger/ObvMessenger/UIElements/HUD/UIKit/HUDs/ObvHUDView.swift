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


class ObvHUDView: UIView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        
        self.clipsToBounds = true
        self.layer.cornerRadius = 8

        backgroundColor = appTheme.colorScheme.secondarySystemFill
        
        if #available(iOS 13, *) {
            
            let blurEffect = UIBlurEffect(style: .systemThinMaterial)
            let blurEffectView = UIVisualEffectView(effect: blurEffect)
            blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blurEffectView.accessibilityIdentifier = "blurEffectView"
            self.addSubview(blurEffectView)
            
            let vibrancyEffect = UIVibrancyEffect(blurEffect: blurEffect, style: .fill)
            let vibrancyView = UIVisualEffectView(effect: vibrancyEffect)
            vibrancyView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            vibrancyView.accessibilityIdentifier = "vibrancyView"
            blurEffectView.contentView.addSubview(vibrancyView)
        }
        
    }
    
}

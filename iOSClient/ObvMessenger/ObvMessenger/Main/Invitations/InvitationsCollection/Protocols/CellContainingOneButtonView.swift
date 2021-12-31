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

protocol CellContainingOneButtonView {
    
    var oneButtonView: OneButtonView? { get }
    
    var buttonTitle: String? { get set }
    var buttonAction: (() -> Void)? { get set }
}

extension CellContainingOneButtonView {
    
    var buttonTitle: String? {
        get { return oneButtonView?.buttonTitle }
        set { oneButtonView?.buttonTitle = newValue }
    }
    
    var buttonAction: (() -> Void)? {
        get { return oneButtonView?.buttonAction }
        set { oneButtonView?.buttonAction = newValue }
    }

    func useLeadingButton() {
        oneButtonView?.useLeadingButton()
    }
    
    func useTrailingButton() {
        oneButtonView?.useTrailingButton()
    }

}

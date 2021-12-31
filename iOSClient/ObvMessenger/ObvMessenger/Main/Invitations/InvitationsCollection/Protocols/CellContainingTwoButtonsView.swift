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

import Foundation

protocol CellContainingTwoButtonsView {

    var twoButtonsView: TwoButtonsView! { get }
    
    var buttonTitle1: String { get set }
    var buttonTitle2: String { get set }
    
    var button1Action: (() -> Void)? { get set }
    var button2Action: (() -> Void)? { get set }
    
}

extension CellContainingTwoButtonsView {
    
    var buttonTitle1: String {
        get { return twoButtonsView.buttonTitle1 }
        set { twoButtonsView.buttonTitle1 = newValue }
    }

    var buttonTitle2: String {
        get { return twoButtonsView.buttonTitle2 }
        set { twoButtonsView.buttonTitle2 = newValue }
    }

    var button1Action: (() -> Void)? {
        get { return twoButtonsView.button1Action }
        set { twoButtonsView.button1Action = newValue }
    }

    var button2Action: (() -> Void)? {
        get { return twoButtonsView.button2Action }
        set { twoButtonsView.button2Action = newValue }
    }

}

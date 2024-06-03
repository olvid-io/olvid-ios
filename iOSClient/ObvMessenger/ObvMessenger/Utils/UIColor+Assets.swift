/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import SwiftUI

extension UIColor {
    
    //MARK: Default
    enum `Default`: String, AssetColorProtocol {
        
        case background = ""
        
    }
    
    //MARK: Group Creation
    enum GroupCreation: String, AssetColorProtocol {
        
        case background = "GroupCreationFlowBackgroundColor"
        case actionButton = "Blue01"
        case searchBackground = "searchBackground"
        case textFieldBackground = "Grey02"
        case textFieldPlaceholder = "Grey01"
        case divider = "Divider"
    }
}

//MARK: UIColor extension in order to get proper color thanks only to a string representation
extension UIColor {

    static func fromAsset(asset: AssetColorProtocol) -> UIColor? {
        return UIColor(named: asset.name)
    }
}

protocol AssetColorProtocol {
    
    var name: String { get }
    
    var uicolor: UIColor? { get }
    
    var color: Color { get }
}

extension AssetColorProtocol {
    
    var uicolor: UIColor? {
        UIColor.fromAsset(asset: self)
    }

    var color: Color {
        Color(uicolor ?? .clear)
    }
}

extension AssetColorProtocol where Self: RawRepresentable, Self.RawValue == String {
    
    var name: String { self.rawValue }
    
}


/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import UIKit

final class ContextMenuContainerViewWrapper: PrivateObjectWrapper<UIView, ContextMenuContainerViewWrapper.EncodedString> {
    
    enum EncodedString: String, PrivateObjectWrappingStringRepresentable {
        
        case className
        
        var encodedString: String {
            switch self {
            case .className:
                // _UIContextMenuContainerView
                return "X1VJQ29udGV4dE1lbnVDb250YWluZXJWaWV3"
            }
        }
        
    }
    
    
    @available(iOS 16, *)
    var contextMenuPlatterTransitionViewWrapper: ContextMenuPlatterTransitionViewWrapper? {
        guard let view = self.wrappedObject else { return nil }
        return view.subviews.reduce(nil) { $0 ?? .init(objectToWrap: $1) }
    }
    
    
    var contextMenuSharedRootView: UIView? {
        guard let view = self.wrappedObject else { return nil }
        return view.subviews.first {
            !($0 is UIVisualEffectView)
            && $0.subviews.count > 0
            && $0.constraints.count > 0
        }
    }
    
}

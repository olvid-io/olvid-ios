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

@available(iOS 16, *)
final class ContextMenuPlatterTransitionViewWrapper: PrivateObjectWrapper<UIView, ContextMenuPlatterTransitionViewWrapper.EncodedString> {
    
    enum EncodedString: String, PrivateObjectWrappingStringRepresentable {

        case className
        
        var encodedString: String {
            switch self {
            case .className:
                // _UIContextMenuPlatterTransitionView
                return "X1VJQ29udGV4dE1lbnVQbGF0dGVyVHJhbnNpdGlvblZpZXc="
            }
        }
        
    }
    
    
    var contextMenuViewWrapper: ContextMenuViewWrapper? {
        guard let view = self.wrappedObject else { return nil }
        return view.subviews.reduce(nil) { $0 ?? .init(objectToWrap: $1) }
    }
    
    
    var morphingPlatterViewWrapper: MorphingPlatterViewWrapper? {
        guard let view = self.wrappedObject else { return nil }
        return view.subviews.reduce(nil) { $0 ?? .init(objectToWrap: $1) }
    }
    
}


final class ContextMenuViewWrapper: PrivateObjectWrapper<UIView, ContextMenuViewWrapper.EncodedString> {
    
    enum EncodedString: String, PrivateObjectWrappingStringRepresentable {

        case className
        
        var encodedString: String {
            switch self {
            case .className:
                // _UIContextMenuView
                return "X1VJQ29udGV4dE1lbnVWaWV3"
            }
        }
    }
    
}


final class MorphingPlatterViewWrapper: PrivateObjectWrapper<UIView, MorphingPlatterViewWrapper.EncodedString> {
    
    enum EncodedString: String, PrivateObjectWrappingStringRepresentable {
        
        case className
        
        var encodedString: String {
            switch self {
            case .className:
                // _UIMorphingPlatterView
                return "X1VJTW9ycGhpbmdQbGF0dGVyVmlldw=="
            }
        }
        
    }
    
    
    var platterSoftShadowViewWrapper: PlatterSoftShadowViewWrapper? {
        guard let view = self.wrappedObject else { return nil }
        return view.subviews.reduce(nil) { $0 ?? .init(objectToWrap: $1) }
    }
    
}


final class PlatterSoftShadowViewWrapper: PrivateObjectWrapper<UIView, PlatterSoftShadowViewWrapper.EncodedString> {
    
    enum EncodedString: String, PrivateObjectWrappingStringRepresentable {
        
        case className
        
        var encodedString: String {
            switch self {
            case .className:
                // _UIPlatterSoftShadowView
                return "X1VJUGxhdHRlclNvZnRTaGFkb3dWaWV3"
            }
        }
        
    }
    
}

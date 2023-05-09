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
  

import Foundation
import SwiftUI


// MARK: - SwiftUINewCircledInitialsView
public struct CircledInitialsView: View {
    public enum Size {
        case medium
        case small
        
        var sideLength: CGFloat {
            switch self {
            case .medium: return 60.0
            case .small: return 30.0
            }
        }
        
        func paddingForIcon(_ icon: SystemIcon) -> EdgeInsets {
            switch self {
            case .medium:
                switch icon {
                case .lock(.fill, .none):
                    return EdgeInsets(top: 20.0, leading: 20.0, bottom: 20.0, trailing: 20.0)
                default:
                    return EdgeInsets(top: 12.0, leading: 12.0, bottom: 12.0, trailing: 12.0)
                }
            case .small:
                return EdgeInsets(top: 4.0, leading: 4.0, bottom: 4.0, trailing: 4.0)
            }
        }
        
        var initialsFontSize: CGFloat {
            switch self {
            case .medium: return 30.0
            case .small: return 15.0
            }
        }
    }

    let configuration: CircledInitialsConfiguration
    let size: Size
    
    public init(configuration: CircledInitialsConfiguration, size: Size) {
        self.configuration = configuration
        self.size = size
    }

    public var body: some View {
        RoundedClipView(configuration: configuration, size: size)
            .frame(width: size.sideLength, height: size.sideLength)
            .background(Color(configuration.backgroundColor(appTheme: AppTheme.shared)))
            .clipShape(Circle())
    }
}


// MARK: - RoundedClipView
fileprivate struct RoundedClipView: View {

    let configuration: CircledInitialsConfiguration
    let size: CircledInitialsView.Size

    var body: some View {
        switch configuration.contentType {
        case .icon(let icon, let color): return AnyView(createIconView(using: icon, color: color))
        case .initial(let text, let color): return AnyView(createInitialView(using: text, color: color))
        case .picture(let image): return AnyView(createPictureView(using: image))
        case .none: return AnyView(Text(""))
        }
    }
    
    private func createIconView(using icon: SystemIcon, color: UIColor) -> some View {
        return Image(systemIcon: icon)
            .resizable()
            .scaledToFit()
            .foregroundColor(Color(color))
            .padding(size.paddingForIcon(icon))
    }
    
    private func createInitialView(using initials: String, color: UIColor) -> some View {
        return Text(initials)
            .font(.system(size: size.initialsFontSize, weight: .black, design: .rounded))
            .foregroundColor(Color(color))
            .multilineTextAlignment(.center)
        
    }
    
    private func createPictureView(using uiImage: UIImage) -> some View {
        return Image(uiImage: uiImage)
            .resizable()
            .scaledToFit()
    }
}

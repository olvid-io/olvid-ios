/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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


import SwiftUI
import ObvDesignSystem
import ObvSettings
import ObvSystemIcon


@MainActor
public protocol InitialCircleViewNewModelProtocol: ObservableObject {
    var circledInitialsConfiguration: CircledInitialsConfiguration { get }
}


/// 2023-07-13: Replaces InitialCircleView and ProfilePictureView.
public struct InitialCircleViewNew<Model: InitialCircleViewNewModelProtocol>: View {
    
    @ObservedObject var model: Model
    let state: State

    public init(model: Model, state: State) {
        self.model = model
        self.state = state
    }
    
    public enum State {
        case circleDiameter(diameter: CGFloat)
        case cornerRadius(diameter: CGFloat, cornerRadius: CGFloat)
        
        var diameter: CGFloat {
            switch self {
            case .circleDiameter(diameter: let diameter): return diameter
            case .cornerRadius(diameter: let diameter, cornerRadius: _): return diameter
            }
        }
        
        var cornerRadius: CGFloat {
            switch self {
            case .circleDiameter: return 0
            case .cornerRadius(diameter: _, cornerRadius: let cornerRadius): return cornerRadius
            }
        }
        
        func shape() -> UniversalShape {
            switch self {
                case .circleDiameter:
                UniversalShape(Circle())
                case .cornerRadius(_, let cornerRadius):
                UniversalShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            
        }
    }
    
    private var iconSizeAdjustement: CGFloat {
        switch model.circledInitialsConfiguration.icon {
        case .person: return 2
        case .person3Fill: return 3
        case .personFillXmark: return 2
        default: return 1
        }
    }

    public var body: some View {
        Group {
            if let profilePicture = model.circledInitialsConfiguration.photo {
                Image(uiImage: profilePicture)
                    .resizable()
                    .scaledToFill() // 2023-09-07 was .scaledToFit()
                    .frame(width: state.diameter, height: state.diameter)
                    .clipShape(state.shape())
            } else {
                ZStack {
                    state.shape()
                        .frame(width: state.diameter, height: state.diameter)
                        .foregroundColor(Color(model.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared)))
                    if let text = model.circledInitialsConfiguration.initials?.text {
                        Text(text)
                            .font(Font.system(size: state.diameter/2.0, weight: .black, design: .rounded))
                            .foregroundColor(Color(model.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)))
                    } else {
                        Image(systemIcon: model.circledInitialsConfiguration.icon)
                            .font(Font.system(size: state.diameter/iconSizeAdjustement, weight: .semibold, design: .default))
                            .foregroundColor(Color(model.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)))
                    }
                }
            }
        }
        .overlay(
            Image(systemIcon: .checkmarkShieldFill)
                .font(.system(size: (state.diameter) / 4))
                .foregroundColor(model.circledInitialsConfiguration.showGreenShield ? Color(AppTheme.shared.colorScheme.green) : .clear),
            alignment: .topTrailing
        )
        .overlay(
            Image(systemIcon: .exclamationmarkShieldFill)
                .font(.system(size: (state.diameter) / 2))
                .foregroundColor(model.circledInitialsConfiguration.showRedShield ? .red : .clear),
            alignment: .center
        )
    }
    
}

public struct UniversalShape: Shape, Sendable {
    
    public var make: @Sendable (CGRect, inout Path) -> ()

    public init(_ make: @Sendable @escaping (CGRect, inout Path) -> ()) {
        self.make = make
    }

    public init<S: Shape>(_ shape: S) {
        self.make = { rect, path in
            path = shape.path(in: rect)
        }
    }

    public func path(in rect: CGRect) -> Path {
        return Path { [make] in make(rect, &$0) }
    }
}


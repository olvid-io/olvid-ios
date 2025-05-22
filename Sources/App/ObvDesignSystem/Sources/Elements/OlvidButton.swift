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
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import ObvSystemIcon

fileprivate extension OlvidButton.Style {

    func backgroundColor(isEnabled: Bool) -> Color {
        guard isEnabled else { return Color(AppTheme.shared.colorScheme.quaternarySystemFill) }
        switch self {
        case .blue: return Color(AppTheme.shared.colorScheme.olvidLight)
        case .white: return .white
        case .standard: return Color(AppTheme.shared.colorScheme.systemFill)
        case .standardWithBlueText: return Color(AppTheme.shared.colorScheme.systemFill)
        case .standardAlt: return Color.white.opacity(0.2)
        case .clearBackgroundAndWhiteForeground: return .clear
        case .green: return .green
        case .red: return .red
        case .redOnTransparentBackground: return .clear
        case .text: return .clear
        }
    }

    func foregroundColor(isEnabled: Bool) -> Color {
        guard isEnabled else { return Color(AppTheme.shared.colorScheme.quaternaryLabel) }
        switch self {
        case .blue: return .white
        case .white: return Color(AppTheme.shared.colorScheme.olvidLight)
        case .standard: return Color(AppTheme.shared.colorScheme.secondaryLabel)
        case .standardWithBlueText: return Color(AppTheme.shared.colorScheme.olvidLight)
        case .standardAlt: return .white
        case .clearBackgroundAndWhiteForeground: return .white
        case .green: return .white
        case .red: return .white
        case .redOnTransparentBackground: return .red
        case .text: return Color(AppTheme.shared.colorScheme.olvidLight)
        }
    }
}

/// This SwiftUI view represents a large blue or standard button with rounded corners.
/// This `View` is the equivalent of the `ObvImageButton` in UIKit
public struct OlvidButton: View {
    
    static let height: CGFloat = 50
    static let cornerRadius: CGFloat = 12

    public enum Style {
        case blue
        case white
        case standard
        case standardWithBlueText
        case standardAlt
        case clearBackgroundAndWhiteForeground
        case green
        case red
        case redOnTransparentBackground
        case text
    }
    
    let style: Style
    let title: Text
    let systemIcon: SystemIcon?
    let action: () -> Void
    let cornerRadius: CGFloat = 12.0

    @Environment(\.isEnabled) var isEnabled

    public init(olvidButtonAction: OlvidButtonAction) {
        self.style = olvidButtonAction.style
        self.title = olvidButtonAction.title
        self.systemIcon = olvidButtonAction.systemIcon
        self.action = olvidButtonAction.action
    }
    
    public init(style: Style, title: Text, systemIcon: SystemIcon? = nil, action: @escaping () -> Void) {
        self.style = style
        self.title = title
        self.systemIcon = systemIcon
        self.action = action
    }

    private func buttonContent<T: View>(_ content: () -> T) -> some View {
        ObvCardView(backgroundColor: style.backgroundColor(isEnabled: isEnabled), padding: 0, cornerRadius: cornerRadius) {
            content()
                .font(.system(size: 17, weight: .semibold, design: .default))
                .padding(.horizontal, 4)
                .frame(height: OlvidButton.height)
                .frame(minWidth: 0,
                       maxWidth: .infinity,
                       minHeight: 0,
                       idealHeight: OlvidButton.height,
                       maxHeight: OlvidButton.height,
                       alignment: .center)
                .foregroundColor(style.foregroundColor(isEnabled: isEnabled))
        }
    }

    public var body: some View {
        Button(action: action) {
            buttonContent {
                Label(
                    title: { title },
                    icon: { systemIcon != nil ? Image(systemIcon: systemIcon!) : nil }
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}


public struct OlvidButtonAction: Identifiable {
    public let id = UUID()
    let action: () -> Void
    let title: Text
    let systemIcon: SystemIcon
    let style: OlvidButton.Style
    
    public init(action: @escaping () -> Void, title: Text, systemIcon: SystemIcon, style: OlvidButton.Style = .blue) {
        self.action = action
        self.title = title
        self.systemIcon = systemIcon
        self.style = style
    }
    
}

struct OlvidButtonSquare: View {

    let style: OlvidButton.Style
    let systemIcon: SystemIcon
    let action: () -> Void
    @Environment(\.isEnabled) var isEnabled
    
    var body: some View {
        Button(action: action) {
            Image(systemIcon: systemIcon)
                .font(.system(size: 17, weight: .semibold, design: .default))
                .frame(width: OlvidButton.height, height: OlvidButton.height)
                .foregroundColor(style.foregroundColor(isEnabled: isEnabled))
                .background(style.backgroundColor(isEnabled: isEnabled))
                .cornerRadius(OlvidButton.cornerRadius)
        }.fixedSize(horizontal: true, vertical: true)
    }
    
}


@available(iOS 14, *)
struct OlvidButton_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            Group {
                OlvidButton(style: .blue, title: Text("Share"), action: {})
                    .padding()
                    .previewLayout(.sizeThatFits)
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .light)
                    .previewDisplayName("Blue example in light mode")
                OlvidButton(style: .standard, title: Text("Share"), action: {})
                    .padding()
                    .previewLayout(.sizeThatFits)
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .light)
                    .previewDisplayName("Standard example in light mode")
                OlvidButton(style: .blue, title: Text("Share"), action: {})
                    .padding()
                    .previewLayout(.sizeThatFits)
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .dark)
                    .previewDisplayName("Blue example in dark mode")
                OlvidButton(style: .standard, title: Text("Share"), action: {})
                    .padding()
                    .previewLayout(.sizeThatFits)
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .dark)
                    .previewDisplayName("Standard example in dark mode")
                OlvidButton(style: .blue, title: Text("Share"), systemIcon: .squareAndArrowUp, action: {})
                    .padding()
                    .previewLayout(.sizeThatFits)
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .light)
                    .previewDisplayName("Blue example in light mode")
                OlvidButton(style: .blue, title: Text("Share"), systemIcon: .squareAndArrowUp, action: {})
                    .disabled(true)
                    .padding()
                    .previewLayout(.sizeThatFits)
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .light)
                    .previewDisplayName("Disabled example in light mode")
                OlvidButton(style: .standard, title: Text("Share"), systemIcon: .squareAndArrowUp, action: {})
                    .disabled(true)
                    .padding()
                    .previewLayout(.sizeThatFits)
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .dark)
                    .previewDisplayName("Disabled example in light mode")
                OlvidButtonSquare(style: .blue, systemIcon: .gearshapeFill, action: {})
                    .padding()
                    .previewLayout(.sizeThatFits)
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .light)
                    .previewDisplayName("Blue example in light mode without label")
                OlvidButton(style: .green, title: Text("PUBLISH"), systemIcon: .checkmarkCircle, action: {})
                    .disabled(false)
                    .padding()
                    .previewLayout(.sizeThatFits)
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .light)
                    .previewDisplayName("Green example in light mode")
                OlvidButton(style: .green, title: Text("PUBLISH"), systemIcon: .checkmarkCircle, action: {})
                    .disabled(false)
                    .padding()
                    .previewLayout(.sizeThatFits)
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .dark)
                    .previewDisplayName("Green example in dark mode")
            }
            Group {
                OlvidButton(style: .red, title: Text("CANCEL"), systemIcon: .xmarkCircle, action: {})
                    .disabled(false)
                    .padding()
                    .previewLayout(.sizeThatFits)
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .dark)
                    .previewDisplayName("Red example in dark mode")
                OlvidButton(style: .red, title: Text("CANCEL"), systemIcon: .xmarkCircle, action: {})
                    .disabled(false)
                    .padding()
                    .previewLayout(.sizeThatFits)
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .light)
                    .previewDisplayName("Red example in light mode")
                OlvidButtonSquare(style: .redOnTransparentBackground, systemIcon: .trash, action: {})
                    .padding()
                    .previewLayout(.sizeThatFits)
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .light)
                    .previewDisplayName("Blue example in light mode without label")
                OlvidButton(style: .text, title: Text("Save"), action: {})
                    .padding()
                    .previewLayout(.sizeThatFits)
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .light)
                    .previewDisplayName("Text example in light mode")
            }
        }
    }
}

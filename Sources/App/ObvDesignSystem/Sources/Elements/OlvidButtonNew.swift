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


public enum OlvidButtonStyle {
    case glassOrBorderedProminent
    case glassOrBordered
    case borderless
}

public struct OlvidButtonNew<Label>: View where Label : View {
    
    public init(action: @escaping @MainActor () -> Void, verticalPadding: CGFloat = 8, style: OlvidButtonStyle = .glassOrBorderedProminent, @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.label = label
        self.verticalPadding = verticalPadding
        self.style = style
    }
        
    let action: () -> Void
    let label: () -> Label
    let verticalPadding: CGFloat
    let style: OlvidButtonStyle
    
    public var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                label()
                    .padding(.vertical, verticalPadding)
            }
            .buttonStyleObv(style: style)
            .buttonSizing(.flexible)
        } else {
            Button(action: action) {
                HStack {
                    Spacer(minLength: 0)
                    label()
                    Spacer(minLength: 0)
                }
                .padding(.vertical, verticalPadding)
            }
            .buttonStyleObv(style: style)
        }
    }
    
}


private struct ObvButtonStyle: ViewModifier {
        
    let style: OlvidButtonStyle
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            switch style {
            case .glassOrBorderedProminent:
                content
                    .buttonStyle(.glassProminent)
            case .glassOrBordered:
                content
                    .buttonStyle(.glass)
            case .borderless:
                content
                    .buttonStyle(.borderless)
            }
        } else {
            switch style {
            case .glassOrBorderedProminent:
                content
                    .buttonStyle(.borderedProminent)
            case .glassOrBordered:
                content
                    .buttonStyle(.bordered)
            case .borderless:
                content
                    .buttonStyle(.borderless)
            }
        }
    }
    
}


extension View {
    
    func buttonStyleObv(style: OlvidButtonStyle) -> some View {
        self.modifier(ObvButtonStyle(style: style))
    }
    
}


#if DEBUG

#Preview {
    VStack {
        OlvidButtonNew(action: {}) {
            Label(title: { Text(verbatim: "Button title") }, icon: { Image(systemIcon: .airpods) })
        }
        OlvidButtonNew(action: {}, style: .glassOrBordered) {
            Label(title: { Text(verbatim: "Button title") }, icon: { Image(systemIcon: .airpods) })
        }
        OlvidButtonNew(action: {}, style: .borderless) {
            Label(title: { Text(verbatim: "Button title") }, icon: { Image(systemIcon: .airpods) })
        }
    }
    .padding()
}

#endif

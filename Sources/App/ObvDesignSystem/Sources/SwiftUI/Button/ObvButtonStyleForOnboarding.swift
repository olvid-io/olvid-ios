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



public struct ObvButtonStyleForOnboarding: PrimitiveButtonStyle {
    
    public init() {}
    
    @Environment(\.colorScheme) var colorScheme

    private var tintColor: Color {
        switch colorScheme {
        case .light:
            return .white
        case .dark:
            return Color(UIColor.systemFill)
        @unknown default:
            return .white
        }
    }
    
    private let lineWidth: CGFloat = 1
    private let cornerRadius: CGFloat = 12
    
    public func makeBody(configuration: Configuration) -> some View {
        Button(action: configuration.trigger) {
            HStack {
                configuration.label
                    .padding(.vertical)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemIcon: .chevronRight)
            }
        }
        .buttonStyle(.bordered)
        .tint(tintColor)
        .foregroundStyle(.primary)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(UIColor.lightGray), lineWidth: lineWidth)
            )
        .padding(.all, lineWidth)
    }
    
}


// - MARK: Previews

private struct TestButtonView: View {
    var body: some View {
        VStack {
            Button {
                
            } label: {
                Text(verbatim: "This is a test")
            }
            .buttonStyle(ObvButtonStyleForOnboarding())
            
            Button {
                
            } label: {
                Text(verbatim: "This is a test")
                    .padding(.vertical)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemIcon: .chevronRight)
            }
            .buttonStyle(.borderedProminent)

        }
        .padding()
    }
}

#Preview {
    TestButtonView()
}

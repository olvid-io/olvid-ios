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

import SwiftUI

@available(iOS 13.0, *)
struct RoundedButtonView: View {
    var size: CGFloat = 60
    let icon: AudioInputIcon
    let text: String?
    let backgroundColor: Color
    let backgroundColorWhenOn: Color
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        VStack {
            switch icon {
            case .sf(let systemName):
                Button(action: action) {
                    Circle()
                        .fill(isOn ? backgroundColorWhenOn : backgroundColor)
                        .frame(width: size, height: size)
                        .overlay(Image(systemName: systemName)
                                    .font(Font.system(size: size*0.4).bold()))
                        .foregroundColor(.white)
                }
            case .png(let name):
                Button(action: action) {
                    Circle()
                        .fill(isOn ? backgroundColorWhenOn : backgroundColor)
                        .frame(width: size, height: size)
                        .overlay(
                            Image(name)
                                .renderingMode(.template)
                                .resizable()
                                .foregroundColor(.white)
                                .frame(width: size * 0.5, height: size * 0.5)
                        )
                        .foregroundColor(.white)
                }
            }
            if let text = text {
                Text(text)
                    .font(.footnote)
                    .foregroundColor(Color(.secondaryLabel))
            }
        }
    }
}


@available(iOS 13.0, *)
struct CallSettingButtonStyle: PrimitiveButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration
            .label
            .gesture(TapGesture().onEnded({ _ in configuration.trigger() }))
            .animation(.easeInOut(duration: 0.2))
    }

}


// MARK: - Previews

@available(iOS 13.0, *)
struct RoundedButtonView_Previews: PreviewProvider {

    fileprivate static let mockObject = MockObject()

    static var previews: some View {
        Group {
            HStack {
                RoundedButtonView(icon: .sf("mic.slash.fill"),
                                  text: "mute",
                                  backgroundColor: Color(.systemFill),
                                  backgroundColorWhenOn: Color(.systemFill),
                                  isOn: false,
                                  action: defaultAction)
                    .padding()
                RoundedButtonView(icon: .sf("mic.slash.fill"),
                                  text: "mute",
                                  backgroundColor: Color(.systemFill),
                                  backgroundColorWhenOn: Color(AppTheme.shared.colorScheme.olvidLight),
                                  isOn: true,
                                  action: defaultAction)
                    .padding()
            }
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Static example in light mode")
            HStack {
                RoundedButtonView(size: 30,
                                  icon: .sf("minus"),
                                  text: nil,
                                  backgroundColor: Color(.red),
                                  backgroundColorWhenOn: Color(.red),
                                  isOn: false,
                                  action: defaultAction)
                    .padding()
            }
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Static example (2) in light mode")
            HStack {
                RoundedButtonView(icon: .sf("mic.slash.fill"),
                                  text: "mute",
                                  backgroundColor: Color(.systemFill),
                                  backgroundColorWhenOn: Color(.systemFill),
                                  isOn: false,
                                  action: defaultAction)
                    .padding()
                RoundedButtonView(icon: .sf("mic.slash.fill"),
                                  text: "mute",
                                  backgroundColor: Color(.systemFill),
                                  backgroundColorWhenOn: Color(AppTheme.shared.colorScheme.olvidLight),
                                  isOn: true,
                                  action: defaultAction)
                    .padding()
            }
            .previewLayout(.sizeThatFits)
            .background(Color(.systemBackground))
            .environment(\.colorScheme, .dark)
            .previewDisplayName("Static example in dark mode")
            RoundedButtonMockView(object: MockObject())
                .buttonStyle(CallSettingButtonStyle())
                .padding()
                .previewLayout(.sizeThatFits)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .light)
                .previewDisplayName("Dynamic example in light mode with call setting style")
            RoundedButtonMockView(object: MockObject())
                .buttonStyle(CallSettingButtonStyle())
                .padding()
                .previewLayout(.sizeThatFits)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
                .previewDisplayName("Dynamic example in dark mode with call setting style")
            HStack {
                RoundedButtonView(icon: .png("bluetooth"),
                                  text: "audio",
                                  backgroundColor: Color(.systemFill),
                                  backgroundColorWhenOn: Color(.systemFill),
                                  isOn: false,
                                  action: defaultAction)
                    .padding()
                RoundedButtonView(icon: .png("bluetooth"),
                                  text: "audio",
                                  backgroundColor: Color(.systemFill),
                                  backgroundColorWhenOn: Color(AppTheme.shared.colorScheme.olvidLight),
                                  isOn: true,
                                  action: defaultAction)
                    .padding()
            }
            .previewLayout(.sizeThatFits)
            .background(Color(.systemBackground))
            .environment(\.colorScheme, .dark)
            .previewDisplayName("Static bluetooth example in dark mode")
        }
    }

    private static func defaultAction() {
        debugPrint("Button tapped")
    }
}


@available(iOS 13.0, *)
fileprivate class MockObject: ObservableObject {
    @Published private(set) var isOn: Bool = false
    func toggle() {
        debugPrint("Toggle!")
        isOn.toggle()
    }
}


@available(iOS 13.0, *)
fileprivate struct RoundedButtonMockView: View {
    @ObservedObject var object: MockObject
    var body: some View {
        RoundedButtonView(icon: .sf("mic.slash.fill"),
                          text: object.isOn ? "unmute" : "mute",
                          backgroundColor: Color(.systemFill),
                          backgroundColorWhenOn: Color(AppTheme.shared.colorScheme.olvidLight),
                          isOn: object.isOn,
                          action: object.toggle)
    }
}

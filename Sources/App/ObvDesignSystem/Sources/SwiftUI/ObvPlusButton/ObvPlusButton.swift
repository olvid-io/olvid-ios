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

@MainActor
public protocol ObvPlusButtonActionsDelegate {
    func userTappedObvPlusButton()
}


/// This is the implementation of the "plus" button that shall be used on all tabs, eventually.
/// For now (2025-09-04), it is only used on the first tab, i.e., on the list of all recent discussions.
public struct ObvPlusButton: View {
    
    let actions: ObvPlusButtonActionsDelegate
    
    public init(actions: ObvPlusButtonActionsDelegate, hasAppeared: Bool = false) {
        self.actions = actions
    }
    
    public var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Group {
                    if #available(iOS 26.0, *) {
                        ObvPlusButtonInternalIOS26(actions: actions)
                    } else if #available(iOS 17.0, *){
                        ObvPlusButtonInternalIOS17(actions: actions)
                    } else {
                        ObvPlusButtonInternalIOS16(actions: actions)
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
    }
}

/// A glass-morphic button for iOS 26+, avoiding `.glassProminent` to prevent unwanted "capsule" visual effects on tap.
///
/// Uses a standard `Button` to ensure taps are captured within the button’s shape (not the view beneath),
/// guaranteeing the button’s `action` is always executed. Inspired by techniques from
/// [WWDC25 session 323](https://developer.apple.com/videos/play/wwdc2025/323/) (~19:30).
@available(iOS 26.0, *)
private struct ObvPlusButtonInternalIOS26: View {
    
    let actions: ObvPlusButtonActionsDelegate
    
    private let diameter: CGFloat = 61
    private let symbolSize: CGFloat = 28

    var body: some View {
        Button(action: actions.userTappedObvPlusButton) {
            Image(systemIcon: .plus)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
        }
        .buttonSizing(.fitted)
        .buttonBorderShape(.circle)
        .glassEffect(.regular.tint(.accentColor).interactive())
    }
    
}


/// A `.borderedProminent` button styled for iOS 17 and iOS 18, visually matching the design of `ObvPlusButtonInternalIOS26` on iOS 26.
///
/// The button's dimensions and styling were experimentally adjusted to align as closely as possible
/// with the appearance and proportions of the iOS 26 implementation.
@available(iOS 17.0, *)
private struct ObvPlusButtonInternalIOS17: View {
    
    let actions: ObvPlusButtonActionsDelegate
    
    private let diameter: CGFloat = 44
    private let symbolSize: CGFloat = 28

    var body: some View {
        Button(action: actions.userTappedObvPlusButton) {
            Image(systemIcon: .plus)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .shadow(color: .black.opacity(0.2), radius: 10) // Default color is black with 0.33 opacity
        .offset(x: 5)
    }
    
}


/// A `.borderedProminent` button styled for iOS 16, visually matching the design of `ObvPlusButtonInternalIOS26` on iOS 26.
///
/// The button's dimensions and styling were experimentally adjusted to align as closely as possible
/// with the appearance and proportions of the iOS 26 implementation.
private struct ObvPlusButtonInternalIOS16: View {
    
    let actions: ObvPlusButtonActionsDelegate
    
    private let diameter: CGFloat = 44
    private let symbolSize: CGFloat = 28

    var body: some View {
        Button(action: actions.userTappedObvPlusButton) {
            Image(systemIcon: .plus)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
        }
        .buttonStyle(.borderedProminent)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.2), radius: 10) // Default color is black with 0.33 opacity
        .offset(x: 5)
    }
    
}

// MARK: - Previews

#if DEBUG

private final class ActionsForPreviews: ObvPlusButtonActionsDelegate {
    
    func userTappedObvPlusButton() {
        print("Button tapped")
    }
    
}

private enum FakeCategory: String, CaseIterable, Identifiable {
    case item1, item2, item3, item4, item5, item6, item7, item8, item9, item10, item11, item12, item17, item18, item19, item20, item21, item22, item23, item24, item25, item26, item27, item28, item29, item30, item31, item32, item33, item34, item35, item36, item37, item38, item39, item40, item41, item42, item43, item44, item45, item46, item47, item48, item49, item50
    var id: String { return self.rawValue }
}

@MainActor
private let actionsForPreviews = ActionsForPreviews()


private struct FakeListView: View {
    
    let actions: ObvPlusButtonActionsDelegate
    
    var body: some View {
        NavigationStack {
            ZStack {
                List(FakeCategory.allCases) { category in
                    NavigationLink(value: category) {
                        HStack {
                            Text(verbatim: "Cell \(category.rawValue)")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                }
                .navigationTitle(Text(verbatim: "Test"))
                .navigationDestination(for: FakeCategory.self) { category in
                    FakeCategoryView(category: category)
                }
                ObvPlusButton(actions: actionsForPreviews)
            }
        }
    }
}


private struct FakeCategoryView: View {
    
    let category: FakeCategory
    
    var body: some View {
        Text(verbatim: "Category: \(category.rawValue)")
    }
    
}


#Preview {
    FakeListView(actions: actionsForPreviews)
}


#endif // DEBUG

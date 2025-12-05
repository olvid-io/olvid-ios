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
import ObvSystemIcon
import ObvDesignSystem


protocol NewAutorisationRequesterViewActionsProtocol: AnyObject {
    func requestAutorisation(now: Bool, for autorisationCategory: NewAutorisationRequesterViewController.AutorisationCategory) async
}


public struct NewAutorisationRequesterView: View {

    let autorisationCategory: NewAutorisationRequesterViewController.AutorisationCategory
    let actions: NewAutorisationRequesterViewActionsProtocol

    private var textTitle: String {
        switch autorisationCategory {
        case .localNotifications:
            return String(localizedInThisBundle: "TITLE_NEVER_MISS_A_MESSAGE")
        case .recordPermission:
            return String(localizedInThisBundle: "TITLE_NEVER_MISS_A_SECURE_CALL")
        }
    }
    
    private func userTappedSkipButton() {
        Task(priority: .userInitiated) {
            await actions.requestAutorisation(now: false, for: autorisationCategory)
        }
    }
    
    private func userTappedAllowButton() {
        Task(priority: .userInitiated) {
            await actions.requestAutorisation(now: true, for: autorisationCategory)
        }
    }
    
    private var showSkipButton: Bool {
        switch autorisationCategory {
        case .localNotifications:
            return true
        case .recordPermission:
            return false
        }
    }
    
    @ViewBuilder
    private var texts: some View {
        let columns = [GridItem(.fixed(30)), GridItem(.flexible())]
        LazyVGrid(columns: columns, alignment: .leading) {
            
            switch autorisationCategory {
            case .localNotifications:
                
                ExplanationImage(systemIcon: .textBubbleFill, color: .purple)
                ExplanationText(text: String(localizedInThisBundle: "LOCAL_NOTIFICATIONS_TEXT_1"))
                    .padding(.bottom)

                ExplanationImage(systemIcon: .personCropCircleBadgePlus, color: .yellow)
                ExplanationText(text: String(localizedInThisBundle: "LOCAL_NOTIFICATIONS_TEXT_2"))
                    .padding(.bottom)

                ExplanationImage(systemIcon: .gearshapeFill, color: .green)
                ExplanationText(text: String(localizedInThisBundle: "LOCAL_NOTIFICATIONS_TEXT_3"))
                    .padding(.bottom)
                
            case .recordPermission:
                
                ExplanationImage(systemIcon: .phoneFill, color: .purple)
                ExplanationText(text: String(localizedInThisBundle: "RECORD_PERMISSION_TEXT_1"))
                    .padding(.bottom)
                
                ExplanationImage(systemIcon: .micFill, color: .yellow)
                ExplanationText(text: String(localizedInThisBundle: "RECORD_PERMISSION_TEXT_2"))
                    .padding(.bottom)
                
                ExplanationImage(systemIcon: .checkmarkShieldFill, color: .green)
                ExplanationText(text: String(localizedInThisBundle: "RECORD_PERMISSION_TEXT_3"))
                    .padding(.bottom)
                
            }
            

        }
        .font(.body)
    }
    
    public var body: some View {
        VStack {
            
            ScrollView {
                VStack {
                    
                    ObvHeaderView(title: textTitle, subtitle: nil)
                        .padding(.bottom, 20)

                    texts
                        .padding()
            
                    MainButton(autorisationCategory: autorisationCategory, action: userTappedAllowButton)
                        .padding()

                }
            }
            
            // Show a "skip" button bellow the scroll view
            
            Spacer()
            
            if showSkipButton {
                HStack {
                    Spacer()
                    Button("MAYBE_LATER".localizedInThisBundle, action: userTappedSkipButton)
                        .font(.callout)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }

        }.navigationBarBackButtonHidden(true)
    }
    
}


// MARK: - Internal view for main button

private struct MainButton: View {
    
    let autorisationCategory: NewAutorisationRequesterViewController.AutorisationCategory
    let action: () -> Void

    private var title: String {
        switch autorisationCategory {
        case .localNotifications:
            return String(localizedInThisBundle: "BUTON_TITLE_ACTIVATE_NOTIFICATION")
        case .recordPermission:
            return String(localizedInThisBundle: "BUTON_TITLE_REQUEST_RECORD_PERMISSION")
        }
    }
    
    private var icon: SystemIcon {
        switch autorisationCategory {
        case .localNotifications:
            return .envelopeBadge
        case .recordPermission:
            return .mic
        }
    }
    
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Label(title: { Text(title) }, icon: { Image(systemIcon: icon) })
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .buttonSizing(.flexible)
            .tint(.green)
        } else {
            Button(action: action) {
                HStack {
                    Spacer(minLength: 0)
                    Label(title: { Text(title) }, icon: { Image(systemIcon: icon) })
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
    }
    
}


// MARK: - Internal view

private struct ExplanationImage: View {
 
    let systemIcon: SystemIcon
    let color: Color
    
    var body: some View {
        VStack {
            Image(systemIcon: systemIcon)
                .foregroundColor(color)
            Spacer(minLength: 0)
        }
    }
    
}

// MARK: - Internal view

private struct ExplanationText: View {
    
    let text: String
    
    var body: some View {
        VStack {
            HStack {
                Text(text)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
    }
    
}

#if DEBUG


@MainActor
private final class ActionsForPreviews: NewAutorisationRequesterViewActionsProtocol {
    func requestAutorisation(now: Bool, for autorisationCategory: NewAutorisationRequesterViewController.AutorisationCategory) async {}
}

@MainActor
private let actions = ActionsForPreviews()

#Preview("Record (en)") {
    NewAutorisationRequesterView(autorisationCategory: .recordPermission, actions: actions)
}

#Preview("Record (fr)") {
    NewAutorisationRequesterView(autorisationCategory: .recordPermission, actions: actions)
        .environment(\.locale, .init(identifier: "fr"))
}

#Preview("Notifications (en)") {
    NewAutorisationRequesterView(autorisationCategory: .localNotifications, actions: actions)
}

#Preview("Notifications (fr)") {
    NewAutorisationRequesterView(autorisationCategory: .localNotifications, actions: actions)
        .environment(\.locale, .init(identifier: "fr"))
}


#endif

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


protocol NewAutorisationRequesterViewActionsProtocol: AnyObject {
    func requestAutorisation(now: Bool, for autorisationCategory: NewAutorisationRequesterViewController.AutorisationCategory) async
}


public struct NewAutorisationRequesterView: View {

    let autorisationCategory: NewAutorisationRequesterViewController.AutorisationCategory
    let actions: NewAutorisationRequesterViewActionsProtocol

    private var textBodyKey: LocalizedStringKey {
        switch autorisationCategory {
        case .localNotifications:
            return "SUBSCRIBING_TO_USER_NOTIFICATIONS_EXPLANATION"
        case .recordPermission:
            return "EXPLANATION_WHY_RECORD_PERMISSION_IS_IMPORTANT"
        }
    }
    
    private var textTitleKey: LocalizedStringKey {
        switch autorisationCategory {
        case .localNotifications:
            return "TITLE_NEVER_MISS_A_MESSAGE"
        case .recordPermission:
            return "TITLE_NEVER_MISS_A_SECURE_CALL"
        }
    }
    
    private var buttonTitleKey: LocalizedStringKey {
        switch autorisationCategory {
        case .localNotifications:
            return "BUTON_TITLE_ACTIVATE_NOTIFICATION"
        case .recordPermission:
            return "BUTON_TITLE_REQUEST_RECORD_PERMISSION"
        }
    }
    
    private var buttonSystemIcon: SystemIcon {
        switch autorisationCategory {
        case .localNotifications:
            return .envelopeBadge
        case .recordPermission:
            return .mic
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
    
    public var body: some View {
        VStack {
            
            ScrollView {
                
                VStack {
                    
                    Image("badge-for-onboarding", bundle: nil)
                        .resizable()
                        .frame(width: 60, height: 60, alignment: .center)
                        .padding()
                    Text(textTitleKey)
                        .font(.title)
                        .multilineTextAlignment(.center)
                    
                    Text(textBodyKey)
                        .frame(minWidth: .none,
                               maxWidth: .infinity,
                               minHeight: .none,
                               idealHeight: .none,
                               maxHeight: .none,
                               alignment: .center)
                        .font(.body)
                        .padding()
                    
                    Button(action: userTappedAllowButton) {
                        Label(buttonTitleKey, systemIcon: buttonSystemIcon)
                            .foregroundStyle(.white)
                            .padding()
                    }
                    .background(Color(UIColor.systemGreen))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                }

            }
            
            // Show a "skip" button bellow the scroll view
            
            Spacer()
            
            if showSkipButton {
                HStack {
                    Spacer()
                    Button("MAYBE_LATER".localizedInThisBundle, action: userTappedSkipButton)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }

        }.navigationBarBackButtonHidden(true)
    }
    
}


struct NewAutorisationRequesterView_Previews: PreviewProvider {
    
    private final class ActionsForPreviews: NewAutorisationRequesterViewActionsProtocol {
        func requestAutorisation(now: Bool, for autorisationCategory: NewAutorisationRequesterViewController.AutorisationCategory) async {}
    }
    
    private static let actions = ActionsForPreviews()
    
    static var previews: some View {
        Group {
            NewAutorisationRequesterView(autorisationCategory: .recordPermission, actions: actions)
            NewAutorisationRequesterView(autorisationCategory: .recordPermission, actions: actions)
                .environment(\.locale, .init(identifier: "fr"))
            NewAutorisationRequesterView(autorisationCategory: .localNotifications, actions: actions)
            NewAutorisationRequesterView(autorisationCategory: .localNotifications, actions: actions)
                .environment(\.locale, .init(identifier: "fr"))
        }
    }
}


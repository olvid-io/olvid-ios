/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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


protocol NewWelcomeScreenViewActionsProtocol: AnyObject {
    func userWantsToLeaveWelcomeScreenAndHasAnOlvidProfile() async
    func userWantsToLeaveWelcomeScreenAndHasNoOlvidProfileYet() async
}


// MARK: - NewWelcomeScreenView

struct NewWelcomeScreenView: View {
    
    let actions: NewWelcomeScreenViewActionsProtocol
    
    var body: some View {
        VStack {
            
            // Vertically center the view, but not on iPhone
            
            if UIDevice.current.userInterfaceIdiom != .phone {
                Spacer()
            }
            
            NewOnboardingHeaderView(
                title: "WELCOME_ONBOARDING_TITLE",
                subtitle: "WELCOME_ONBOARDING_SUBTITLE")
            .padding(.bottom, 35)

            VStack {
                OnboardingSpecificPlainButton("ONBOARDING_BUTTON_TITLE_I_HAVE_AN_OLVID_PROFILE", action: {
                    Task { await actions.userWantsToLeaveWelcomeScreenAndHasAnOlvidProfile() }
                })
                .padding(.bottom)
                OnboardingSpecificPlainButton("ONBOARDING_BUTTON_TITLE_I_DO_NOT_HAVE_AN_OLVID_PROFILE", action: {
                    Task { await actions.userWantsToLeaveWelcomeScreenAndHasNoOlvidProfileYet() }
                })
            }
            .padding(.horizontal)
            
            Spacer()

        }
    }
}


// MARK: - Button used in this view only

struct OnboardingSpecificPlainButton: View {
    
    private let key: LocalizedStringKey
    private let action: () -> Void
    @Environment(\.colorScheme) var colorScheme

    init(_ key: LocalizedStringKey, action: @escaping () -> Void) {
        self.key = key
        self.action = action
    }
        
    var body: some View {
        Button(action: action) {
            HStack {
                Text(key)
                    .if(colorScheme == .light) {
                        $0.foregroundStyle(.black)
                    }
                    .multilineTextAlignment( .leading)
                Spacer()
                Image(systemIcon: .chevronRight)
                    .if(colorScheme == .light) {
                        $0.foregroundStyle(.black)
                    }
            }
            .padding(.horizontal)
            .padding(.vertical, 24)
        }
        .overlay(content: {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(UIColor.lightGray), lineWidth: 1)
        })
    }
    
}


// MARK: - Previews

struct NewWelcomeScreenView_Previews: PreviewProvider {
    
    private final class ActionsForPreviews: NewWelcomeScreenViewActionsProtocol {
        func userWantsToLeaveWelcomeScreenAndHasNoOlvidProfileYet() async {}
        func userWantsToLeaveWelcomeScreenAndHasAnOlvidProfile() async {}
    }
    
    private static let actions = ActionsForPreviews()
    
    static var previews: some View {
        NewWelcomeScreenView(actions: actions)
        NewWelcomeScreenView(actions: actions)
            .environment(\.locale, .init(identifier: "fr"))
        NewWelcomeScreenView(actions: actions)
            .previewLayout(.sizeThatFits)
            .padding(.top, 20)
            .padding(.leading, 20)
            .padding(.trailing, 20)
            .padding(.bottom, 40)
            .frame(width: 443, height: 426)
    }
    
}

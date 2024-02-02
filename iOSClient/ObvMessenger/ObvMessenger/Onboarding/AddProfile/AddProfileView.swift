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

protocol AddProfileViewActionsProtocol: AnyObject {
    func userWantsToCreateNewProfile() async
    func userWantsToImportProfileFromAnotherDevice() async
}


struct AddProfileView: View {
    
    let actions: AddProfileViewActionsProtocol
    
    var body: some View {
        VStack {
            
            // Vertically center the view, but not on iPhone
            
            if UIDevice.current.userInterfaceIdiom != .phone {
                Spacer()
            }
            
            NewOnboardingHeaderView(
                title: "ONBOARDING_ADD_PROFILE_TITLE",
                subtitle: nil)
            .padding(.bottom, 35)

            VStack {
                OnboardingSpecificPlainButton("ONBOARDING_ADD_PROFILE_IMPORT_BUTTON", action: {
                    Task { await actions.userWantsToImportProfileFromAnotherDevice() }
                })
                .padding(.bottom)
                OnboardingSpecificPlainButton("ONBOARDING_ADD_PROFILE_CREATE_BUTTON", action: {
                    Task { await actions.userWantsToCreateNewProfile() }
                })
            }
            
            Spacer()

        }.padding(.horizontal)
    }
    
}

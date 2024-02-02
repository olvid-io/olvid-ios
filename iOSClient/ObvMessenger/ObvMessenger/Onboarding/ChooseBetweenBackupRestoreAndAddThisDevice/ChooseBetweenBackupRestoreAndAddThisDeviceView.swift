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


protocol ChooseBetweenBackupRestoreAndAddThisDeviceViewActionsProtocol: AnyObject {
    func userWantsToRestoreBackup()
    func userWantsToActivateHerProfileOnThisDevice()
    func userIndicatedHerProfileIsManagedByOrganisation()
}


struct ChooseBetweenBackupRestoreAndAddThisDeviceView: View {
    
    let actions: ChooseBetweenBackupRestoreAndAddThisDeviceViewActionsProtocol

    var body: some View {
        ScrollView {
            VStack {
                
                // Vertically center the view, but not on iPhone
                
                if UIDevice.current.userInterfaceIdiom != .phone {
                    Spacer()
                }
                
                NewOnboardingHeaderView(
                    title: "WHAT_DO_YOU_WANT_TO_DO_ONBOARDING_TITLE",
                    subtitle: nil)
                
                VStack {
                    OnboardingSpecificPlainButton("ONBOARDING_BUTTON_TITLE_ACTIVATE_MY_PROFILE_ON_THIS_DEVICE", action: actions.userWantsToActivateHerProfileOnThisDevice)
                    .padding(.bottom)
                    OnboardingSpecificPlainButton("ONBOARDING_BUTTON_TITLE_RESTORE_BACKUP", action: actions.userWantsToRestoreBackup)
                }
                .padding(.horizontal)
                .padding(.top)
                
                HStack {
                    Text("ONBOARDING_NAME_CHOOSER_MANAGED_PROFILE_LABEL")
                        .foregroundStyle(.secondary)
                    Button("ONBOARDING_NAME_CHOOSER_MANAGED_PROFILE_BUTTON_TITLE", action: actions.userIndicatedHerProfileIsManagedByOrganisation)
                }
                .font(.subheadline)
                .padding(.top, 40)
                
                Spacer()
                
            }
        }
    }
    
}







struct ChooseBetweenBackupRestoreAndAddThisDeviceView_Previews: PreviewProvider {
    
    private final class Actions: ChooseBetweenBackupRestoreAndAddThisDeviceViewActionsProtocol {
        func userWantsToRestoreBackup() {}
        func userWantsToActivateHerProfileOnThisDevice() {}
        func userIndicatedHerProfileIsManagedByOrganisation() {}
    }

    private static let actions = Actions()
    
    static var previews: some View {
        ChooseBetweenBackupRestoreAndAddThisDeviceView(actions: actions)
    }
    
}

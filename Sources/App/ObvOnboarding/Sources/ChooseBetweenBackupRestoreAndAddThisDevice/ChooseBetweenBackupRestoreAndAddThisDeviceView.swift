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
import ObvDesignSystem


protocol ChooseBetweenBackupRestoreAndAddThisDeviceViewActionsProtocol: AnyObject {
    func userWantsToRestoreBackup()
    func userWantsToActivateHerProfileOnThisDevice()
    func userIndicatedHerProfileIsManagedByOrganisation()
}


struct ChooseBetweenBackupRestoreAndAddThisDeviceView: View {
    
    let actions: ChooseBetweenBackupRestoreAndAddThisDeviceViewActionsProtocol

    
    private struct ProfileManagedByOrganisationView: View {
        let action: () -> Void
        var body: some View {
            HStack {
                Spacer()
                Text("ONBOARDING_NAME_CHOOSER_MANAGED_PROFILE_LABEL")
                    .foregroundStyle(.secondary)
                Button("ONBOARDING_NAME_CHOOSER_MANAGED_PROFILE_BUTTON_TITLE".localizedInThisBundle,
                       action: action)
            }
            .font(.subheadline)
        }
    }
    
    
    private struct InfoView: View {
        var body: some View {
            HStack(alignment: .firstTextBaseline) {
                Image(systemIcon: .infoCircle)
                Text("TEXT_INFO_RECOMMENDED_TRANSFER_INSTEAD_OF_BACKUP")
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(.secondary)
            .font(.subheadline)
        }
    }
    
    
    var body: some View {
        VStack {
            
            ScrollView {
                VStack {
                    
                    // Vertically center the view, but not on iPhone
                    
                    if UIDevice.current.userInterfaceIdiom != .phone {
                        Spacer()
                    }
                    
                    ObvHeaderView(
                        title: "WHAT_DO_YOU_WANT_TO_DO_ONBOARDING_TITLE".localizedInThisBundle,
                        subtitle: nil)
                    .padding()
                    
                    VStack {
                        
                        Button(action: actions.userWantsToActivateHerProfileOnThisDevice) {
                            Text("ONBOARDING_BUTTON_TITLE_ACTIVATE_MY_PROFILE_ON_THIS_DEVICE")
                        }
                        .buttonStyle(ObvButtonStyleForOnboarding())
                        
                        Button(action: actions.userWantsToRestoreBackup) {
                            Text("ONBOARDING_BUTTON_TITLE_RESTORE_BACKUP")
                        }
                        .buttonStyle(ObvButtonStyleForOnboarding())

                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    InfoView()
                        .padding()
                                        
                }
            }
            
            ProfileManagedByOrganisationView(action: actions.userIndicatedHerProfileIsManagedByOrganisation)
                .padding(.horizontal)
                .padding(.bottom)

        }
    }
    
}




// MARK: - Previews

final private class ActionsForPreviews: ChooseBetweenBackupRestoreAndAddThisDeviceViewActionsProtocol {
    func userWantsToRestoreBackup() {}
    func userWantsToActivateHerProfileOnThisDevice() {}
    func userIndicatedHerProfileIsManagedByOrganisation() {}
}


#Preview {
    ChooseBetweenBackupRestoreAndAddThisDeviceView(actions: ActionsForPreviews())
}

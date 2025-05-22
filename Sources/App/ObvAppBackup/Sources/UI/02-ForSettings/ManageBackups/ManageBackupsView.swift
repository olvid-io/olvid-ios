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


protocol ManageBackupsViewActionsProtocol: AnyObject {
    @MainActor func userWantsToSeeListOfBackupedProfilesPerDevice()
    @MainActor func userWantsToSeeListOfBackupedProfilesAcrossDevice()
    @MainActor func userWantsToEnterDeviceBackupSeed()
}


struct ManageBackupsView: View {
    
    let actions: any ManageBackupsViewActionsProtocol
    
    private struct ShowListOfBackupedProfilesPerDeviceButton: View {
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                HStack {
                    Text("BACKED_UP_PROFILES_PER_DEVICE")
                    Spacer()
                    Image(systemIcon: .chevronRight)
                }
            }
        }
    }

    
    private struct ShowListOfBackupedProfilesAcrossDeviceButton: View {
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                HStack {
                    Text("BACKED_UP_PROFILES_ACROSS_DEVICE")
                    Spacer()
                    Image(systemIcon: .chevronRight)
                }
            }
        }
    }

    
    private struct EnterDeviceBackupSeedButton: View {
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                HStack {
                    Text("ENTER_DEVICE_BACKUP_SEED")
                    Spacer()
                    Image(systemIcon: .chevronRight)
                }
            }
        }
    }

    
    var body: some View {
        Form {
            
            Section(String(localizedInThisBundle: "BACKED_UP_PROFILES")) {
                ShowListOfBackupedProfilesAcrossDeviceButton(action: actions.userWantsToSeeListOfBackupedProfilesAcrossDevice)
                ShowListOfBackupedProfilesPerDeviceButton(action: actions.userWantsToSeeListOfBackupedProfilesPerDevice)
            }
            
            Section(String(localizedInThisBundle: "SEARCH_BACKUP_MANUALLY")) {
                EnterDeviceBackupSeedButton(action: actions.userWantsToEnterDeviceBackupSeed)
            }

        }
    }
}




// MARK: - Previews


private final class ActionsForPreview: ManageBackupsViewActionsProtocol {
    func userWantsToSeeListOfBackupedProfilesAcrossDevice() {}
    func userWantsToSeeListOfBackupedProfilesPerDevice() {}
    func userWantsToEnterDeviceBackupSeed() {}
}

#Preview {
    ManageBackupsView(actions: ActionsForPreview())
}

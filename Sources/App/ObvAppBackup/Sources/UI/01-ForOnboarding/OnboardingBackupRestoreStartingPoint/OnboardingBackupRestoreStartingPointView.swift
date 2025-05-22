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



@MainActor
protocol OnboardingBackupRestoreStartingPointViewActionsProtocol: ObservableObject {
    func userWantsToRestoreBackupAutomaticallyFromICloudKeychain()
    func userWantsToRestoreBackupManually()
}


struct OnboardingBackupRestoreStartingPointView: View {
    
    let actions: any OnboardingBackupRestoreStartingPointViewActionsProtocol
    
    private let title = String(localizedInThisBundle: "RESTORE_ONE_OF_YOUR_BACKUPS")
    
    
    var body: some View {
        ScrollView {
    
            VStack {
                
                ObvHeaderView(title: title, subtitle: nil)
                    .padding(.bottom, 40)
                
                Button(action: actions.userWantsToRestoreBackupAutomaticallyFromICloudKeychain) {
                    Text("RESTORE_AUTOMATICALLY_FROM_ICLOUD_KEYCHAIN")
                }
                .buttonStyle(ObvButtonStyleForOnboarding())
                
                Button(action: actions.userWantsToRestoreBackupManually) {
                    Text("ENTER_BACKUP_KEY")
                }
                .buttonStyle(ObvButtonStyleForOnboarding())

            }
            .padding()

        }
    }
}






// MARK: - Previews


@MainActor
private final class ActionsForPreviews: OnboardingBackupRestoreStartingPointViewActionsProtocol {
    func userWantsToRestoreBackupAutomaticallyFromICloudKeychain() {}
    func userWantsToRestoreBackupManually() {}
}

#Preview {
    OnboardingBackupRestoreStartingPointView(actions: ActionsForPreviews())
}

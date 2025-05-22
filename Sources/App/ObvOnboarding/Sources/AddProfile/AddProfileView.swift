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
import ObvDesignSystem


@MainActor
protocol AddProfileViewActionsProtocol: AnyObject {
    func userWantsToCreateNewProfile() async
    func userWantsToImportProfileFromAnotherDevice() async
    func userWantsToRestoreBackup() async
}


struct AddProfileView: View {
    
    let actions: AddProfileViewActionsProtocol
    
    @State private var isBadgeVisible = false

    private func onAppear() {
        Task {
            try await Task.sleep(seconds: 0.2)
            withAnimation {
                isBadgeVisible = true
            }
        }
    }

    var body: some View {
        VStack {
            
            // Vertically center the view, but not on iPhone
            
            if UIDevice.current.userInterfaceIdiom != .phone {
                Spacer()
            }
            
            ObvHeaderView(
                title: "ONBOARDING_ADD_PROFILE_TITLE".localizedInThisBundle,
                subtitle: nil,
                isBadgeVisible: $isBadgeVisible)
            .onAppear(perform: onAppear)
            .padding(.bottom, 35)

            VStack {
                
                Button {
                    Task { await actions.userWantsToImportProfileFromAnotherDevice() }
                } label: {
                    Text("ONBOARDING_ADD_PROFILE_IMPORT_BUTTON")
                }
                .buttonStyle(ObvButtonStyleForOnboarding())

                Button {
                    Task { await actions.userWantsToRestoreBackup() }
                } label: {
                    Text("RESTORE_A_BACKUP")
                }
                .buttonStyle(ObvButtonStyleForOnboarding())

                Button {
                    Task { await actions.userWantsToCreateNewProfile() }
                } label: {
                    Text("ONBOARDING_ADD_PROFILE_CREATE_BUTTON")
                }
                .buttonStyle(ObvButtonStyleForOnboarding())
                
            }
            
            Spacer()

        }.padding(.horizontal)
    }
    
}

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
import ObvTypes

@MainActor
public protocol NewWelcomeScreenViewDataSource: AnyObject {
    func getAnOwnedIdentityExistingOnThisDevice() async -> ObvCryptoId?
}


protocol NewWelcomeScreenViewActionsProtocol: AnyObject {
    func userWantsToLeaveWelcomeScreenAndHasAnOlvidProfile() async
    func userWantsToLeaveWelcomeScreenAndHasNoOlvidProfileYet() async
    func userWantsToLeaveWelcomeScreenAndFinishOnboarding(ownedIdentityThatCanBeOpened: ObvCryptoId)
}


// MARK: - NewWelcomeScreenView

struct NewWelcomeScreenView: View {
    
    let actions: NewWelcomeScreenViewActionsProtocol
    let dataSource: NewWelcomeScreenViewDataSource
    
    @State private var isBadgeVisible = false
    @State private var ownedIdentityThatCanBeOpened: ObvCryptoId?
    
    private func onAppear() {
        Task {
            try await Task.sleep(seconds: 1)
            withAnimation {
                isBadgeVisible = true
            }
        }
        Task {
            let ownedCryptoId = await dataSource.getAnOwnedIdentityExistingOnThisDevice()
            withAnimation {
                self.ownedIdentityThatCanBeOpened = ownedCryptoId
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
                title: "WELCOME_ONBOARDING_TITLE".localizedInThisBundle,
                subtitle: "WELCOME_ONBOARDING_SUBTITLE".localizedInThisBundle,
                isBadgeVisible: $isBadgeVisible)
            .onAppear(perform: onAppear)
            .padding(.bottom, 35)

            VStack {
                
                Button {
                    Task { await actions.userWantsToLeaveWelcomeScreenAndHasAnOlvidProfile() }
                } label: {
                    Text("ONBOARDING_BUTTON_TITLE_I_HAVE_AN_OLVID_PROFILE")
                }
                .buttonStyle(ObvButtonStyleForOnboarding())

                Button {
                    Task { await actions.userWantsToLeaveWelcomeScreenAndHasNoOlvidProfileYet() }
                } label: {
                    Text("ONBOARDING_BUTTON_TITLE_I_DO_NOT_HAVE_AN_OLVID_PROFILE")
                }
                .buttonStyle(ObvButtonStyleForOnboarding())
                
                Spacer()
                
                if let ownedIdentityThatCanBeOpened {
                    Button {
                        actions.userWantsToLeaveWelcomeScreenAndFinishOnboarding(ownedIdentityThatCanBeOpened: ownedIdentityThatCanBeOpened)
                    } label: {
                        Text("ONBOARDING_BUTTON_TITLE_OPEN_YOUR_EXISTING_PROFILE")
                            .padding(.vertical)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemIcon: .chevronRight)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom)
                }
                
            }
            .padding(.horizontal)
            
            Spacer()

        }
    }
}


// MARK: - Previews

private final class DataSourceForPreviews: NewWelcomeScreenViewDataSource {
    
    func getAnOwnedIdentityExistingOnThisDevice() async -> ObvTypes.ObvCryptoId? {
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)
    }

}

@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()

struct NewWelcomeScreenView_Previews: PreviewProvider {
    
    private final class ActionsForPreviews: NewWelcomeScreenViewActionsProtocol {
        func userWantsToLeaveWelcomeScreenAndFinishOnboarding(ownedIdentityThatCanBeOpened: ObvTypes.ObvCryptoId) {}
        func userWantsToLeaveWelcomeScreenAndHasNoOlvidProfileYet() async {}
        func userWantsToLeaveWelcomeScreenAndHasAnOlvidProfile() async {}
    }
    
    private static let actions = ActionsForPreviews()
    
    static var previews: some View {
        NewWelcomeScreenView(actions: actions, dataSource: dataSourceForPreviews)
        NewWelcomeScreenView(actions: actions, dataSource: dataSourceForPreviews)
            .environment(\.locale, .init(identifier: "fr"))
        NewWelcomeScreenView(actions: actions, dataSource: dataSourceForPreviews)
            .previewLayout(.sizeThatFits)
            .padding(.top, 20)
            .padding(.leading, 20)
            .padding(.trailing, 20)
            .padding(.bottom, 40)
            .frame(width: 443, height: 426)
    }
    
}

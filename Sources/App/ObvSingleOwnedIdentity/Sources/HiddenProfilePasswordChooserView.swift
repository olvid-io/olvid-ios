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
import ObvAppCoreConstants

@MainActor
public protocol HiddenProfilePasswordChooserViewActions {
    func userWantsToHideOwnedIdentity(_ view: HiddenProfilePasswordChooserView, ownedCryptoId: ObvCryptoId, password: String) async throws
}

@MainActor
protocol HiddenProfilePasswordChooserViewNavigation {
    func hiddenProfilePasswordChooserViewShouldBeDismissed(_ view: HiddenProfilePasswordChooserView)
}


public struct HiddenProfilePasswordChooserView: View {
    
    let ownedCryptoId: ObvCryptoId
    let navigation: any HiddenProfilePasswordChooserViewNavigation
    let actions: any HiddenProfilePasswordChooserViewActions
        
    @State private var password1 = ""
    @State private var password2 = ""

    @State private var isSettingPassword: Bool = false
    @State private var profileWasHidden: Bool = false

    private var passwordsAreIdenticalAndLongEnough: Bool {
        password1 == password2 && password1.count >= ObvAppCoreConstants.minimumLengthOfPasswordForHiddenProfiles
    }

    private func dismissTapped() {
        navigation.hiddenProfilePasswordChooserViewShouldBeDismissed(self)
    }
        
    private func createPasswordTapped() {
        isSettingPassword = true
        Task {
            defer { isSettingPassword = false }
            do {
                try await actions.userWantsToHideOwnedIdentity(self, ownedCryptoId: ownedCryptoId, password: password1)
                withAnimation { profileWasHidden = true }
                shownHUDCategory = .icon(.eyeSlash)
                try? await Task.sleep(seconds: 1)
                shownHUDCategory = nil
            } catch {
                shownHUDCategory = .xmark
                try? await Task.sleep(seconds: 1)
                shownHUDCategory = nil
                assertionFailure()
            }
        }
    }
    
    @State private var shownHUDCategory: HUDView.Category? = nil

    public var body: some View {
        NavigationStack {
            ZStack {
                Form {
                    Section {
                        Text("HIDE_PROFILE_EXPLANATION")
                            .font(.body)
                    }
                    Section {
                        if profileWasHidden {
                            Text("YOUR_PROFILE_WAS_HIDDEN_SUCESSFULLY")
                            OlvidButtonNew(action: dismissTapped) {
                                Text("DISMISS")
                            }
                        } else {
                            ObvSecureField(label: String(localizedInThisBundle: "ENTER_PASSWORD"), text: $password1)
                                .font(.body)
                            ObvSecureField(label: String(localizedInThisBundle: "CONFIRM_PASSWORD"), text: $password2)
                                .font(.body)
                            HStack {
                                OlvidButtonNew(action: dismissTapped, style: .glassOrBordered) {
                                    Text("CANCEL")
                                }
                                OlvidButtonNew(action: createPasswordTapped) {
                                    Text("CREATE_PASSWORD")
                                }
                                .disabled(!passwordsAreIdenticalAndLongEnough)
                            }
                            .buttonStyle(PlainButtonStyle()) // Prevents cell highlight when tapping a button
                        }
                    }
                }
                if let shownHUDCategory {
                    HUDView(category: shownHUDCategory)
                }
            }
            .navigationBarTitle(String(localizedInThisBundle: "CHOOSE_PASSWORD"), displayMode: .inline)
        }
    }
}


fileprivate struct ObvSecureField: View {
    
    let label: String
    let text: Binding<String>
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Spacer()
            Image(systemIcon: .lock(.none))
                .foregroundColor(Color(UIColor.systemGreen))
            SecureField(label, text: text)
            Spacer()
        }
    }
    
}

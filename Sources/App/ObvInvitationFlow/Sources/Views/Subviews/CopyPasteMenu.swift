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
import ObvTypes
import ObvAppTypes


@MainActor
public protocol ObvCopyPasteMenuActions {
    
    func userWantsToPasteOlvidURLFromClipboard(_ view: CopyPasteMenu, ownedCryptoId: ObvCryptoId) throws -> OlvidURL
    func userWantsToCopyOwnedIdentityToClipboard(_ view: CopyPasteMenu, ownedCryptoId: ObvCryptoId) throws

}


public struct CopyPasteMenu: View {
    
    let ownedCryptoId: ObvCryptoId
    let actions: ObvCopyPasteMenuActions
    @Binding var pastedOlvidURL: OlvidURL?
    
    @State private var isPastingContactIdentityFailedAlertShown = false
    @State private var isCopyOwnedIdentityFailedAlertShown = false
    @State private var isSuccessfulOwnedIdentityCopyAlertShown = false
    
    private func pasteOlvidURLFromClipboard() {
        do {
            let olvidURL = try actions.userWantsToPasteOlvidURLFromClipboard(self, ownedCryptoId: ownedCryptoId)
            withAnimation { self.pastedOlvidURL = olvidURL }
        } catch {
            isPastingContactIdentityFailedAlertShown = true
        }
    }
    
    private func copyOwnedIdentityToClipboard() {
        do {
            try actions.userWantsToCopyOwnedIdentityToClipboard(self, ownedCryptoId: ownedCryptoId)
            isSuccessfulOwnedIdentityCopyAlertShown = true
        } catch {
            isCopyOwnedIdentityFailedAlertShown = true
        }
    }
    
    public var body: some View {
        Menu {
            Section(String(localizedInThisBundle: "MORE_INVITATION_METHODS")) {
                Button(action: copyOwnedIdentityToClipboard) {
                    Label(title: { Text("COPY_MY_ID_TO_CLIPBOARD") }, icon: { Image(systemIcon: .docOnClipboard) })
                }
                Button(action: pasteOlvidURLFromClipboard) {
                    Label(title: { Text("PASTE_CONTACT_ID_FROM_CLIPBOARD") }, icon: { Image(systemIcon: .docOnDoc) })
                }
            }
        } label: {
            if #available(iOS 26.0, *) {
                Image(systemIcon: .ellipsis)
            } else {
                Image(systemIcon: .ellipsisCircle)
            }
        }
        .alert(String(localizedInThisBundle: "PASTED_STRING_IS_NOT_OLVID_ID"), isPresented: $isPastingContactIdentityFailedAlertShown, actions: {})
        .alert(String(localizedInThisBundle: "YOUR_ID_WAS_COPIED_TO_CLIPBOARD"), isPresented: $isSuccessfulOwnedIdentityCopyAlertShown, actions: {})
        .alert(String(localizedInThisBundle: "YOUR_ID_COULD_NOT_BE_COPIED_TO_CLIPBOARD"), isPresented: $isCopyOwnedIdentityFailedAlertShown, actions: {})
    }
    
}

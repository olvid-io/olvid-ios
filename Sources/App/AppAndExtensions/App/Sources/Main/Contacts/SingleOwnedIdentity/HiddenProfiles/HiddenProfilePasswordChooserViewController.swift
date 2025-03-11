/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
  

import UIKit
import SwiftUI
import ObvTypes
import ObvEngine
import ObvUICoreData
import ObvUI

protocol HiddenProfilePasswordChooserViewControllerDelegate: AnyObject {
    func userCancelledHiddenProfilePasswordChooserViewController() async
    func userChosePasswordForHidingOwnedIdentity(_ ownedCryptoId: ObvCryptoId, password: String) async
}


final class HiddenProfilePasswordChooserViewController: UIHostingController<HiddenProfilePasswordChooserView> {
    
    init(ownedCryptoId: ObvCryptoId, delegate: HiddenProfilePasswordChooserViewControllerDelegate) {
        let view = HiddenProfilePasswordChooserView(ownedCryptoId: ownedCryptoId, delegate: delegate)
        super.init(rootView: view)
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


struct HiddenProfilePasswordChooserView: View {
    
    let ownedCryptoId: ObvCryptoId
    weak var delegate: HiddenProfilePasswordChooserViewControllerDelegate?
    
    @State private var password1 = ""
    @State private var password2 = ""

    private var passwordsAreIdenticalAndLongEnough: Bool {
        password1 == password2 && password1.count >= ObvMessengerConstants.minimumLengthOfPasswordForHiddenProfiles
    }
    
    private func dismissTapped() {
        Task { await delegate?.userCancelledHiddenProfilePasswordChooserViewController() }
    }
    
    private func createPasswordTapped() {
        guard passwordsAreIdenticalAndLongEnough else { assertionFailure(); return }
        Task { await delegate?.userChosePasswordForHidingOwnedIdentity(ownedCryptoId, password: password1) }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("HIDE_PROFILE_EXPLANATION")
                        .font(.body)
                }
                Section {
                    ObvSecureField(label: NSLocalizedString("ENTER_PASSWORD", comment: ""), text: $password1)
                        .font(.body)
                    ObvSecureField(label: NSLocalizedString("CONFIRM_PASSWORD", comment: ""), text: $password2)
                        .font(.body)
                    HStack {
                        OlvidButton(style: .standardWithBlueText,
                                    title: Text(CommonString.Word.Cancel),
                                    action: dismissTapped)
                        OlvidButton(style: .blue,
                                    title: Text("CREATE_PASSWORD"),
                                    action: createPasswordTapped)
                        .disabled(!passwordsAreIdenticalAndLongEnough)
                    }
                    .buttonStyle(PlainButtonStyle()) // Prevents cell highlight when tapping a button
                }
            }
            .navigationBarTitle("CHOOSE_PASSWORD", displayMode: .inline)
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


struct HiddenProfilePasswordChooserView_Previews: PreviewProvider {
    
    private static let identitiesAsURLs: [URL] = [
        URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!,
        URL(string: "https://invitation.olvid.io/#AwAAAHAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAVZx8aqikpCe4h3ayCwgKBf-2nDwz-a6vxUo3-ep5azkBUjimUf3J--GXI8WTc2NIysQbw5fxmsY9TpjnDsZMW-AAAAAACEJvYiBXb3Jr")!,
    ]
        
    private static let ownedCryptoIds = identitiesAsURLs.map({ ObvURLIdentity(urlRepresentation: $0)!.cryptoId })

    static var previews: some View {
        HiddenProfilePasswordChooserView(ownedCryptoId: ownedCryptoIds[0])
    }
    
}

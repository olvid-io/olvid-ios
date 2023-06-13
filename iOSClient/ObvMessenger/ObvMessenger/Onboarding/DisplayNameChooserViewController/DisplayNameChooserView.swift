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

import SwiftUI
import ObvTypes
import ObvUICoreData


protocol DisplayNameChooserViewControllerDelegate: AnyObject {
    func userDidSetUnmanagedDetails(ownedIdentityCoreDetails: ObvIdentityCoreDetails, photoURL: URL?) async
    func userDidAcceptedKeycloakDetails(keycloakDetails: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff), keycloakState: ObvKeycloakState, photoURL: URL?) async
}


final class DisplayNameChooserViewController: UIHostingController<DisplayNameChooserView> {

    private let singleIdentity: SingleIdentity
    
    init(delegate: DisplayNameChooserViewControllerDelegate) {
        self.singleIdentity = SingleIdentity(serverAndAPIKeyToShow: nil, identityDetails: nil)
        let view = DisplayNameChooserView(singleIdentity: singleIdentity, completionHandlerOnSave: { [weak delegate] (coreDetails, photoURL) in
            Task { await delegate?.userDidSetUnmanagedDetails(ownedIdentityCoreDetails: coreDetails, photoURL: photoURL) }
        })
        super.init(rootView: view)
    }
    
    init(keycloakDetails: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff), keycloakState: ObvKeycloakState, delegate: DisplayNameChooserViewControllerDelegate) {
        self.singleIdentity = SingleIdentity(keycloakDetails: keycloakDetails)
        let view = DisplayNameChooserView(singleIdentity: singleIdentity, completionHandlerOnSave: { [weak delegate] (coreDetails, photoURL) in
            assert(try! keycloakDetails.keycloakUserDetailsAndStuff.getObvIdentityCoreDetails() == coreDetails)
            Task { await delegate?.userDidAcceptedKeycloakDetails(keycloakDetails: keycloakDetails, keycloakState: keycloakState, photoURL: photoURL) }
        })
        super.init(rootView: view)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Title.myId
    }
    
    deinit {
        debugPrint("DisplayNameChooserViewController deinit")
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


struct DisplayNameChooserView: View {

    var singleIdentity: SingleIdentity
    var completionHandlerOnSave: (ObvIdentityCoreDetails, URL?) -> Void
    var editionType: EditSingleOwnedIdentityView.EditionType = .creation

    var body: some View {
        EditSingleOwnedIdentityView(
            editionType: editionType,
            singleIdentity: singleIdentity,
            userConfirmedPublishAction: {
                if let userDetails = try? singleIdentity.keycloakDetails?.keycloakUserDetailsAndStuff.getObvIdentityCoreDetails() {
                    completionHandlerOnSave(userDetails, singleIdentity.photoURL)
                } else if let unmanagedIdentityDetails = singleIdentity.unmanagedIdentityDetails {
                    completionHandlerOnSave(unmanagedIdentityDetails, singleIdentity.photoURL)
                }
            },
            userWantsToUnbindFromKeycloakServer: { _ in
                assertionFailure("We do not expect any unbinding during an onboarding")
            })
    }
}


struct DisplayNameChooserView_Previews: PreviewProvider {
    
    private static let emptyIdentity = SingleIdentity(firstName: nil,
                                                      lastName: nil,
                                                      position: nil,
                                                      company: nil,
                                                      isKeycloakManaged: false,
                                                      showGreenShield: false,
                                                      showRedShield: false,
                                                      identityColors: nil,
                                                      photoURL: nil)
    
    static var previews: some View {
        Group {
            DisplayNameChooserView(singleIdentity: emptyIdentity, completionHandlerOnSave: {_,_  in })
            DisplayNameChooserView(singleIdentity: emptyIdentity, completionHandlerOnSave: {_,_  in })
                .environment(\.colorScheme, .dark)
                .environment(\.locale, .init(identifier: "fr"))
        }
    }
}

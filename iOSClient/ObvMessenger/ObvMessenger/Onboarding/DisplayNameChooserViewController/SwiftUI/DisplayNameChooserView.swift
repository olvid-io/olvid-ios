/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

@available(iOS 13, *)
struct DisplayNameChooserView: View {

    var singleIdentity: SingleIdentity
    var completionHandlerOnSave: (ObvIdentityCoreDetails, URL?) -> Void
    var editionType: EditSingleOwnedIdentityView.EditionType = .creation

    var body: some View {
        EditSingleOwnedIdentityView(editionType: editionType,
                                    singleIdentity: singleIdentity,
                                    userConfirmedPublishAction: {
                                        if let userDetails = try? singleIdentity.keycloakDetails?.keycloakUserDetailsAndStuff.getObvIdentityCoreDetails() {
                                            completionHandlerOnSave(userDetails, singleIdentity.photoURL)
                                        } else if let unmanagedIdentityDetails = singleIdentity.unmanagedIdentityDetails {
                                            completionHandlerOnSave(unmanagedIdentityDetails, singleIdentity.photoURL)
                                        }
                                    })
    }
}


@available(iOS 13, *)
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

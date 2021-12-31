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

@available(iOS 13, *)
struct OwnedIdentityHeaderView: View {

    @ObservedObject var singleIdentity: SingleIdentity

    var body: some View {
        IdentityCardContentView(model: singleIdentity, displayMode: .header(tapToFullscreen: true))
    }

}

@available(iOS 13, *)
struct ContactIdentityHeaderView: View {

    @ObservedObject var singleIdentity: SingleContactIdentity
    @State private var profilePictureFullScreenIsPresented = false
    var forceEditionMode: CircleAndTitlesEditionMode? = nil

    var body: some View {
        ContactIdentityCardContentView(model: singleIdentity, preferredDetails: .customOrTrusted, forceEditionMode: forceEditionMode, displayMode: .header(tapToFullscreen: true))
    }
}


@available(iOS 13, *)
struct IdentityHeaderView_Previews: PreviewProvider {
    
    static let ownedIdentity = SingleIdentity(
        firstName: "Steve",
        lastName: "Job",
        position: "CEO",
        company: "Apple",
        isKeycloakManaged: false,
        showGreenShield: false,
        showRedShield: false,
        identityColors: nil,
        photoURL: nil)
    static let contactIdentity = SingleContactIdentity(
        firstName: "Steve",
        lastName: "Job",
        position: "CEO",
        company: "Apple",
        customDisplayName: nil,
        editionMode: .none,
        publishedContactDetails: nil,
        contactStatus: .noNewPublishedDetails,
        contactHasNoDevice: false,
        isActive: true)
    
    static var previews: some View {
        Group {
            OwnedIdentityHeaderView(singleIdentity: ownedIdentity)
            ContactIdentityHeaderView(singleIdentity: contactIdentity)
            ContactIdentityHeaderView(singleIdentity: contactIdentity, forceEditionMode: .nicknameAndPicture(action: {}))
        }
    }
}

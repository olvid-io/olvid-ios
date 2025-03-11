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
import ObvUICoreData


struct ContactIdentityHeaderView: View {

    @ObservedObject var singleIdentity: SingleContactIdentity
    @State private var profilePictureFullScreenIsPresented = false
    let editionMode: CircleAndTitlesEditionMode

    var body: some View {
        ContactIdentityCardContentView(model: singleIdentity,
                                       preferredDetails: .customOrTrusted,
                                       displayMode: .header,
                                       editionMode: editionMode)
    }
}



struct IdentityHeaderView_Previews: PreviewProvider {
    
    static let contactIdentity = SingleContactIdentity(
        firstName: "Steve",
        lastName: "Job",
        position: "CEO",
        company: "Apple",
        customDisplayName: nil,
        publishedContactDetails: nil,
        contactStatus: .noNewPublishedDetails,
        atLeastOneDeviceAllowsThisContactToReceiveMessages: true,
        contactHasNoDevice: false,
        contactIsOneToOne: true,
        isActive: true)
    
    static var previews: some View {
        Group {
            ContactIdentityHeaderView(singleIdentity: contactIdentity, editionMode: .none)
            ContactIdentityHeaderView(singleIdentity: contactIdentity, editionMode: .custom(icon: .pencil(), action: { }))
        }
    }
}

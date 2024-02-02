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

import Foundation
import SwiftUI


protocol SpinnerViewForContactCellModelProtocol: ObservableObject {
    
    var contactHasNoDevice: Bool { get }
    var isActive: Bool { get }
    var atLeastOneDeviceAllowsThisContactToReceiveMessages: Bool { get }
    
}


/// This view conditionally shows a spinner (typically, when we are creating a channel with the contact), an exclamation mark (when the keycloak contact is inactive), or nothing (most of the time). It is used in the list of contacts, but also in other places, like in the list of group members.
struct SpinnerViewForContactCell<Model: SpinnerViewForContactCellModelProtocol>: View {
    
    @ObservedObject var model: Model

    var body: some View {
        if !model.isActive {
            Image(systemIcon: .exclamationmarkShieldFill)
                .foregroundColor(.red)
        } else if !model.contactHasNoDevice && !model.atLeastOneDeviceAllowsThisContactToReceiveMessages {
            ProgressView()
        } else {
            EmptyView()
                .frame(width: 0, height: 0)
        }
    }
    
}


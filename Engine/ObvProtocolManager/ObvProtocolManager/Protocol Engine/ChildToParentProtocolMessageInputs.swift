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

import Foundation

import ObvTypes
import ObvEncoder

struct ChildToParentProtocolMessageInputs {
    
    let childProtocolInstanceUid: UID
    let childProtocolInstanceReachedStateRawId: Int
    let childProtocolInstanceEncodedReachedState: ObvEncoded // The the state reached by the child protocol instance, as an ObvEncoded

    init(childProtocolInstanceUid: UID, childProtocolInstanceReachedState: ConcreteProtocolState) {
        self.childProtocolInstanceUid = childProtocolInstanceUid
        self.childProtocolInstanceReachedStateRawId = childProtocolInstanceReachedState.rawId
        self.childProtocolInstanceEncodedReachedState = childProtocolInstanceReachedState.encode()
    }
    
    init?(_ listOfEncoded: [ObvEncoded]) {
        guard listOfEncoded.count == 3 else { return nil }
        do {
            self.childProtocolInstanceUid = try listOfEncoded[0].decode()
            self.childProtocolInstanceReachedStateRawId = try listOfEncoded[1].decode()
            self.childProtocolInstanceEncodedReachedState = listOfEncoded[2]
        } catch {
            return nil
        }
    }
    
    func toListOfEncoded() -> [ObvEncoded] {
        return [childProtocolInstanceUid.encode(), childProtocolInstanceReachedStateRawId.encode(), childProtocolInstanceEncodedReachedState]
    }
}

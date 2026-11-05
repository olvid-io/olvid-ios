/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvSingleDiscussion
import ObvUICoreData


// MARK: - How far a deletion reaches, said twice

/// The one place the discussion screen's vocabulary for a deletion and the app's are put side by side.
///
/// `ObvSingleDiscussion` does not depend on `ObvUICoreData` and should not: it knows nothing of Core Data, and ``WhatCanBeDeleted/Kind`` is the third enum it has
/// had to say for itself after `MessageAction` and `WhatAMessageOffers.Entry`. So the two exist and are mapped here, in **one** function each way, where the
/// compiler names the omission if either gains a case.
///
/// Moving `DeletionType` into `ObvAppTypes` — which both modules already depend on — would delete this file. It is worth doing one day and is a cleanup of its
/// own: twenty-seven files name that type, and the change lands in `ObvUICoreData` and in the coordinators.
extension DeletionType {

    init(_ kind: WhatCanBeDeleted.Kind) {
        switch kind {
        case .fromThisDeviceOnly:
            self = .fromThisDeviceOnly
        case .fromAllOwnedDevices:
            self = .fromAllOwnedDevices
        case .fromAllOwnedDevicesAndAllContactDevices:
            self = .fromAllOwnedDevicesAndAllContactDevices
        }
    }

}


extension WhatCanBeDeleted.Kind {

    init(_ deletionType: DeletionType) {
        switch deletionType {
        case .fromThisDeviceOnly:
            self = .fromThisDeviceOnly
        case .fromAllOwnedDevices:
            self = .fromAllOwnedDevices
        case .fromAllOwnedDevicesAndAllContactDevices:
            self = .fromAllOwnedDevicesAndAllContactDevices
        }
    }

}

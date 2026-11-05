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
import ObvCrypto


/// One receipt with everything needed to encrypt it and put it in a request.
///
/// The two things that are not in a row are gathered when the receipt is about to leave: the contact's devices, which
/// the identity database is the authority on, and the seed, which is derived from the owned identity. A receipt that
/// waited overnight therefore goes to the devices the contact has this morning.
struct ReturnReceiptReadyToUpload {

    let returnReceipt: ReturnReceiptToUpload
    let contactDeviceUIDs: Set<UID>
    /// Makes the encryption deterministic, so that the same receipt always encrypts to the same bytes.
    let seed: Seed

    init(returnReceipt: ReturnReceiptToUpload, contactDeviceUIDs: Set<UID>, seed: Seed) {
        self.returnReceipt = returnReceipt
        self.contactDeviceUIDs = contactDeviceUIDs
        self.seed = seed
    }

}

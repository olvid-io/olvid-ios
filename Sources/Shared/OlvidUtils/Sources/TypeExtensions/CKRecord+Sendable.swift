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
import CloudKit


// Warning: This is a dangerous extension. We need this for now (2023-04-04) because of the way the AppBackupManager was coded. Beacause it is an actor, Xcode 14.3 raises several warnings that shall be fixed by refactoring the AppBackupManager. We will do so when integrating the multidevice feature and the new backup procedure.

extension CKRecord: @unchecked @retroactive Sendable {
    
}

extension [CKRecord]?: @unchecked Sendable {
    
}

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
import CallKit


protocol CallProviderProtocol {

    /// We do *not* use the async way for reporting new incoming call. We had too much issues when calling this method on the `CXProvider` while in the background.
    func reportNewIncomingCall(with UUID: UUID, update: CXCallUpdate,completion: @escaping (Error?) -> Void)

    func reportOutgoingCall(with: UUID, startedConnectingAt: Date?)
    func reportOutgoingCall(with: UUID, connectedAt: Date?)
    func reportCall(with: UUID, updated: CXCallUpdate)
    func reportCall(with: UUID, endedAt: Date?, reason: CXCallEndedReason)
    
}
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
import ObvTypes

protocol TransferTransportDelegate: AnyObject, Sendable, TransferTransportSendJsonMessageDelegateForSource, TransferTransportSendJsonMessageDelegateForDestination {
    
    var transferTransportLayerState: TransferTransportLayerState { get async }
    var role: TransferRole { get async }
    var ownedCryptoId: ObvCryptoId { get async }
    var transferId: String? { get async }
    
    func connect(progressUpdater: any ConnectProgressUpdater) async throws
    
    func getAsyncStreamOfTransferTransportLayerState() async -> AsyncStream<TransferTransportLayerState>
    func userWantsToCancelTransfer(cancelSource: TransferTransportCancelSource) async
    
    func disconnect() async
    
}

enum TransferTransportCancelSource {
    case currentDevice
    case otherDevice(transferId: String)
}

extension TransferTransportCancelSource: CustomStringConvertible {
    
    var description: String {
        switch self {
        case .currentDevice:
            return "CurrentDevice"
        case .otherDevice(let transferId):
            return "OtherDevice(\(transferId))"
        }
    }
}

enum TransferTransportDelegateError: Error {
    case transferTransportDelegateFailed
    case ownedCryptoIdDoesNotMatch
}


protocol ConnectProgressUpdater: Sendable {
    func updateConnectProgress(entryNumber: Int, total: Int) async
}

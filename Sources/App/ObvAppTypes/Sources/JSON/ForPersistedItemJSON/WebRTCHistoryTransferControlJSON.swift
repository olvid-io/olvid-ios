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


/// Message sent during a message history transfer.
///
/// This message can be sent both by the source and by the destination, depending on the kind. When kind is:
/// - `.requestTransfer`: this message is sent by the source to the destination, just before starting a Transfer, in order to "wake up" the destination and request a confirmation.
/// - `.acceptTransfer`: this message is sent by the destination in order to accept a transfer (requested by a `.requestTransfer`).
/// - `.rejectOrAbortTransfer`: this message is sent by the destination in order to reject a transfer (requested by a `.requestTransfer`). Also sent to interrupt a transfer, by any of the two devices.
public struct WebRTCHistoryTransferControlJSON {
    
    public let transferId: String
    public let kind: Kind
    
    public enum Kind: Int, Codable {
        case requestTransfer = 1
        case acceptTransfer = 2
        case rejectOrAbortTransfer = 3
    }
    
    public init(transferId: String, kind: Kind) {
        self.transferId = transferId
        self.kind = kind
    }
    
}


extension WebRTCHistoryTransferControlJSON: Codable {
    
    enum CodingKeys: String, CodingKey {
        case transferId = "id"
        case kind = "t"
    }

}

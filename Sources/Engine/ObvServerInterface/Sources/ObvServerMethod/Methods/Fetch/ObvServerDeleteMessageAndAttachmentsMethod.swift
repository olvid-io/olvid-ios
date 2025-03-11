/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import os.log
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils
import ObvEncoder

public final class ObvServerDeleteMessageAndAttachmentsMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerDeleteMessageAndAttachmentsMethod", category: "ObvServerInterface")
    
    public let pathComponent = "/deleteMessageAndAttachments"
    
    public var serverURL: URL { return ownedCryptoId.serverURL }

    private let token: Data
    private let deviceUid: UID
    public let flowId: FlowIdentifier
    public let isActiveOwnedIdentityRequired = false
    private let ownedCryptoId: ObvCryptoIdentity
    private let messageUIDsAndCategories: [MessageUIDAndCategory]
    
    public var ownedIdentity: ObvCryptoIdentity? {
        return ownedCryptoId
    }
    
    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public enum Category: CustomDebugStringConvertible, ObvEncodable {
                
        case requestDeletion
        case markAsListed
        
        public var debugDescription: String {
            switch self {
            case .requestDeletion: return "requestDeletion"
            case .markAsListed: return "markAsListed"
            }
        }
        
        public func obvEncode() -> ObvEncoder.ObvEncoded {
            let markAsListed: Bool
            switch self {
            case .requestDeletion:
                markAsListed = false
            case .markAsListed:
                markAsListed = true
            }
            return markAsListed.obvEncode()
        }

    }
    
    public struct MessageUIDAndCategory {
        
        public let messageUID: UID
        public let category: Category
        
        public init(messageUID: UID, category: Category) {
            self.messageUID = messageUID
            self.category = category
        }
        
        func toListOfObvEncoded() -> [ObvEncoded] {
            [messageUID.obvEncode(), category.obvEncode()]
        }
        
    }
    
    public init(ownedCryptoId: ObvCryptoIdentity, token: Data, deviceUid: UID, messageUIDsAndCategories: [MessageUIDAndCategory], flowId: FlowIdentifier) {
        self.ownedCryptoId = ownedCryptoId
        self.token = token
        self.deviceUid = deviceUid
        self.messageUIDsAndCategories = messageUIDsAndCategories
        self.flowId = flowId
    }
    
    public enum PossibleReturnStatus: UInt8, CustomDebugStringConvertible {
        case ok = 0x00
        case invalidSession = 0x04
        case generalError = 0xff
        public var debugDescription: String {
            switch self {
            case .ok: return "ok"
            case .invalidSession: return "invalidSession"
            case .generalError: return "generalError"
            }
        }
    }

    lazy public var dataToSend: Data? = {
        [
            ownedCryptoId.getIdentity().obvEncode(),
            token.obvEncode(),
            deviceUid.obvEncode(),
            messageUIDsAndCategories.toListOfObvEncoded().obvEncode(),
        ].obvEncode().rawData
    }()

    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> PossibleReturnStatus? {
        
        guard let (rawServerReturnedStatus, _) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .error)
            return nil
        }
        
        guard let serverReturnedStatus = PossibleReturnStatus(rawValue: rawServerReturnedStatus) else {
            os_log("The returned server status is invalid", log: log, type: .error)
            return nil
        }
        
        // At this point, we simply forward the return status
        return serverReturnedStatus
    }

}


// MARK: - Helper

extension [ObvServerDeleteMessageAndAttachmentsMethod.MessageUIDAndCategory] {
    
    func toListOfObvEncoded() -> [ObvEncoded] {
        var listOfObvEncoded = [ObvEncoded]()
        for messageUIDAndCategory in self {
            listOfObvEncoded += messageUIDAndCategory.toListOfObvEncoded()
        }
        return listOfObvEncoded
    }
    
}

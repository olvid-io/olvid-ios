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
import OlvidUtils
import ObvCrypto

extension URLSessionTask: ObvErrorMaker {
    
    public static var errorDomain: String { "URLSessionTask+OwnedCryptoIdAndFlowIdentifier" }
    
    
    public func setTaskDescriptionWith(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) throws {
        let info = OwnedCryptoIdAndFlowIdentifier(ownedCryptoId: ownedCryptoId, flowId: flowId)
        self.taskDescription = try info.jsonEncode()
    }
 
    
    public func getOwnedCryptoIdAndFlowIdentifierFromTaskDescription() throws -> (ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) {
        guard let taskDescription else { assertionFailure(); throw Self.makeError(message: "The task description is nil") }
        let info = try OwnedCryptoIdAndFlowIdentifier.jsonDecode(taskDescription)
        return (info.ownedCryptoId, info.flowId)
    }
    
    
    private struct OwnedCryptoIdAndFlowIdentifier: Codable, ObvErrorMaker {
        
        static let errorDomain = "URLSessionTask+OwnedCryptoIdAndFlowIdentifier"
        
        let ownedCryptoId: ObvCryptoIdentity
        let flowId: FlowIdentifier
        
        enum CodingKeys: String, CodingKey {
            case ownedCryptoId = "ownedCryptoId"
            case flowId = "flowId"
        }
        
        init(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) {
            self.ownedCryptoId = ownedCryptoId
            self.flowId = flowId
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(ownedCryptoId.getIdentity(), forKey: .ownedCryptoId)
            try container.encode(flowId, forKey: .flowId)
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let identity = try values.decode(Data.self, forKey: .ownedCryptoId)
            guard let ownedCryptoId = ObvCryptoIdentity(from: identity) else {
                assertionFailure()
                throw Self.makeError(message: "Could not decode owned identity")
            }
            let flowId = try values.decode(FlowIdentifier.self, forKey: .flowId)
            self.init(ownedCryptoId: ownedCryptoId, flowId: flowId)
        }
        
        func jsonEncode() throws -> String {
            let encoder = JSONEncoder()
            guard let encoded = String(data: try encoder.encode(self), encoding: .utf8) else {
                assertionFailure()
                throw Self.makeError(message: "Encoding failed")
            }
            return encoded
        }
        
        
        static func jsonDecode(_ string: String) throws -> OwnedCryptoIdAndFlowIdentifier {
            guard let data = string.data(using: .utf8) else {
                assertionFailure()
                throw Self.makeError(message: "Decoding failed")
            }
            let decoder = JSONDecoder()
            return try decoder.decode(OwnedCryptoIdAndFlowIdentifier.self, from: data)
        }

    }
    
}

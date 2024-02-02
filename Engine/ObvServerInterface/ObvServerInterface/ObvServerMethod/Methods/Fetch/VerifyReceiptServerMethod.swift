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
import os.log
import ObvCrypto
import ObvMetaManager
import ObvTypes
import OlvidUtils


public final class VerifyReceiptServerMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.VerifyReceiptMethod", category: "ObvServerInterface")

    public let pathComponent = "/verifyReceipt"

    public var serverURL: URL { return ownedIdentity.serverURL }

    public let ownedIdentity: ObvCryptoIdentity
    private let token: Data
    private let signedAppStoreTransactionAsJWS: String
    public let flowId: FlowIdentifier
    public let isActiveOwnedIdentityRequired = true
    private let iOSStoreId = Data([0x02]) // StoreKit1 used 0x00, StoreKit2 uses 0x02.

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, token: Data, signedAppStoreTransactionAsJWS: String, identityDelegate: ObvIdentityDelegate, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedIdentity = ownedIdentity
        self.token = token
        self.signedAppStoreTransactionAsJWS = signedAppStoreTransactionAsJWS
        self.identityDelegate = identityDelegate
    }

    private enum ServerReturnStatus: UInt8 {
        case ok = 0x00
        case invalidSession = 0x04
        case receiptIsExpired = 0x10
        case generalError = 0xff
    }
    
    public enum PossibleReturnStatus {
        case ok(apiKey: UUID)
        case invalidSession
        case receiptIsExpired
        case generalError
    }

    lazy public var dataToSend: Data? = {
        return [ownedIdentity.getIdentity(), token, iOSStoreId, signedAppStoreTransactionAsJWS].obvEncode().rawData
    }()
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> Result<PossibleReturnStatus, Error> {
        
        os_log("💰 Parsing the server response...", log: log, type: .info)
        
        guard let (rawServerReturnedStatus, listOfReturnedDatas) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("💰 Could not parse the server response", log: log, type: .error)
            let error = Self.makeError(message: "💰 Could not parse the server response")
            return .failure(error)
        }
        
        guard let serverReturnedStatus = ServerReturnStatus(rawValue: rawServerReturnedStatus) else {
            os_log("💰 The returned server status is invalid", log: log, type: .error)
            let error = Self.makeError(message: "💰 The returned server status is invalid")
            return .failure(error)
        }

        switch serverReturnedStatus {
        
        case .ok:
            
            guard listOfReturnedDatas.count == 1 else {
                os_log("💰 The server did not return the expected number of elements", log: log, type: .error)
                let error = Self.makeError(message: "💰 The server did not return the expected number of elements")
                return .failure(error)
            }
            guard let rawApiKey = String(listOfReturnedDatas[0]) else {
                os_log("💰 We could not recover the raw api key", log: log, type: .error)
                let error = Self.makeError(message: "💰 We could not recover the raw api key")
                return .failure(error)
            }
            guard let apiKey = UUID(uuidString: rawApiKey) else {
                os_log("💰 We could not cast the raw api key", log: log, type: .error)
                let error = Self.makeError(message: "💰 We could not cast the raw api key")
                return .failure(error)
            }
            return .success(.ok(apiKey: apiKey))

        case .invalidSession:
            
            os_log("The server reported that the session is invalid", log: log, type: .error)
            return .success(.invalidSession)

        case .receiptIsExpired:
            
            os_log("💰 The server reported that the receipt is expired", log: log, type: .error)
            return .success(.receiptIsExpired)

        case .generalError:
            os_log("💰 The server reported a general error", log: log, type: .error)
            return .success(.generalError)

        }
        
    }
    
}

/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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


public final class VerifyReceiptMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.VerifyReceiptMethod", category: "ObvServerInterface")

    public let pathComponent = "/verifyReceipt"

    public var serverURL: URL { return ownedIdentity.serverURL }

    public let ownedIdentity: ObvCryptoIdentity
    private let token: Data
    private let receiptData: String
    private let transactionIdentifier: String
    public let flowId: FlowIdentifier
    public let isActiveOwnedIdentityRequired = true
    private let iOSStoreId = Data([0x00])

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, token: Data, receiptData: String, transactionIdentifier: String, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedIdentity = ownedIdentity
        self.token = token
        self.receiptData = receiptData
        self.transactionIdentifier = transactionIdentifier
    }

    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case invalidSession = 0x04
        case receiptIsExpired = 0x10
        case generalError = 0xff
    }

    lazy public var dataToSend: Data? = {
        return [ownedIdentity.getIdentity(), token, iOSStoreId, receiptData].encode().rawData
    }()
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> (status: PossibleReturnStatus, apiKey: UUID?)? {
        
        os_log("💰 Parsing the server response...", log: log, type: .info)
        
        guard let (rawServerReturnedStatus, listOfReturnedDatas) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("💰 Could not parse the server response", log: log, type: .error)
            return nil
        }
        
        guard let serverReturnedStatus = PossibleReturnStatus(rawValue: rawServerReturnedStatus) else {
            os_log("💰 The returned server status is invalid", log: log, type: .error)
            return nil
        }

        switch serverReturnedStatus {
        
        case .ok:
            
            guard listOfReturnedDatas.count == 1 else {
                os_log("💰 The server did not return the expected number of elements", log: log, type: .error)
                return nil
            }
            guard let rawApiKey = String(listOfReturnedDatas[0]) else {
                os_log("💰 We could not recover the raw api key", log: log, type: .error)
                return nil
            }
            guard let apiKey = UUID(uuidString: rawApiKey) else {
                os_log("💰 We could not cast the raw api key", log: log, type: .error)
                return nil
            }
            return (serverReturnedStatus, apiKey)

        case .invalidSession:
            
            os_log("The server reported that the session is invalid", log: log, type: .error)
            return (serverReturnedStatus, nil)

        case .receiptIsExpired:
            
            os_log("💰 The server reported that the receipt is expired", log: log, type: .error)
            return (serverReturnedStatus, nil)

        case .generalError:
            os_log("💰 The server reported a general error", log: log, type: .error)
            return (serverReturnedStatus, nil)
        
        }
        
    }
    
}

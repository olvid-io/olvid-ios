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
import ObvMetaManager
import ObvTypes
import ObvCrypto
import OlvidUtils
import ObvEncoder


/// Allows to upload a batch of messages without attachment
public final class ObvServerBatchUploadMessages: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerBatchUploadMessages", category: "ObvServerInterface")

    public let pathComponent = "/batchUploadMessages"
    
    public let serverURL: URL
    public let flowId: FlowIdentifier
    public let ownedIdentity: ObvCryptoIdentity? = nil // Messages can be from distinct owned identities (but they must share the same serverURL)
    public let isActiveOwnedIdentityRequired = false // As we don't specify an owned identity, this Boolean makes no sense anyway
    public var identityDelegate: ObvIdentityDelegate? = nil
    public let messagesToUpload: [MessageToUpload]
    
    public struct MessageToUpload {
        
        public struct Header {
            
            let deviceUid: UID
            let wrappedKey: EncryptedData
            let toIdentity: ObvCryptoIdentity
            
            public init(deviceUid: UID, wrappedKey: EncryptedData, toIdentity: ObvCryptoIdentity) {
                self.deviceUid = deviceUid
                self.wrappedKey = wrappedKey
                self.toIdentity = toIdentity
            }
            
        }
        
        let headers: [Header]
        let encryptedContent: EncryptedData
        let isAppMessageWithUserContent: Bool
        let isVoipMessageForStartingCall: Bool
        
        public let messageId: ObvMessageIdentifier // Not sent to server
        
        public init(messageId: ObvMessageIdentifier, headers: [Header], encryptedContent: EncryptedData, isAppMessageWithUserContent: Bool, isVoipMessageForStartingCall: Bool) {
            self.headers = headers
            self.encryptedContent = encryptedContent
            self.isAppMessageWithUserContent = isAppMessageWithUserContent
            self.isVoipMessageForStartingCall = isVoipMessageForStartingCall
            self.messageId = messageId
        }
        
    }

    public init(serverURL: URL, messagesToUpload: [MessageToUpload], flowId: FlowIdentifier) {
        self.serverURL = serverURL
        self.flowId = flowId
        self.messagesToUpload = messagesToUpload
    }
    
    lazy public var dataToSend: Data? = {
        messagesToUpload.map({ $0.obvEncode() }).obvEncode().rawData
    }()
    
}


// MARK: - Helpers for the encoding

private extension ObvServerBatchUploadMessages.MessageToUpload.Header {

    func toListOfEncoded() -> [ObvEncoded] {
        [self.deviceUid.obvEncode(), self.wrappedKey.obvEncode(), self.toIdentity.obvEncode()]
    }
    
}


private extension [ObvServerBatchUploadMessages.MessageToUpload.Header] {
    
    func toListOfEncoded() -> [ObvEncoded] {
        var listOfEncodedHeaders = [ObvEncoded]()
        for header in self {
            listOfEncodedHeaders += header.toListOfEncoded()
        }
        return listOfEncodedHeaders
    }
    
}


extension ObvServerBatchUploadMessages.MessageToUpload: ObvEncodable {
    
    public func obvEncode() -> ObvEncoded {
        [
            headers.toListOfEncoded().obvEncode(),
            encryptedContent.raw.obvEncode(),
            isAppMessageWithUserContent.obvEncode(),
            isVoipMessageForStartingCall.obvEncode(),
        ].obvEncode()
    }
    
}


extension ObvServerBatchUploadMessages {
    
    private enum PossibleReturnRawStatus: UInt8 {
        case ok = 0x00
        case payloadTooLarge = 0x18
        case generalError = 0xff
    }

    public enum PossibleReturnStatus {
        case ok([(uidFromServer: UID, nonce: Data, timestampFromServer: Date)])
        case generalError
        case payloadTooLarge
    }
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> PossibleReturnStatus? {
        
        guard let (rawServerReturnedStatus, allListsOfReturnedDatas) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .error)
            assertionFailure()
            return nil
        }
        
        guard let serverReturnedStatus = PossibleReturnRawStatus(rawValue: rawServerReturnedStatus) else {
            os_log("The returned server status is invalid", log: log, type: .error)
            assertionFailure()
            return nil
        }

        switch serverReturnedStatus {

        case .ok:
            
            guard !allListsOfReturnedDatas.isEmpty else {
                os_log("The server did not return the expected number of elements", log: log, type: .error)
                assertionFailure()
                return nil
            }
            
            var returnedValues = [(uidFromServer: UID, nonce: Data, timestampFromServer: Date)]()
            
            for encodedListOfReturnedData in allListsOfReturnedDatas {
                
                guard let listOfReturnedDatas = [ObvEncoded](encodedListOfReturnedData) else {
                    os_log("Could not decode", log: log, type: .error)
                    assertionFailure()
                    return nil
                }
                
                guard listOfReturnedDatas.count == 3 else {
                    os_log("The server did not return the expected number of elements", log: log, type: .error)
                    assertionFailure()
                    return nil
                }

                guard let uidFromServer = UID(listOfReturnedDatas[0]) else {
                    os_log("We could decode the UID returned by the server", log: log, type: .error)
                    assertionFailure()
                    return nil
                }

                guard let nonce = Data(listOfReturnedDatas[1]) else {
                    os_log("We could decode the nonce returned by the server", log: log, type: .error)
                    assertionFailure()
                    return nil
                }

                guard let serverTimestampInMilliseconds = Int(listOfReturnedDatas[2]) else {
                    os_log("We could decode the timestamp returned by the server", log: log, type: .error)
                    assertionFailure()
                    return nil
                }
                let serverTimestamp = Date(timeIntervalSince1970: Double(serverTimestampInMilliseconds)/1000.0)

                returnedValues += [(uidFromServer, nonce, serverTimestamp)]
            }
            
            return .ok(returnedValues)
            
        case .payloadTooLarge:
            
            assertionFailure()
            
            return .payloadTooLarge

        case .generalError:
            
            assertionFailure()
            
            return .generalError
            
        }
        
    }
    
}

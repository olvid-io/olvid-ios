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
import ObvEncoder
import ObvMetaManager
import OlvidUtils

public final class ObvServerUploadMessageAndGetUidsMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerUploadMessageAndGetUidsMethod", category: "ObvServerInterface")
    
    public let pathComponent = "/uploadMessageAndGetUids"
    
    public let serverURL: URL
    
    public let ownedIdentity: ObvCryptoIdentity?
    private let encryptedAttachments: [(length: Int, chunkLength: Int)]
    private let encryptedExtendedMessagePayload: EncryptedData?
    private let headers: [(deviceUid: UID, wrappedKey: EncryptedData, toIdentity: ObvCryptoIdentity)]
    private let encryptedContent: EncryptedData
    /// If `true`, the server will send a User Notification to the devices of the recipient of the message. This should always be `false` for protocol messages.
    private let isAppMessageWithUserContent: Bool
    private let isVoipMessageForStartingCall: Bool
    public let isActiveOwnedIdentityRequired = true
    public let isDeletedOwnedIdentitySufficient = true // When deleting an owned identity, we (sometimes) send messages to let our contacts know about this. This Boolean makes it possible to send the messages even if the owned identity cannot be found.
    public let flowId: FlowIdentifier

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    // The server won't store the encrypted extended message payload if larger than this value. If larger, we only ignore it.
    private let maxMessageExtendedContentLenghtForServer = 50*1024
    
    public init(ownedIdentity: ObvCryptoIdentity, headers: [(deviceUid: UID, wrappedKey: EncryptedData, toIdentity: ObvCryptoIdentity)], encryptedContent: EncryptedData, encryptedExtendedMessagePayload: EncryptedData?, encryptedAttachments: [(length: Int, chunkLength: Int)], serverURL: URL, isAppMessageWithUserContent: Bool, isVoipMessageForStartingCall: Bool, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedIdentity = ownedIdentity
        self.headers = headers
        self.encryptedContent = encryptedContent
        self.encryptedExtendedMessagePayload = encryptedExtendedMessagePayload
        self.encryptedAttachments = encryptedAttachments
        self.serverURL = serverURL
        self.isAppMessageWithUserContent = isAppMessageWithUserContent
        self.isVoipMessageForStartingCall = isVoipMessageForStartingCall
    }
    
    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case generalError = 0xff
    }
    
    lazy public var dataToSend: Data? = {
        
        var listOfEncodedHeaders = [ObvEncoded]()
        for header in headers {
            listOfEncodedHeaders.append(header.deviceUid.obvEncode())
            listOfEncodedHeaders.append(header.wrappedKey.raw.obvEncode())
            listOfEncodedHeaders.append(header.toIdentity.getIdentity().obvEncode())
        }
        
        var encryptedAttachmentEncodedLengths = [ObvEncoded]()
        var encryptedAttachmentChunkEncodedLengths = [ObvEncoded]()
        for encryptedAttachment in encryptedAttachments {
            encryptedAttachmentEncodedLengths.append(encryptedAttachment.length.obvEncode())
            encryptedAttachmentChunkEncodedLengths.append(encryptedAttachment.chunkLength.obvEncode())
        }
        
        if let encryptedExtendedMessagePayload = self.encryptedExtendedMessagePayload, encryptedExtendedMessagePayload.count >= maxMessageExtendedContentLenghtForServer {
            os_log("The encrypted extended message payload is too large and will be ignored: %{public}d > %{public}d", log: ObvServerUploadMessageAndGetUidsMethod.log, type: .error, encryptedExtendedMessagePayload.count, maxMessageExtendedContentLenghtForServer)
            assertionFailure()
        }
        
        let listOfEncodedVals: [ObvEncoded]
        if let encryptedExtendedMessagePayload = self.encryptedExtendedMessagePayload, encryptedExtendedMessagePayload.count < maxMessageExtendedContentLenghtForServer {
            listOfEncodedVals = [listOfEncodedHeaders.obvEncode(),
                                 encryptedContent.raw.obvEncode(),
                                 encryptedExtendedMessagePayload.raw.obvEncode(),
                                 isAppMessageWithUserContent.obvEncode(),
                                 isVoipMessageForStartingCall.obvEncode(),
                                 encryptedAttachmentEncodedLengths.obvEncode(),
                                 encryptedAttachmentChunkEncodedLengths.obvEncode()]
            
        } else {
            listOfEncodedVals = [listOfEncodedHeaders.obvEncode(),
                                 encryptedContent.raw.obvEncode(),
                                 isAppMessageWithUserContent.obvEncode(),
                                 isVoipMessageForStartingCall.obvEncode(),
                                 encryptedAttachmentEncodedLengths.obvEncode(),
                                 encryptedAttachmentChunkEncodedLengths.obvEncode()]
        }
        return listOfEncodedVals.obvEncode().rawData
    }()
    
    
    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> (status: PossibleReturnStatus, (idFromServer: UID, nonce: Data, timestampFromServer: Date, signedURLs: [[URL]])?)? {
        
        guard let (rawServerReturnedStatus, listOfReturnedDatas) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .error)
            return nil
        }
        
        guard let serverReturnedStatus = PossibleReturnStatus(rawValue: rawServerReturnedStatus) else {
            os_log("The returned server status is invalid", log: log, type: .error)
            return nil
        }
        
        switch serverReturnedStatus {
            
        case .ok:
            
            guard listOfReturnedDatas.count == 4 else {
                os_log("The server did not return the expected number of elements", log: log, type: .error)
                return nil
            }
            
            guard let uidFromServer = UID(listOfReturnedDatas[0]) else {
                os_log("We could decode the UID returned by the server", log: log, type: .error)
                return nil
            }

            guard let nonce = Data(listOfReturnedDatas[1]) else {
                os_log("We could decode the nonce returned by the server", log: log, type: .error)
                return nil
            }

            guard let serverTimestampInMilliseconds = Int(listOfReturnedDatas[2]) else {
                os_log("We could decode the timestamp returned by the server", log: log, type: .error)
                return nil
            }
            let serverTimestamp = Date(timeIntervalSince1970: Double(serverTimestampInMilliseconds)/1000.0)

            guard let listOfEncodedElements = [ObvEncoded](listOfReturnedDatas[3]) else {
                os_log("We could not decode the list of encoded list of signed URLs sent by the server", log: log, type: .error)
                return nil
            }
            
            let listOfListOfEncodedURLs = listOfEncodedElements.compactMap { [ObvEncoded]($0) }
            
            let signedURLs: [[URL]] = listOfListOfEncodedURLs.map {
                $0.compactMap {
                    guard let urlAsString = String($0) else { return nil }
                    return URL(string: urlAsString)
                }
            }
            
            return (serverReturnedStatus, (uidFromServer, nonce, serverTimestamp, signedURLs))
            
        case .generalError:
            
            os_log("The server reported a general error", log: log, type: .error)
            return (serverReturnedStatus, nil)
            
        }
        
    }

}

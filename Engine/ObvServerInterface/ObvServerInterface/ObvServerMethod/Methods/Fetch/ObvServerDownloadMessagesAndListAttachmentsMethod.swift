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
import ObvTypes
import ObvEncoder
import ObvMetaManager
import OlvidUtils

public final class ObvServerDownloadMessagesAndListAttachmentsMethod: ObvServerDataMethod {
    
    static let log = OSLog(subsystem: "io.olvid.server.interface.ObvServerDownloadMessagesAndListAttachmentsMethod", category: "ObvServerInterface")
    
    public let pathComponent = "/downloadMessagesAndListAttachments"
    
    public var serverURL: URL { return toIdentity.serverURL }
    
    public let toIdentity: ObvCryptoIdentity
    
    public let ownedIdentity: ObvCryptoIdentity
    private let token: Data
    private let deviceUid: UID
    public let isActiveOwnedIdentityRequired = true
    public let flowId: FlowIdentifier

    weak public var identityDelegate: ObvIdentityDelegate? = nil

    public init(ownedIdentity: ObvCryptoIdentity, token: Data, deviceUid: UID, toIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        self.flowId = flowId
        self.ownedIdentity = ownedIdentity
        self.toIdentity = toIdentity
        self.token = token
        self.deviceUid = deviceUid
    }
    
    public enum PossibleReturnStatus: UInt8 {
        case ok = 0x00
        case invalidSession = 0x04
        case deviceIsNotRegistered = 0x0b
        case generalError = 0xff
    }
    
    lazy public var dataToSend: Data? = {
        return [toIdentity.getIdentity(), token, deviceUid].encode().rawData
    }()
    
    public struct MessageAndAttachmentsOnServer {
        public let messageUidFromServer: UID
        public let messageUploadTimestampFromServer: Date
        public let encryptedContent: EncryptedData
        public let hasEncryptedExtendedMessagePayload: Bool
        public let wrappedKey: EncryptedData
        public let attachments: [AttachmentOnServer]
    }
    
    public struct AttachmentOnServer {
        public let attachmentNumber: Int
        public let expectedLength: Int
        public let expectedChunkLength: Int
        public let chunkDownloadPrivateUrls: [URL?]
    }

    public static func parseObvServerResponse(responseData: Data, using log: OSLog) -> (status: PossibleReturnStatus, downloadTimestampFromServer: Date?, [MessageAndAttachmentsOnServer]?)? {
        
        guard let (rawServerReturnedStatus, listOfReturnedDatas) = genericParseObvServerResponse(responseData: responseData, using: log) else {
            os_log("Could not parse the server response", log: log, type: .error)
            assertionFailure()
            return nil
        }
        
        guard let serverReturnedStatus = PossibleReturnStatus(rawValue: rawServerReturnedStatus) else {
            os_log("The returned server status is invalid", log: log, type: .error)
            return nil
        }
        
        switch serverReturnedStatus {
            
        case .ok:
            guard listOfReturnedDatas.count >= 1 else {
                os_log("We could not decode the messages/attachments returned by the server: unexpected number of values", log: log, type: .error)
                return nil
            }
            let encodedDownloadTimestampFromServer = listOfReturnedDatas[0]
            let listOfReturnedMessageAndAttachmentsData = [ObvEncoded](listOfReturnedDatas[1...])
            guard let downloadTimestampFromServerInMilliseconds = Int(encodedDownloadTimestampFromServer) else {
                os_log("We could decode the timestamp returned by the server", log: log, type: .error)
                return nil
            }
            let downloadTimestampFromServer = Date(timeIntervalSince1970: Double(downloadTimestampFromServerInMilliseconds)/1000.0)
            let listOfUnparsedMessagesAndTheirAttachments = listOfReturnedMessageAndAttachmentsData.compactMap({ [ObvEncoded]($0) })
            guard listOfReturnedMessageAndAttachmentsData.count == listOfUnparsedMessagesAndTheirAttachments.count else {
                os_log("We could not decode the messages/attachments returned by the server", log: log, type: .error)
                return nil
            }
            let listOfMessageAndAttachments = listOfUnparsedMessagesAndTheirAttachments.compactMap({ ObvServerDownloadMessagesAndListAttachmentsMethod.parse(unparsedMessageAndAttachments: $0) })
            guard listOfMessageAndAttachments.count == listOfUnparsedMessagesAndTheirAttachments.count else {
                os_log("We could not decode the messages/attachments returned by the server", log: log, type: .error)
                return nil
            }
            os_log("We succesfully parsed the message(s) and attachment(s)", log: log, type: .debug)
            return (serverReturnedStatus, downloadTimestampFromServer, listOfMessageAndAttachments)
            
        case .invalidSession:
            os_log("The server reported that the session is invalid", log: log, type: .error)
            return (serverReturnedStatus, nil, nil)
            
        case .deviceIsNotRegistered:
            os_log("The server reported that the device is not registered", log: log, type: .error)
            return (serverReturnedStatus, nil, nil)

        case .generalError:
            os_log("The server reported a general error", log: log, type: .error)
            return (serverReturnedStatus, nil, nil)
            
        }
    }
    
    public static func parse(unparsedMessageAndAttachments: [ObvEncoded]) -> MessageAndAttachmentsOnServer? {
        // We expect the unparsedMessageAndAttachments list to contain encoded values of the following elements:
        // - the message uid,
        // - the header (containing our device uid, that we discard, and the wrapped key), and
        // - the encrypted content of the message.
        // - a Boolean indicating whether the APNS notification sent by the server did include mutable-content: 1
        // Each of the following elements (if any) represents an attachment
        guard unparsedMessageAndAttachments.count >= 5 else { return nil }
        // Parse the message uid, header, and encrypted content
        guard let messageId = UID(unparsedMessageAndAttachments[0]) else { return nil }
        guard let messageUploadTimestampFromServerInMilliseconds = Int(unparsedMessageAndAttachments[1]) else { return nil }
        let messageUploadTimestampFromServer = Date(timeIntervalSince1970: Double(messageUploadTimestampFromServerInMilliseconds)/1000.0)
        guard let wrappedKey = EncryptedData(unparsedMessageAndAttachments[2]) else { return nil }
        guard let encryptedContent = EncryptedData(unparsedMessageAndAttachments[3]) else { return nil }
        guard let hasEncryptedExtendedMessagePayload = Bool(unparsedMessageAndAttachments[4]) else { return nil }
        // Parse the attachments
        let rangeForAttachments = unparsedMessageAndAttachments.startIndex+5..<unparsedMessageAndAttachments.endIndex
        let unparsedAttachments = unparsedMessageAndAttachments[rangeForAttachments].compactMap({ [ObvEncoded]($0) })
        guard unparsedAttachments.count == unparsedMessageAndAttachments[rangeForAttachments].count else { assertionFailure(); return nil }
        let attachments = unparsedAttachments.compactMap({ parse(unparsedAttachment: $0) })
        guard attachments.count == unparsedAttachments.count else { assertionFailure(); return nil }
        let messageAndAttachmentsOnServer = MessageAndAttachmentsOnServer(messageUidFromServer: messageId, messageUploadTimestampFromServer: messageUploadTimestampFromServer, encryptedContent: encryptedContent, hasEncryptedExtendedMessagePayload: hasEncryptedExtendedMessagePayload, wrappedKey: wrappedKey, attachments: attachments)
        return messageAndAttachmentsOnServer
    }
    
    private static func parse(unparsedAttachment: [ObvEncoded]) -> AttachmentOnServer? {
        // We expect the unparsedAttachment list to contain encoded values of the following elements:
        // - the attachment number
        // - the expected length of the attachment
        // - the expected chunk size
        // - one signed URL per chunk to download
        guard unparsedAttachment.count == 4 else { return nil }
        guard let attachmentNumber = Int(unparsedAttachment[0]) else { return nil }
        guard let expectedLength = Int(unparsedAttachment[1]) else { return nil }
        guard let expectedChunkSize = Int(unparsedAttachment[2]) else { return nil }
        guard let encodedURLs = [ObvEncoded](unparsedAttachment[3]) else { return nil }
        let chunkDownloadPrivateUrls: [URL?] = encodedURLs.map {
            guard let urlAsString = String($0) else { return nil }
            guard !urlAsString.isEmpty else { return nil }
            return URL(string: urlAsString)
        }
        let attachmentOnServer = AttachmentOnServer(attachmentNumber: attachmentNumber, expectedLength: expectedLength, expectedChunkLength: expectedChunkSize, chunkDownloadPrivateUrls: chunkDownloadPrivateUrls)
        return attachmentOnServer
    }

}

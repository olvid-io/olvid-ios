/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import ObvCrypto
import ObvEncoder

public struct ObvNetworkMessageToSend {

    public let messageId: MessageIdentifier
    public let encryptedContent: EncryptedData
    public let encryptedExtendedMessagePayload: EncryptedData?
    public let serverURL: URL
    public let isAppMessageWithUserContent: Bool
    public let isVoipMessageForStartingCall: Bool
    public let headers: [Header]

    public let attachments: [Attachment]?
    
    public init(messageId: MessageIdentifier, encryptedContent: EncryptedData, encryptedExtendedMessagePayload: EncryptedData?, isAppMessageWithUserContent: Bool, isVoipMessageForStartingCall: Bool, serverURL: URL, headers: [Header], attachments: [Attachment]? = nil) {
        self.messageId = messageId
        self.encryptedContent = encryptedContent
        self.encryptedExtendedMessagePayload = encryptedExtendedMessagePayload
        self.serverURL = serverURL
        self.headers = headers
        self.isAppMessageWithUserContent = isAppMessageWithUserContent
        self.isVoipMessageForStartingCall = isVoipMessageForStartingCall
        self.attachments = attachments
    }
    
    public struct Header {
        public let toIdentity: ObvCryptoIdentity
        public let deviceUid: UID
        public let wrappedMessageKey: EncryptedData
        
        /// This header contains the required data allowing the target device to decrypt the associated message.
        ///
        /// - Parameters:
        ///   - deviceUid: Either the `UID` of a device that is one of the current device of the identity we want to send the message to, or the broadcast device uid, that is, 32 bytes set to 0xff.
        ///   - wrappedMessageKey: A ciphertext that, once decrypted, allows to recover the message key, which the authenticated encryption key that allows to decrypt the encrypted content of the message. This `wrappedMessageKey` is generated by a channel.
        ///
        ///     In the case where an Oblivious channel was used to generate this `wrappedMessageKey`, the inner structure of they wrapped key is
        ///
        ///     `keyId || encryptedMessageKey`
        ///
        ///     where `keyId` is a 32 byte identifier allowing the recipient to recover the proper symmetric decryption key allowing to decrypt `encryptedMessageKey`.
        ///
        ///     In the case where an Asymmetric channel was used to generate this `wrappedMessageKey`, the inner structure of they wrapped key is
        ///
        ///     `ciphertext || encryptedMessageKey`
        ///
        ///     where `ciphertext` is a 32 byte long ciphertext resulting from a KEM using the public key of the recipient. The recipient can decrypt this `ciphertext`, in order to obtain a key allowing to decrypt the `encryptedMessageKey`.
        public init(toIdentity: ObvCryptoIdentity, deviceUid: UID, wrappedMessageKey: EncryptedData) {
            self.toIdentity = toIdentity
            self.deviceUid = deviceUid
            self.wrappedMessageKey = wrappedMessageKey
        }
    }
    
    public struct Attachment {
        public let fileURL: URL
        public let deleteAfterSend: Bool
        public let byteSize: Int
        public let key: AuthenticatedEncryptionKey

        public init(fileURL: URL, deleteAfterSend: Bool, byteSize: Int, key: AuthenticatedEncryptionKey) {
            self.fileURL = fileURL
            self.deleteAfterSend = deleteAfterSend
            self.byteSize = byteSize
            self.key = key
        }
    }
    
}
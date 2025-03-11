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
import ObvCrypto
import ObvTypes
import ObvEncoder


public struct ReceivedApplicationMessage {
    
    let message: ReceivedMessage
    public let remoteCryptoIdentity: ObvCryptoIdentity
    public let remoteDeviceUid: UID
    public let messagePayload: Data
    public let attachmentsInfos: [ObvNetworkFetchAttachmentInfos]

    public var messageId: ObvMessageIdentifier { return message.messageId }
    public var extendedMessagePayloadKey: AuthenticatedEncryptionKey? { message.extendedMessagePayloadKey }
    public var extendedMessagePayload: Data? { message.extendedMessagePayload }

    public init?(with message: ReceivedMessage) {
        guard message.type == .ApplicationMessage else { return nil }
        switch message.channelType {
        case .asymmetricChannel,
             .local,
             .anyObliviousChannelOrPreKeyWithOwnedDevice,
             .anyObliviousChannelOrPreKeyChannel,
             .anyObliviousChannel:
            return nil
        case .obliviousChannel(remoteCryptoIdentity: let remoteCryptoIdentity, remoteDeviceUid: let remoteDeviceUid):
            // We do not check whether the channel is confirmed or not. This does not matter when receiving a message.
            self.remoteCryptoIdentity = remoteCryptoIdentity
            self.remoteDeviceUid = remoteDeviceUid
        case .preKeyChannel(remoteCryptoIdentity: let remoteCryptoIdentity, remoteDeviceUid: let remoteDeviceUid):
            self.remoteCryptoIdentity = remoteCryptoIdentity
            self.remoteDeviceUid = remoteDeviceUid
        }
        
        guard let (messagePayload, attachmentsInfos) = ReceivedApplicationMessage.generateMessagePayloadAndAttachmentsInfos(from: message.encodedElements) else { return nil }
        self.attachmentsInfos = attachmentsInfos
        self.messagePayload = messagePayload
        self.message = message
    }
    
    private static func generateMessagePayloadAndAttachmentsInfos(from encodedElements: ObvEncoded) -> (messagePayload: Data, attachmentsInfos: [ObvNetworkFetchAttachmentInfos])? {
        guard var encodedElements = [ObvEncoded](encodedElements) else { return nil }
        guard let encodedMessagePayload = encodedElements.popLast() else { return nil }
        guard let messagePayload = Data(encodedMessagePayload) else { return nil }
        var attachmentsInfos = [ObvNetworkFetchAttachmentInfos]()
        for encodedElement in encodedElements {
            guard let attachmentInfos = generateAttachmentInfos(from: encodedElement) else { return nil }
            attachmentsInfos.append(attachmentInfos)
        }
        return (messagePayload, attachmentsInfos)
    }
    
    private static func generateAttachmentInfos(from encodedElement: ObvEncoded) -> ObvNetworkFetchAttachmentInfos? {
        guard let listOfEncodedInfos = [ObvEncoded](encodedElement) else { return nil }
        guard listOfEncodedInfos.count == 2 else { return nil }
        guard let key = try? AuthenticatedEncryptionKeyDecoder.decode(listOfEncodedInfos[0]) else { return nil }
        guard let metadata = Data(listOfEncodedInfos[1]) else { return nil }
        return ObvNetworkFetchAttachmentInfos(metadata: metadata, key: key)
    }
}

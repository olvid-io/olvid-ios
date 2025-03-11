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
import ObvTypes
import ObvCrypto


/// Type of the result returned by the channel manager when processing a received message. This type must be shared between the channel and the network managers. See also ``enum ReceivedEncryptedMessageProcessingError```
public enum ReceivedEncryptedMessageProcessingResult {
    case protocolMessageWasProcessed(messageId: ObvMessageIdentifier)
    case noKeyAllowedToDecrypt(messageId: ObvMessageIdentifier)
    case couldNotDecryptOrParse(messageId: ObvMessageIdentifier)
    case protocolManagerFailedToProcessMessage(messageId: ObvMessageIdentifier)
    case protocolMessageCouldNotBeParsed(messageId: ObvMessageIdentifier)
    case invalidAttachmentCountOfApplicationMessage(messageId: ObvMessageIdentifier)
    case remoteIdentityToSetOnReceivedMessage(messageId: ObvMessageIdentifier, remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUID: UID, messagePayload: Data, extendedMessagePayloadKey: AuthenticatedEncryptionKey?, attachmentsInfos: [ObvNetworkFetchAttachmentInfos])
    case applicationMessageCouldNotBeParsed(messageId: ObvMessageIdentifier)
    case unexpectedMessageType(messageId: ObvMessageIdentifier)
    case messageKeyDoesNotSupportGKMV2AlthoughItShould(messageId: ObvMessageIdentifier)
    case unwrapSucceededButRemoteCryptoIdIsUnknown(messageId: ObvMessageIdentifier, remoteCryptoIdentity: ObvCryptoIdentity) // Only used by PreKey channel
    case messageReceivedFromContactThatIsRevokedAsCompromised(messageId: ObvMessageIdentifier)
}

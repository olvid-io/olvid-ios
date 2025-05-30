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

public struct ObvChannelApplicationMessageToSend: ObvChannelMessageToSend {
    
    public let messageType = ObvChannelMessageType.ApplicationMessage
    public let channelType: ObvChannelSendChannelType
    public let messagePayload: Data
    public let extendedMessagePayload: Data?
    public let attachments: [Attachment]
    public let isVoipMessageForStartingCall: Bool
    
    public var withUserContent: Bool {
        channelType.withUserContent
    }
    
    public init(toContactIdentities: Set<ObvCryptoIdentity>, fromIdentity: ObvCryptoIdentity, contactDeviceIdentifiersToExclude: Set<ObvContactDeviceIdentifier>, messagePayload: Data, extendedMessagePayload: Data?, withUserContent: Bool, isVoipMessageForStartingCall: Bool, attachments: [Attachment], alsoPostToOtherOwnedDevices: Bool) {
        if alsoPostToOtherOwnedDevices {
            self.channelType = ObvChannelSendChannelType.allConfirmedObliviousChannelsOrPreKeyChannelsWithContactsAndWithOtherOwnedDevices(
                contactIdentities: toContactIdentities,
                fromOwnedIdentity: fromIdentity,
                withUserContent: withUserContent,
                contactDeviceIdentifiersToExclude: contactDeviceIdentifiersToExclude)
        } else {
            self.channelType = ObvChannelSendChannelType.allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(
                contactIdentities: toContactIdentities,
                fromOwnedIdentity: fromIdentity,
                withUserContent: withUserContent,
                contactDeviceIdentifiersToExclude: contactDeviceIdentifiersToExclude)
        }
        self.attachments = attachments
        self.messagePayload = messagePayload
        self.extendedMessagePayload = extendedMessagePayload
        self.isVoipMessageForStartingCall = isVoipMessageForStartingCall
    }
    
    
    public init(toContactDevice: ObvContactDeviceIdentifier, messagePayload: Data) {
        self.channelType = ObvChannelSendChannelType.confirmedObliviousChannelOrPreKeyChannelWithContactDevice(contactDevice: toContactDevice)
        self.messagePayload = messagePayload
        self.extendedMessagePayload = nil
        self.attachments = []
        self.isVoipMessageForStartingCall = false
    }
    
    
    public struct Attachment {
        public let fileURL: URL
        public let deleteAfterSend: Bool
        public let byteSize: Int
        public let metadata: Data
        
        public init(fileURL: URL, deleteAfterSend: Bool, byteSize: Int, metadata: Data) {
            self.fileURL = fileURL
            self.deleteAfterSend = deleteAfterSend
            self.byteSize = byteSize
            self.metadata = metadata
        }
    }
}

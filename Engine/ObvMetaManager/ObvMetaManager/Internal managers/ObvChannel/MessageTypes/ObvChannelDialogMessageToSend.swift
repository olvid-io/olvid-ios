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
import ObvEncoder
import ObvCrypto
import ObvTypes

/// Public structure used to transfer a dialog from the engine to the User Interface. This is typically used to ask the user for some confirmation during a protocol, to enter a Short Authenticated String, etc.
public struct ObvChannelDialogMessageToSend: ObvChannelMessageToSend {
    
    public let messageType = ObvChannelMessageType.DialogMessage
    
    public let channelType: ObvChannelSendChannelType
    
    public let encodedElements: ObvEncoded
    
    public let uuid: UUID
    
    public init(uuid: UUID, ownedIdentity: ObvCryptoIdentity, dialogType: ObvChannelDialogToSendType, encodedElements: ObvEncoded) {
        self.channelType = .UserInterface(uuid: uuid, ownedIdentity: ownedIdentity, dialogType: dialogType)
        self.encodedElements = encodedElements
        self.uuid = uuid
    }
}

public enum ObvChannelDialogToSendType {

    case inviteSent(contact: CryptoIdentityWithFullDisplayName) // Used within the protocol allowing establish trust
    case acceptInvite(contact: CryptoIdentityWithCoreDetails) // Used within the protocol allowing establish trust
    case invitationAccepted(contact: CryptoIdentityWithCoreDetails) // Used within the protocol allowing establish trust
    case sasExchange(contact: CryptoIdentityWithCoreDetails, sasToDisplay: Data, numberOfBadEnteredSas: Int)
    case sasConfirmed(contact: CryptoIdentityWithCoreDetails, sasToDisplay: Data, sasEntered: Data)
    case mutualTrustConfirmed(contact: CryptoIdentityWithCoreDetails)
    case acceptMediatorInvite(contact: CryptoIdentityWithCoreDetails, mediatorIdentity: ObvCryptoIdentity)
    case mediatorInviteAccepted(contact: CryptoIdentityWithCoreDetails, mediatorIdentity: ObvCryptoIdentity)
    case oneToOneInvitationSent(contact: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity)
    case oneToOneInvitationReceived(contact: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity)

    // Dialogs related to contact groups

    case acceptGroupInvite(groupInformation: GroupInformation, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, receivedMessageTimestamp: Date)
    
    // Dialogs related to contact groups V2

    case acceptGroupV2Invite(inviter: ObvCryptoId, group: ObvGroupV2)
    case freezeGroupV2Invite(inviter: ObvCryptoId, group: ObvGroupV2)

    // Dialogs related to the synchronization between owned devices
    
    case syncRequestReceivedFromOtherOwnedDevice(otherOwnedDeviceUID: UID, syncAtom: ObvSyncAtom)
    
    // A special dialog allowing a protocol instance to notify the "user interface" that is should remove any previous dialog

    case delete
}

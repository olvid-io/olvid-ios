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
import ObvUICoreData

/// This manager is used by the `PersistedDiscussionsUpdatesCoordinator`. It is used when a receiving an `ObvMessage` or an `ObvOwnedMessage` "too early". This is for example the case
/// when a contact creates a group while our second device is offline. Our first device accepts the invitation and exchanges a few messages. When our second device comes back online, it first receive the protocol
/// messages allowing to create the group. As a consequence, the engine starts downloading the group blob. This can take a "long" time. In the meantime, the app receives all the messages, discussion shared settings, etc.
/// for that group. The issue: the group does not exist yet at that time, it has yet to be created. This is where this manager comes into play: we use it to store the `ObvMessage` and `ObvOwnedMessage` that
/// must wait until the group is created. When it is created, we "replay" all the messages.
/// Note that, although we keep those messages in memory only, this process is resilient. The reason is that we do **not** call the engine completion handler when we put an `Obv(Owned)Message` to wait and thus,
/// the engine does not mark it for deletion (it keeps it in the inbox). If the app is killed, the engine will replay the exact sames messages during bootstrap.
/// When replaying a message, we do call the completion handler in the end.
actor MessagesKeptForLaterManager {
    
    enum KindOfMessageToKeepForLater {
        
        case obvMessageForGroupV2(groupIdentifier: GroupV2Identifier, obvMessage: ObvMessage)
        case obvMessageExpectingContact(contactCryptoId: ObvCryptoId, obvMessage: ObvMessage)
        case obvMessageExpectingOneToOneContact(contactCryptoId: ObvCryptoId, obvMessage: ObvMessage)
        case obvMessageExpectingGroupV2Member(groupIdentifier: GroupV2Identifier, contactCryptoId: ObvCryptoId, obvMessage: ObvMessage)
        
        case obvOwnedMessageForGroupV2(groupIdentifier: GroupV2Identifier, obvOwnedMessage: ObvOwnedMessage)
        case obvOwnedMessageExpectingContact(contactCryptoId: ObvCryptoId, obvOwnedMessage: ObvOwnedMessage)
        case obvOwnedMessageExpectingOneToOneContact(contactCryptoId: ObvCryptoId, obvOwnedMessage: ObvOwnedMessage)
        case obvOwnedMessageExpectingGroupV2Member(groupIdentifier: GroupV2Identifier, contactCryptoId: ObvCryptoId, obvOwnedMessage: ObvOwnedMessage)
        
    }
    
    private var keptGroupV2MessagesForOwnedCryptoId = [ObvCryptoId: [GroupV2Identifier: [KindOfMessageToKeepForLater]]]()
    private var keptMessagesExpectingContactForOwnedCryptoId = [ObvCryptoId: [ObvCryptoId: [KindOfMessageToKeepForLater]]]()
    private var keptMessagesExpectingOneToOneContactForOwnedCryptoId = [ObvCryptoId: [ObvCryptoId: [KindOfMessageToKeepForLater]]]()
    private var keptMessagesExpectingGroupV2Member = [ObvCryptoId: [GroupV2Identifier: [KindOfMessageToKeepForLater]]]() // Note we don't store the identity of the expected member
    
    // Keep for later PersistedMessageReceived for Groups V2
    
    func keepForLater(_ kind: KindOfMessageToKeepForLater) {
        
        switch kind {

        case .obvMessageForGroupV2(let groupIdentifier, let obvMessage):
            let ownedCryptoId = obvMessage.fromContactIdentity.ownedCryptoId
            var keptGroupV2Messages = keptGroupV2MessagesForOwnedCryptoId[ownedCryptoId, default: [GroupV2Identifier : [KindOfMessageToKeepForLater]]()]
            var keptMessages = keptGroupV2Messages[groupIdentifier, default: [KindOfMessageToKeepForLater]()]
            keptMessages.append(kind)
            keptGroupV2Messages[groupIdentifier] = keptMessages
            keptGroupV2MessagesForOwnedCryptoId[ownedCryptoId] = keptGroupV2Messages
            
        case .obvMessageExpectingContact(contactCryptoId: let contactCryptoId, obvMessage: let obvMessage):
            let ownedCryptoId = obvMessage.fromContactIdentity.ownedCryptoId
            var keptMessagesExpectingContact = keptMessagesExpectingContactForOwnedCryptoId[ownedCryptoId, default: [ObvCryptoId : [KindOfMessageToKeepForLater]]()]
            var keptMessages = keptMessagesExpectingContact[contactCryptoId, default: [KindOfMessageToKeepForLater]()]
            keptMessages.append(kind)
            keptMessagesExpectingContact[contactCryptoId] = keptMessages
            keptMessagesExpectingContactForOwnedCryptoId[ownedCryptoId] = keptMessagesExpectingContact
            
        case .obvMessageExpectingOneToOneContact(contactCryptoId: let contactCryptoId, obvMessage: let obvMessage):
            let ownedCryptoId = obvMessage.fromContactIdentity.ownedCryptoId
            var keptMessagesExpectingOneToOneContact = keptMessagesExpectingOneToOneContactForOwnedCryptoId[ownedCryptoId, default: [ObvCryptoId : [KindOfMessageToKeepForLater]]()]
            var keptMessages = keptMessagesExpectingOneToOneContact[contactCryptoId, default: [KindOfMessageToKeepForLater]()]
            keptMessages.append(kind)
            keptMessagesExpectingOneToOneContact[contactCryptoId] = keptMessages
            keptMessagesExpectingOneToOneContactForOwnedCryptoId[ownedCryptoId] = keptMessagesExpectingOneToOneContact
            
        case .obvMessageExpectingGroupV2Member(groupIdentifier: let groupIdentifier, contactCryptoId: _, obvMessage: let obvMessage):
            let ownedCryptoId = obvMessage.fromContactIdentity.ownedCryptoId
            var keptGroupV2Messages = keptMessagesExpectingGroupV2Member[ownedCryptoId, default: [GroupV2Identifier : [KindOfMessageToKeepForLater]]()]
            var keptMessages = keptGroupV2Messages[groupIdentifier, default: [KindOfMessageToKeepForLater]()]
            keptMessages.append(kind)
            keptGroupV2Messages[groupIdentifier] = keptMessages
            keptMessagesExpectingGroupV2Member[ownedCryptoId] = keptGroupV2Messages

            
        case .obvOwnedMessageForGroupV2(groupIdentifier: let groupIdentifier, obvOwnedMessage: let obvOwnedMessage):
            let ownedCryptoId = obvOwnedMessage.ownedCryptoId
            var keptGroupV2Messages = keptGroupV2MessagesForOwnedCryptoId[ownedCryptoId, default: [GroupV2Identifier : [KindOfMessageToKeepForLater]]()]
            var keptMessages = keptGroupV2Messages[groupIdentifier, default: [KindOfMessageToKeepForLater]()]
            keptMessages.append(kind)
            keptGroupV2Messages[groupIdentifier] = keptMessages
            keptGroupV2MessagesForOwnedCryptoId[ownedCryptoId] = keptGroupV2Messages
            
        case .obvOwnedMessageExpectingContact(contactCryptoId: let contactCryptoId, obvOwnedMessage: let obvOwnedMessage):
            let ownedCryptoId = obvOwnedMessage.ownedCryptoId
            var keptMessagesExpectingContact = keptMessagesExpectingContactForOwnedCryptoId[ownedCryptoId, default: [ObvCryptoId : [KindOfMessageToKeepForLater]]()]
            var keptMessages = keptMessagesExpectingContact[contactCryptoId, default: [KindOfMessageToKeepForLater]()]
            keptMessages.append(kind)
            keptMessagesExpectingContact[contactCryptoId] = keptMessages
            keptMessagesExpectingContactForOwnedCryptoId[ownedCryptoId] = keptMessagesExpectingContact
            
        case .obvOwnedMessageExpectingOneToOneContact(contactCryptoId: let contactCryptoId, obvOwnedMessage: let obvOwnedMessage):
            let ownedCryptoId = obvOwnedMessage.ownedCryptoId
            var keptMessagesExpectingOneToOneContact = keptMessagesExpectingOneToOneContactForOwnedCryptoId[ownedCryptoId, default: [ObvCryptoId : [KindOfMessageToKeepForLater]]()]
            var keptMessages = keptMessagesExpectingOneToOneContact[contactCryptoId, default: [KindOfMessageToKeepForLater]()]
            keptMessages.append(kind)
            keptMessagesExpectingOneToOneContact[contactCryptoId] = keptMessages
            keptMessagesExpectingOneToOneContactForOwnedCryptoId[ownedCryptoId] = keptMessagesExpectingOneToOneContact
            
        case .obvOwnedMessageExpectingGroupV2Member(groupIdentifier: let groupIdentifier, contactCryptoId: _, obvOwnedMessage: let obvOwnedMessage):
            let ownedCryptoId = obvOwnedMessage.ownedCryptoId
            var keptGroupV2Messages = keptMessagesExpectingGroupV2Member[ownedCryptoId, default: [GroupV2Identifier : [KindOfMessageToKeepForLater]]()]
            var keptMessages = keptGroupV2Messages[groupIdentifier, default: [KindOfMessageToKeepForLater]()]
            keptMessages.append(kind)
            keptGroupV2Messages[groupIdentifier] = keptMessages
            keptMessagesExpectingGroupV2Member[ownedCryptoId] = keptGroupV2Messages

        }
        
    }
    
    
    func getGroupV2MessagesKeptForLaterForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId, groupIdentifier: GroupV2Identifier) -> [KindOfMessageToKeepForLater] {
        guard var keptGroupV2Messages = keptGroupV2MessagesForOwnedCryptoId[ownedCryptoId] else { return [] }
        let keptForLater = keptGroupV2Messages.removeValue(forKey: groupIdentifier) ?? [KindOfMessageToKeepForLater]()
        keptGroupV2MessagesForOwnedCryptoId[ownedCryptoId] = keptGroupV2Messages
        return keptForLater
    }
    
    
    func getMessagesExpectingContactForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) -> [KindOfMessageToKeepForLater] {
        guard var keptMessagesExpectingContact = keptMessagesExpectingContactForOwnedCryptoId[ownedCryptoId] else { return [] }
        guard let keptForLater = keptMessagesExpectingContact.removeValue(forKey: contactCryptoId) else { return [] }
        keptMessagesExpectingContactForOwnedCryptoId[ownedCryptoId] = keptMessagesExpectingContact
        return keptForLater
    }
    
    
    func getMessagesExpectingOneToOneContactForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) -> [KindOfMessageToKeepForLater] {
        guard var keptMessagesExpectingOneToOneContact = keptMessagesExpectingOneToOneContactForOwnedCryptoId[ownedCryptoId] else { return [] }
        guard let keptForLater = keptMessagesExpectingOneToOneContact.removeValue(forKey: contactCryptoId) else { return [] }
        keptMessagesExpectingOneToOneContactForOwnedCryptoId[ownedCryptoId] = keptMessagesExpectingOneToOneContact
        return keptForLater
    }

    
    func getMessagesExpectingGroupV2Member(_ ownedCryptoId: ObvCryptoId, groupIdentifier: GroupV2Identifier) -> [KindOfMessageToKeepForLater] {
        guard var keptGroupV2Messages = keptMessagesExpectingGroupV2Member[ownedCryptoId] else { return [] }
        let keptForLater = keptGroupV2Messages.removeValue(forKey: groupIdentifier) ?? [KindOfMessageToKeepForLater]()
        keptMessagesExpectingGroupV2Member[ownedCryptoId] = keptGroupV2Messages
        return keptForLater
    }
    
}

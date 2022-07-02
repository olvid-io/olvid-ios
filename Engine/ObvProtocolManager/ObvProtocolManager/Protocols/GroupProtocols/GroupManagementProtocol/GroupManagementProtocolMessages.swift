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
import ObvTypes
import ObvCrypto
import ObvMetaManager

// MARK: - Protocol Messages

extension GroupManagementProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        
        case InitiateGroupCreation = 0
        case PropagateGroupCreation = 1
        case GroupMembersChangedTrigger = 2
        case NewMembers = 3
        case AddGroupMembers = 4
        case RemoveGroupMembers = 5
        case KickFromGroup = 6
        case NotifyGroupLeft = 7
        case LeaveGroupJoined = 10
        case InitiateGroupMembersQuery = 11
        case QueryGroupMembers = 12
        case TriggerReinvite = 13
        case TriggerUpdateMembers = 14
        case UploadGroupPhoto = 15

        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .InitiateGroupCreation           : return InitiateGroupCreationMessage.self
            case .PropagateGroupCreation          : return PropagateGroupCreationMessage.self
            case .GroupMembersChangedTrigger      : return GroupMembersChangedTriggerMessage.self
            case .NewMembers                      : return NewMembersMessage.self
            case .AddGroupMembers                 : return AddGroupMembersMessage.self
            case .RemoveGroupMembers              : return RemoveGroupMembersMessage.self
            case .KickFromGroup                   : return KickFromGroupMessage.self
            case .LeaveGroupJoined                : return LeaveGroupJoinedMessage.self
            case .NotifyGroupLeft                 : return NotifyGroupLeftMessage.self
            case .InitiateGroupMembersQuery       : return InitiateGroupMembersQueryMessage.self
            case .QueryGroupMembers               : return QueryGroupMembersMessage.self
            case .TriggerReinvite                 : return TriggerReinviteMessage.self
            case .TriggerUpdateMembers            : return TriggerUpdateMembersMessage.self
            case .UploadGroupPhoto                : return UploadGroupPhotoMessage.self
            }
        }
    }
    
    
    // MARK: - InitiateGroupCreationMessage
    
    struct InitiateGroupCreationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.InitiateGroupCreation
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformationWithPhoto: GroupInformationWithPhoto
        let pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>
        
        var encodedInputs: [ObvEncoded] {
            let encodedMembers = (pendingGroupMembers.map { $0.obvEncode() }).obvEncode()
            return [groupInformationWithPhoto.obvEncode(), encodedMembers]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { throw NSError() }
            self.groupInformationWithPhoto = try message.encodedInputs[0].obvDecode()
            guard let listOfEncodedMembers = [ObvEncoded](message.encodedInputs[1]) else { throw NSError() }
            self.pendingGroupMembers = try Set(listOfEncodedMembers.map { try $0.obvDecode() })
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformationWithPhoto: GroupInformationWithPhoto, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformationWithPhoto = groupInformationWithPhoto
            self.pendingGroupMembers = pendingGroupMembers
        }
        
    }

    
    // MARK: - PropagateGroupCreationMessage
    
    struct PropagateGroupCreationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.PropagateGroupCreation
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        let pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>
        
        var encodedInputs: [ObvEncoded] {
            let encodedMembers = (pendingGroupMembers.map { $0.obvEncode() }).obvEncode()
            return [groupInformation.obvEncode(),
                    encodedMembers]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { throw NSError() }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
            guard let listOfEncodedMembers = [ObvEncoded](message.encodedInputs[1]) else { throw NSError() }
            self.pendingGroupMembers = try Set(listOfEncodedMembers.map { try $0.obvDecode() })
            
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
            self.pendingGroupMembers = pendingGroupMembers
        }
        
    }

    
    // MARK: - GroupMembersChangedTriggerMessage
    
    struct GroupMembersChangedTriggerMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.GroupMembersChangedTrigger
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { throw NSError() }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
            
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
        }
        
    }

    
    // MARK: - NewMembersMessage
    
    struct NewMembersMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.NewMembers
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        let groupMembers: Set<CryptoIdentityWithCoreDetails>
        let pendingMembers: Set<CryptoIdentityWithCoreDetails>
        let groupMembersVersion: Int
        
        var encodedInputs: [ObvEncoded] {
            let encodedMembers = (groupMembers.map { $0.obvEncode() }).obvEncode()
            let encodedPendings = (pendingMembers.map { $0.obvEncode() }).obvEncode()
            return [groupInformation.obvEncode(),
                    encodedMembers,
                    encodedPendings,
                    groupMembersVersion.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 4 else { throw NSError() }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
            guard let listOfEncodedMembers = [ObvEncoded](message.encodedInputs[1]) else { throw NSError() }
            self.groupMembers = try Set(listOfEncodedMembers.map { try $0.obvDecode() })
            guard let listOfEncodedPendingMembers = [ObvEncoded](message.encodedInputs[2]) else { throw NSError() }
            self.pendingMembers = try Set(listOfEncodedPendingMembers.map { try $0.obvDecode() })
            self.groupMembersVersion = try message.encodedInputs[3].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation, groupMembers: Set<CryptoIdentityWithCoreDetails>, pendingMembers: Set<CryptoIdentityWithCoreDetails>, groupMembersVersion: Int) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
            self.groupMembers = groupMembers
            self.pendingMembers = pendingMembers
            self.groupMembersVersion = groupMembersVersion
        }
        
    }

    
    // MARK: - AddGroupMembersMessage
    
    struct AddGroupMembersMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.AddGroupMembers
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        let newGroupMembers: Set<ObvCryptoIdentity>
        
        var encodedInputs: [ObvEncoded] {
            let encodedMembers = (newGroupMembers.map { $0.obvEncode() }).obvEncode()
            return [groupInformation.obvEncode(),
                    encodedMembers]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { throw NSError() }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
            guard let listOfEncodedMembers = [ObvEncoded](message.encodedInputs[1]) else { throw NSError() }
            self.newGroupMembers = try Set(listOfEncodedMembers.map { try $0.obvDecode() })
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation, newGroupMembers: Set<ObvCryptoIdentity>) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
            self.newGroupMembers = newGroupMembers
        }
        
    }

    
    // MARK: - RemoveGroupMembersMessage
    
    struct RemoveGroupMembersMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.RemoveGroupMembers
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        let removedGroupMembers: Set<ObvCryptoIdentity>
        
        var encodedInputs: [ObvEncoded] {
            let encodedMembers = (removedGroupMembers.map { $0.obvEncode() }).obvEncode()
            return [groupInformation.obvEncode(),
                    encodedMembers]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { throw NSError() }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
            guard let listOfEncodedMembers = [ObvEncoded](message.encodedInputs[1]) else { throw NSError() }
            self.removedGroupMembers = try Set(listOfEncodedMembers.map { try $0.obvDecode() })
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation, removedGroupMembers: Set<ObvCryptoIdentity>) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
            self.removedGroupMembers = removedGroupMembers
        }
        
    }

    
    // MARK: - KickFromGroupMessage
    
    struct KickFromGroupMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.KickFromGroup
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { throw NSError() }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
        }
        
    }

    
    // MARK: - LeaveGroupJoinedMessage
    
    struct LeaveGroupJoinedMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.LeaveGroupJoined
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { throw NSError() }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
        }
        
    }

    
    // MARK: - NotifyGroupLeftMessage
    
    struct NotifyGroupLeftMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.NotifyGroupLeft
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { throw NSError() }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
        }
        
    }

    
    // MARK: - InitiateGroupMembersQueryMessage
    
    struct InitiateGroupMembersQueryMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.InitiateGroupMembersQuery
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { throw NSError() }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
        }

    }
    
    
    // MARK: - QueryGroupMembersMessage
    
    struct QueryGroupMembersMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.QueryGroupMembers
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { throw NSError() }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
        }
        
    }
    
    
    // MARK: - TriggerReinviteMessage
    
    struct TriggerReinviteMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.TriggerReinvite
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        let memberIdentity: ObvCryptoIdentity
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode(), memberIdentity.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { throw NSError() }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
            self.memberIdentity = try message.encodedInputs[1].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation, memberIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
            self.memberIdentity = memberIdentity
        }
        
    }

    
    // MARK: - TriggerUpdateMembersMessage
    
    struct TriggerUpdateMembersMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.TriggerUpdateMembers
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        let memberIdentity: ObvCryptoIdentity
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode(), memberIdentity.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { throw NSError() }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
            self.memberIdentity = try message.encodedInputs[1].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation, memberIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
            self.memberIdentity = memberIdentity
        }
        
    }

    // MARK: - UploadGroupPhotoMessage

    struct UploadGroupPhotoMessage: ConcreteProtocolMessage {

        var id: ConcreteProtocolMessageId = MessageId.UploadGroupPhoto
        let coreProtocolMessage: CoreProtocolMessage

        let groupInformation: GroupInformation

        var encodedInputs: [ObvEncoded] { [groupInformation.obvEncode()] }

        // Initializers

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { throw NSError() }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
        }

        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
        }


    }

}

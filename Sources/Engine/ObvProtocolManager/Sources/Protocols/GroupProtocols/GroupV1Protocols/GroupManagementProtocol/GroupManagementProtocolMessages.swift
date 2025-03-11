/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
        
        case initiateGroupCreation = 0
        case propagateGroupCreation = 1
        case groupMembersChangedTrigger = 2
        case newMembers = 3
        case addGroupMembers = 4
        case removeGroupMembers = 5
        case kickFromGroup = 6
        case notifyGroupLeft = 7
        // case reinvitePendingMember = 8 // Not implemented under iOS
        case disbandGroup = 9
        case leaveGroupJoined = 10
        case initiateGroupMembersQuery = 11
        case queryGroupMembers = 12
        case triggerReinvite = 13
        case triggerUpdateMembers = 14
        case uploadGroupPhoto = 15
        case propagateReinvitePendingMember = 16
        case propagateDisbandGroup = 17
        case propagateLeaveGroup = 18

        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initiateGroupCreation          : return InitiateGroupCreationMessage.self
            case .propagateGroupCreation         : return PropagateGroupCreationMessage.self
            case .groupMembersChangedTrigger     : return GroupMembersChangedTriggerMessage.self
            case .newMembers                     : return NewMembersMessage.self
            case .addGroupMembers                : return AddGroupMembersMessage.self
            case .removeGroupMembers             : return RemoveGroupMembersMessage.self
            case .kickFromGroup                  : return KickFromGroupMessage.self
            case .leaveGroupJoined               : return LeaveGroupJoinedMessage.self
            case .notifyGroupLeft                : return NotifyGroupLeftMessage.self
            // case .reinvitePendingMember          : return ReinvitePendingMemberMessage.self
            case .disbandGroup                   : return DisbandGroupMessage.self
            case .initiateGroupMembersQuery      : return InitiateGroupMembersQueryMessage.self
            case .queryGroupMembers              : return QueryGroupMembersMessage.self
            case .triggerReinvite                : return TriggerReinviteMessage.self
            case .triggerUpdateMembers           : return TriggerUpdateMembersMessage.self
            case .uploadGroupPhoto               : return UploadGroupPhotoMessage.self
            case .propagateReinvitePendingMember : return PropagateReinvitePendingMemberMessage.self
            case .propagateDisbandGroup          : return PropagateDisbandGroupMessage.self
            case .propagateLeaveGroup            : return PropagateLeaveGroupMessage.self
            }
        }
    }
    
    
    // MARK: - InitiateGroupCreationMessage
    
    struct InitiateGroupCreationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateGroupCreation
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
            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupInformationWithPhoto = try message.encodedInputs[0].obvDecode()
            guard let listOfEncodedMembers = [ObvEncoded](message.encodedInputs[1]) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded members") }
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
        
        let id: ConcreteProtocolMessageId = MessageId.propagateGroupCreation
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
            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
            guard let listOfEncodedMembers = [ObvEncoded](message.encodedInputs[1]) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded members") }
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
        
        let id: ConcreteProtocolMessageId = MessageId.groupMembersChangedTrigger
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
            
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
        }
        
    }

    
    // MARK: - NewMembersMessage
    
    struct NewMembersMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.newMembers
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
            guard message.encodedInputs.count == 4 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
            guard let listOfEncodedMembers = [ObvEncoded](message.encodedInputs[1]) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded members") }
            self.groupMembers = try Set(listOfEncodedMembers.map { try $0.obvDecode() })
            guard let listOfEncodedPendingMembers = [ObvEncoded](message.encodedInputs[2]) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded pending members") }
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
        
        let id: ConcreteProtocolMessageId = MessageId.addGroupMembers
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
            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
            guard let listOfEncodedMembers = [ObvEncoded](message.encodedInputs[1]) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded members") }
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
        
        let id: ConcreteProtocolMessageId = MessageId.removeGroupMembers
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
            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
            guard let listOfEncodedMembers = [ObvEncoded](message.encodedInputs[1]) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded members") }
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
        
        let id: ConcreteProtocolMessageId = MessageId.kickFromGroup
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
        }
        
    }

    
    // MARK: - LeaveGroupJoinedMessage
    
    struct LeaveGroupJoinedMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.leaveGroupJoined
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
        }
        
    }

    
    // MARK: - NotifyGroupLeftMessage
    
    struct NotifyGroupLeftMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.notifyGroupLeft
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
        }
        
    }

    
    // MARK: - ReinvitePendingMemberMessage (not implemented under iOS)
    
//    struct ReinvitePendingMemberMessage: ConcreteProtocolMessage {
//        
//        let id: ConcreteProtocolMessageId = MessageId.reinvitePendingMember
//        let coreProtocolMessage: CoreProtocolMessage
//        
//        let groupInformation: GroupInformation
//        let pendingMemberIdentity: ObvCryptoIdentity
//        
//        var encodedInputs: [ObvEncoded] {
//            return [groupInformation.obvEncode(), pendingMemberIdentity.obvEncode()]
//        }
//        
//        // Initializers
//        
//        init(with message: ReceivedMessage) throws {
//            self.coreProtocolMessage = CoreProtocolMessage(with: message)
//            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
//            self.groupInformation = try message.encodedInputs[0].obvDecode()
//            let rawPendingMemberIdentity: Data = try message.encodedInputs[1].obvDecode()
//            guard let cryptoId = ObvCryptoIdentity(from: rawPendingMemberIdentity) else { assertionFailure(); throw ObvError.couldNotDecodeIdentity }
//            self.pendingMemberIdentity = cryptoId
//        }
//        
//        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation, pendingMemberIdentity: ObvCryptoIdentity) {
//            self.coreProtocolMessage = coreProtocolMessage
//            self.groupInformation = groupInformation
//            self.pendingMemberIdentity = pendingMemberIdentity
//        }
//        
//        enum ObvError: Error {
//            case couldNotDecodeIdentity
//        }
//        
//    }

    
    // MARK: - DisbandGroupMessage
    
    struct DisbandGroupMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.disbandGroup
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
        }
        
    }

    
    // MARK: - PropagateReinvitePendingMemberMessage
    
    struct PropagateReinvitePendingMemberMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagateReinvitePendingMember
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        let pendingMemberIdentity: ObvCryptoIdentity
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode(), pendingMemberIdentity.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
            let rawPendingMemberIdentity: Data = try message.encodedInputs[1].obvDecode()
            guard let cryptoId = ObvCryptoIdentity(from: rawPendingMemberIdentity) else { assertionFailure(); throw ObvError.couldNotDecodeIdentity }
            self.pendingMemberIdentity = cryptoId
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation, pendingMemberIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
            self.pendingMemberIdentity = pendingMemberIdentity
        }
        
        enum ObvError: Error {
            case couldNotDecodeIdentity
        }
        
    }

    
    // MARK: - PropagateDisbandGroupMessage
    
    struct PropagateDisbandGroupMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagateDisbandGroup
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
        }
        
    }
    
    // MARK: PropagateLeaveGroupMessage

    struct PropagateLeaveGroupMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagateLeaveGroup
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
        }
        
    }

    // MARK: - InitiateGroupMembersQueryMessage
    
    struct InitiateGroupMembersQueryMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateGroupMembersQuery
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
        }

    }
    
    
    // MARK: - QueryGroupMembersMessage
    
    struct QueryGroupMembersMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.queryGroupMembers
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
        }
        
    }
    
    
    // MARK: - TriggerReinviteMessage
    
    struct TriggerReinviteMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.triggerReinvite
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        let memberIdentity: ObvCryptoIdentity
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode(), memberIdentity.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
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
        
        let id: ConcreteProtocolMessageId = MessageId.triggerUpdateMembers
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        let memberIdentity: ObvCryptoIdentity
        
        var encodedInputs: [ObvEncoded] {
            return [groupInformation.obvEncode(), memberIdentity.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
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

        var id: ConcreteProtocolMessageId = MessageId.uploadGroupPhoto
        let coreProtocolMessage: CoreProtocolMessage

        let groupInformation: GroupInformation

        var encodedInputs: [ObvEncoded] { [groupInformation.obvEncode()] }

        // Initializers

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
        }

        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
        }


    }

}

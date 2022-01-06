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

// MARK: - Protocol States

extension GroupInvitationProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case InitialState = 0
        case InvitationSent = 1
        case InvitationReceived = 2
        case ResponseSent = 3
        case ResponseReceived = 4
        case Cancelled = 5
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .InitialState       : return ConcreteProtocolInitialState.self
            case .InvitationSent     : return InvitationSentState.self
            case .InvitationReceived : return InvitationReceivedState.self
            case .ResponseSent       : return ResponseSentState.self
            case .ResponseReceived   : return ResponseReceivedState.self
            case .Cancelled          : return CancelledState.self
            }
        }
    }

    
    // MARK: - InvitationSentState
    
    struct InvitationSentState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.InvitationSent
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func encode() -> ObvEncoded { return 0.encode() }

    }

    
    // MARK: - InvitationReceivedState
    
    struct InvitationReceivedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.InvitationReceived
        
        let groupInformation: GroupInformation
        let dialogUuid: UUID
        let pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>

        func encode() -> ObvEncoded {
            let encodedMembers = (pendingGroupMembers.map { $0.encode() }).encode()
            return [groupInformation.encode(),
                    dialogUuid.encode(),
                    encodedMembers].encode()
        }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 3) else { throw NSError() }
            self.groupInformation = try encodedElements[0].decode()
            self.dialogUuid = try encodedElements[1].decode()
            guard let listOfEncodedMembers = [ObvEncoded](encodedElements[2]) else { throw NSError() }
            self.pendingGroupMembers = Set(try listOfEncodedMembers.map { try $0.decode() })
        }

        init(groupInformation: GroupInformation, dialogUuid: UUID, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>) {
            self.groupInformation = groupInformation
            self.dialogUuid = dialogUuid
            self.pendingGroupMembers = pendingGroupMembers
        }
        
    }

    
    // MARK: - ResponseSentState
    
    struct ResponseSentState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.ResponseSent
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func encode() -> ObvEncoded { return 0.encode() }
        
    }

    
    // MARK: - ResponseReceivedState
    
    struct ResponseReceivedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.ResponseReceived
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func encode() -> ObvEncoded { return 0.encode() }
        
    }
    

    // MARK: - CancelledState
    
    struct CancelledState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.Cancelled
        
        init(_: ObvEncoded) throws {}
        
        init() {}
        
        func encode() -> ObvEncoded { return 0.encode() }
        
    }

}

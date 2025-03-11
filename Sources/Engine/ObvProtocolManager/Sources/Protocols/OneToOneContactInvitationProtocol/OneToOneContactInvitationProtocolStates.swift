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
import ObvCrypto


extension OneToOneContactInvitationProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case initial = 0
        case invitationSent = 1
        case invitationReceived = 2
        case finished = 3
        case cancelled = 4

        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .initial            : return ConcreteProtocolInitialState.self
            case .invitationSent     : return InvitationSentState.self
            case .invitationReceived : return InvitationReceivedState.self
            case .finished           : return FinishedState.self
            case .cancelled          : return CancelledState.self
            }
        }
        
    }

    
    struct InvitationSentState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.invitationSent

        let contactIdentity: ObvCryptoIdentity
        let dialogUuid: UUID
        
        func obvEncode() -> ObvEncoded { [contactIdentity, dialogUuid].obvEncode() }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 2) else {
                throw Self.makeError(message: "Could not get list of encoded elements for InvitationSentState")
            }
            self.contactIdentity = try encodedElements[0].obvDecode()
            self.dialogUuid = try encodedElements[1].obvDecode()
        }

        init(contactIdentity: ObvCryptoIdentity, dialogUuid: UUID) {
            self.contactIdentity = contactIdentity
            self.dialogUuid = dialogUuid
        }

    }

    
    struct InvitationReceivedState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.invitationReceived

        let contactIdentity: ObvCryptoIdentity
        let dialogUuid: UUID
        
        func obvEncode() -> ObvEncoded { [contactIdentity, dialogUuid].obvEncode() }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 2) else {
                throw Self.makeError(message: "Could not get list of encoded elements for InvitationReceivedState")
            }
            self.contactIdentity = try encodedElements[0].obvDecode()
            self.dialogUuid = try encodedElements[1].obvDecode()
        }

        init(contactIdentity: ObvCryptoIdentity, dialogUuid: UUID) {
            self.contactIdentity = contactIdentity
            self.dialogUuid = dialogUuid
        }

    }

    
    struct FinishedState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.finished

        init(_: ObvEncoded) {}

        init() {}

        func obvEncode() -> ObvEncoded { return 0.obvEncode() }

    }

    
    struct CancelledState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.cancelled
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
    }

}

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


extension OneToOneContactInvitationProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case Initial = 0
        case InvitationSent = 1
        case InvitationReceived = 2
        case Finished = 3
        case Cancelled = 4

        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .Initial            : return ConcreteProtocolInitialState.self
            case .InvitationSent     : return InvitationSentState.self
            case .InvitationReceived : return InvitationReceivedState.self
            case .Finished           : return FinishedState.self
            case .Cancelled          : return CancelledState.self
            }
        }
        
    }

    
    struct InvitationSentState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.InvitationSent

        let contactIdentity: ObvCryptoIdentity
        let dialogUuid: UUID
        
        func obvEncode() -> ObvEncoded { [contactIdentity, dialogUuid].obvEncode() }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 2) else { throw NSError() }
            self.contactIdentity = try encodedElements[0].obvDecode()
            self.dialogUuid = try encodedElements[1].obvDecode()
        }

        init(contactIdentity: ObvCryptoIdentity, dialogUuid: UUID) {
            self.contactIdentity = contactIdentity
            self.dialogUuid = dialogUuid
        }

    }

    
    struct InvitationReceivedState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.InvitationReceived

        let contactIdentity: ObvCryptoIdentity
        let dialogUuid: UUID
        
        func obvEncode() -> ObvEncoded { [contactIdentity, dialogUuid].obvEncode() }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 2) else { throw NSError() }
            self.contactIdentity = try encodedElements[0].obvDecode()
            self.dialogUuid = try encodedElements[1].obvDecode()
        }

        init(contactIdentity: ObvCryptoIdentity, dialogUuid: UUID) {
            self.contactIdentity = contactIdentity
            self.dialogUuid = dialogUuid
        }

    }

    
    struct FinishedState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.Finished

        init(_: ObvEncoded) {}

        init() {}

        func obvEncode() -> ObvEncoded { return 0.obvEncode() }

    }

    
    struct CancelledState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.Cancelled
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
    }

}

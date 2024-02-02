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
import ObvTypes


// MARK: - Protocol States

extension ContactMutualIntroductionProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case initialState = 0

        // Mediator's side
        case contactsIntroduced = 1
        
        // Contacts' sides
        case invitationReceived = 2
        case invitationRejected = 4
        case invitationAccepted = 3
        case waitingForAck = 5
        case mutualTrustEstablished = 6
        case cancelled = 7
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .initialState           : return ConcreteProtocolInitialState.self
            case .contactsIntroduced     : return ContactsIntroducedState.self
            case .invitationReceived     : return InvitationReceivedState.self
            case .invitationRejected     : return InvitationRejectedState.self
            case .invitationAccepted     : return InvitationAcceptedState.self
            case .waitingForAck          : return WaitingForAckState.self
            case .mutualTrustEstablished : return MutualTrustEstablishedState.self
            case .cancelled              : return CancelledState.self
            }
        }
    }
    
    
    // MARK: - ContactsIntroducedState
    
    struct ContactsIntroducedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.contactsIntroduced
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }

    }
    
    
    // MARK: - InvitationReceivedState
    
    struct InvitationReceivedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.invitationReceived
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let mediatorIdentity: ObvCryptoIdentity
        let dialogUuid: UUID

        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityDetails: Data
            (contactIdentity, encodedContactIdentityDetails, mediatorIdentity, dialogUuid) = try encoded.obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityDetails)
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, mediatorIdentity: ObvCryptoIdentity, dialogUuid: UUID) {
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.mediatorIdentity = mediatorIdentity
            self.dialogUuid = dialogUuid
        }
        
        func obvEncode() -> ObvEncoded {
            let encodedContactIdentityDetails = try! contactIdentityCoreDetails.jsonEncode()
            return [contactIdentity, encodedContactIdentityDetails, mediatorIdentity, dialogUuid].obvEncode()
        }

    }
    
    
    // MARK: - InvitationRejectedState
    
    struct InvitationRejectedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.invitationRejected
        
        init(_: ObvEncoded) throws {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }

    }
    
    
    // MARK: - InvitationAcceptedState
    
    struct InvitationAcceptedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.invitationAccepted
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let mediatorIdentity: ObvCryptoIdentity
        let dialogUuid: UUID
        let acceptType: Int // See the AcceptType structure within ContactMutualIntroductionProtocol

        func obvEncode() -> ObvEncoded {
            let encodedContactIdentityDetails = try! contactIdentityCoreDetails.jsonEncode()
            return [contactIdentity, encodedContactIdentityDetails, mediatorIdentity, dialogUuid, acceptType].obvEncode()
        }

        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityDetails: Data
            (contactIdentity, encodedContactIdentityDetails, mediatorIdentity, dialogUuid, acceptType) = try encoded.obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityDetails)
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, mediatorIdentity: ObvCryptoIdentity, dialogUuid: UUID, acceptType: Int) {
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.mediatorIdentity = mediatorIdentity
            self.dialogUuid = dialogUuid
            self.acceptType = acceptType
        }
        

    }
    
    
    // MARK: - WaitingForAckState
    
    struct WaitingForAckState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.waitingForAck
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let mediatorIdentity: ObvCryptoIdentity
        let dialogUuid: UUID
        let acceptType: Int // See the AcceptType structure within ContactMutualIntroductionProtocol

        func obvEncode() -> ObvEncoded {
            let encodedContactIdentityDetails = try! contactIdentityCoreDetails.jsonEncode()
            return [contactIdentity, encodedContactIdentityDetails, mediatorIdentity, dialogUuid, acceptType].obvEncode()
        }

        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityDetails: Data
            (contactIdentity, encodedContactIdentityDetails, mediatorIdentity, dialogUuid, acceptType) = try encoded.obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityDetails)
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, mediatorIdentity: ObvCryptoIdentity, dialogUuid: UUID, acceptType: Int) {
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.mediatorIdentity = mediatorIdentity
            self.dialogUuid = dialogUuid
            self.acceptType = acceptType
        }
        

    }
    
    
    // MARK: - MutualTrustEstablishedState
    
    struct MutualTrustEstablishedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.mutualTrustEstablished
        
        init(_: ObvEncoded) throws {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
        
    }
    
    
    // MARK: - CancelledState
    
    struct CancelledState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.cancelled
        
        init(_: ObvEncoded) throws {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
        
    }

}

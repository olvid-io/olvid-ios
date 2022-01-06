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


// MARK: - Protocol States

extension ContactMutualIntroductionProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case InitialState = 0

        // Mediator's side
        case ContactsIntroduced = 1
        
        // Contacts' sides
        case InvitationReceived = 2
        case InvitationRejected = 4
        case InvitationAccepted = 3
        case WaitingForAck = 5
        case MutualTrustEstablished = 6
        case Cancelled = 7
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .InitialState           : return ConcreteProtocolInitialState.self
            case .ContactsIntroduced     : return ContactsIntroducedState.self
            case .InvitationReceived     : return InvitationReceivedState.self
            case .InvitationRejected     : return InvitationRejectedState.self
            case .InvitationAccepted     : return InvitationAcceptedState.self
            case .WaitingForAck          : return WaitingForAckState.self
            case .MutualTrustEstablished : return MutualTrustEstablishedState.self
            case .Cancelled              : return CancelledState.self
            }
        }
    }
    
    
    // MARK: - ContactsIntroducedState
    
    struct ContactsIntroducedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.ContactsIntroduced
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func encode() -> ObvEncoded { return 0.encode() }

    }
    
    
    // MARK: - InvitationReceivedState
    
    struct InvitationReceivedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.InvitationReceived
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let mediatorIdentity: ObvCryptoIdentity
        let dialogUuid: UUID

        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityDetails: Data
            (contactIdentity, encodedContactIdentityDetails, mediatorIdentity, dialogUuid) = try encoded.decode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityDetails)
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, mediatorIdentity: ObvCryptoIdentity, dialogUuid: UUID) {
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.mediatorIdentity = mediatorIdentity
            self.dialogUuid = dialogUuid
        }
        
        func encode() -> ObvEncoded {
            let encodedContactIdentityDetails = try! contactIdentityCoreDetails.encode()
            return [contactIdentity, encodedContactIdentityDetails, mediatorIdentity, dialogUuid].encode()
        }

    }
    
    
    // MARK: - InvitationRejectedState
    
    struct InvitationRejectedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.InvitationRejected
        
        init(_: ObvEncoded) throws {}
        
        init() {}
        
        func encode() -> ObvEncoded { return 0.encode() }

    }
    
    
    // MARK: - InvitationAcceptedState
    
    struct InvitationAcceptedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.InvitationAccepted
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let mediatorIdentity: ObvCryptoIdentity
        let dialogUuid: UUID
        let acceptType: Int // See the AcceptType structure within ContactMutualIntroductionProtocol

        func encode() -> ObvEncoded {
            let encodedContactIdentityDetails = try! contactIdentityCoreDetails.encode()
            return [contactIdentity, encodedContactIdentityDetails, mediatorIdentity, dialogUuid, acceptType].encode()
        }

        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityDetails: Data
            (contactIdentity, encodedContactIdentityDetails, mediatorIdentity, dialogUuid, acceptType) = try encoded.decode()
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
        
        let id: ConcreteProtocolStateId = StateId.WaitingForAck
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let mediatorIdentity: ObvCryptoIdentity
        let dialogUuid: UUID
        let acceptType: Int // See the AcceptType structure within ContactMutualIntroductionProtocol

        func encode() -> ObvEncoded {
            let encodedContactIdentityDetails = try! contactIdentityCoreDetails.encode()
            return [contactIdentity, encodedContactIdentityDetails, mediatorIdentity, dialogUuid, acceptType].encode()
        }

        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityDetails: Data
            (contactIdentity, encodedContactIdentityDetails, mediatorIdentity, dialogUuid, acceptType) = try encoded.decode()
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
        
        let id: ConcreteProtocolStateId = StateId.MutualTrustEstablished
        
        init(_: ObvEncoded) throws {}
        
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

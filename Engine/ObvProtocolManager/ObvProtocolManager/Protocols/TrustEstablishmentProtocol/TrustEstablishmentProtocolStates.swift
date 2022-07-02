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
import CoreData
import os.log
import ObvCrypto
import ObvEncoder
import ObvTypes
import ObvOperation
import ObvMetaManager

// MARK: - Protocol States

extension TrustEstablishmentProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case InitialState = 0
        // Alice's side
        case WaitingForSeed = 1
        // Bob's side
        case WaitingForConfirmation = 2
        case WaitingForDecommitment = 6
        // On Alice's and Bob's sides
        case WaitingForUserSAS = 7
        case ContactIdentityTrusted = 8
        case MutualTrustConfirmed = 9
        case Cancelled = 10
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .InitialState                  : return ConcreteProtocolInitialState.self
            case .WaitingForSeed                : return WaitingForSeedState.self
            case .WaitingForConfirmation        : return WaitingForConfirmationState.self
            case .WaitingForDecommitment        : return WaitingForDecommitmentState.self
            case .WaitingForUserSAS             : return WaitingForUserSASState.self
            case .ContactIdentityTrusted        : return ContactIdentityTrustedState.self
            case .MutualTrustConfirmed          : return MutualTrustConfirmedState.self
            case .Cancelled                     : return CancelledState.self
            }
        }
        
    }
    
    
    struct WaitingForSeedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.WaitingForSeed
        
        let contactIdentity: ObvCryptoIdentity // The contact identity we seek to trust
        let decommitment: Data
        let seedForSas: Seed
        let dialogUuid: UUID
        
        func obvEncode() -> ObvEncoded {
            return [contactIdentity, decommitment, seedForSas, dialogUuid].obvEncode()
        }

        init(_ encoded: ObvEncoded) throws {
            (contactIdentity, decommitment, seedForSas, dialogUuid) = try encoded.obvDecode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, decommitment: Data, seedForSas: Seed, dialogUuid: UUID) {
            self.contactIdentity = contactIdentity
            self.decommitment = decommitment
            self.seedForSas = seedForSas
            self.dialogUuid = dialogUuid
        }
        
    }
    
    
    struct WaitingForConfirmationState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.WaitingForConfirmation
        
        let contactIdentity: ObvCryptoIdentity // The contact identity we seek to trust
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let contactDeviceUids: [UID]
        let commitment: Data
        let dialogUuid: UUID
        
        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityCoreDetails: Data
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 5) else { throw NSError() }
            contactIdentity = try encodedElements[0].obvDecode()
            encodedContactIdentityCoreDetails = try encodedElements[1].obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            contactDeviceUids = try TrustEstablishmentProtocol.decodeEncodedListOfDeviceUids(encodedElements[2])
            commitment = try encodedElements[3].obvDecode()
            dialogUuid = try encodedElements[4].obvDecode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, contactDeviceUids: [UID], commitment: Data, dialogUuid: UUID) {
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.contactDeviceUids = contactDeviceUids
            self.commitment = commitment
            self.dialogUuid = dialogUuid
        }
        
        func obvEncode() -> ObvEncoded {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.jsonEncode()
            return [contactIdentity,
                    encodedContactIdentityCoreDetails,
                    contactDeviceUids as [ObvEncodable],
                    commitment,
                    dialogUuid].obvEncode()
        }
    }
    
    
    
    struct WaitingForDecommitmentState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.WaitingForDecommitment
        
        let contactIdentity: ObvCryptoIdentity // The contact identity we seek to trust
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let contactDeviceUids: [UID]
        let commitment: Data
        let seedForSas: Seed
        let dialogUuid: UUID
        
        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityCoreDetails: Data
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 6) else { throw NSError() }
            contactIdentity = try encodedElements[0].obvDecode()
            encodedContactIdentityCoreDetails = try encodedElements[1].obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            contactDeviceUids = try TrustEstablishmentProtocol.decodeEncodedListOfDeviceUids(encodedElements[2])
            commitment = try encodedElements[3].obvDecode()
            seedForSas = try encodedElements[4].obvDecode()
            dialogUuid = try encodedElements[5].obvDecode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, contactDeviceUids: [UID], commitment: Data, seedForSas: Seed, dialogUuid: UUID) {
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.contactDeviceUids = contactDeviceUids
            self.commitment = commitment
            self.seedForSas = seedForSas
            self.dialogUuid = dialogUuid
        }
        
        func obvEncode() -> ObvEncoded {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.jsonEncode()
            return [contactIdentity,
                    encodedContactIdentityCoreDetails,
                    contactDeviceUids as [ObvEncodable],
                    commitment,
                    seedForSas,
                    dialogUuid].obvEncode()
        }
    }
    
    
    struct WaitingForUserSASState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.WaitingForUserSAS
        
        let contactIdentity: ObvCryptoIdentity // The contact identity we seek to trust
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let contactDeviceUids: [UID]
        let seedForSas: Seed
        let contactSeedForSas: Seed
        let dialogUuid: UUID
        let numberOfBadEnteredSas: Int
        
        func obvEncode() -> ObvEncoded {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.jsonEncode()
            return [contactIdentity, encodedContactIdentityCoreDetails, contactDeviceUids as [ObvEncodable], seedForSas, contactSeedForSas, dialogUuid, numberOfBadEnteredSas].obvEncode()
        }

        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityCoreDetails: Data
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 7) else { throw NSError() }
            contactIdentity = try encodedElements[0].obvDecode()
            encodedContactIdentityCoreDetails = try encodedElements[1].obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            contactDeviceUids = try TrustEstablishmentProtocol.decodeEncodedListOfDeviceUids(encodedElements[2])
            seedForSas = try encodedElements[3].obvDecode()
            contactSeedForSas = try encodedElements[4].obvDecode()
            dialogUuid = try encodedElements[5].obvDecode()
            numberOfBadEnteredSas = try encodedElements[6].obvDecode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, contactDeviceUids: [UID], seedForSas: Seed, contactSeedForSas: Seed, dialogUuid: UUID, numberOfBadEnteredSas: Int) {
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.contactDeviceUids = contactDeviceUids
            self.seedForSas = seedForSas
            self.contactSeedForSas = contactSeedForSas
            self.dialogUuid = dialogUuid
            self.numberOfBadEnteredSas = numberOfBadEnteredSas
        }
        
    }
    
    
    struct ContactIdentityTrustedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.ContactIdentityTrusted
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let dialogUuid: UUID
        
        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityCoreDetails: Data
            (contactIdentity, encodedContactIdentityCoreDetails, dialogUuid) = try encoded.obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, dialogUuid: UUID) {
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.dialogUuid = dialogUuid
        }
        
        func obvEncode() -> ObvEncoded {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.jsonEncode()
            return [contactIdentity, encodedContactIdentityCoreDetails, dialogUuid].obvEncode()
        }
        
    }
    
    
    struct MutualTrustConfirmedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.MutualTrustConfirmed
        
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

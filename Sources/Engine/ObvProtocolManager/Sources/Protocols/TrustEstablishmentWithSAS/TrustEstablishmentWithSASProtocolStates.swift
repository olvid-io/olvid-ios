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
import CoreData
import os.log
import ObvCrypto
import ObvEncoder
import ObvTypes
import ObvOperation
import ObvMetaManager

// MARK: - Protocol States

extension TrustEstablishmentWithSASProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case initialState = 0
        // Alice's side
        case waitingForSeed = 1
        // Bob's side
        case waitingForConfirmation = 2
        case waitingForDecommitment = 6
        // On Alice's and Bob's sides
        case waitingForUserSAS = 7
        case contactIdentityTrustedLegacy = 8
        case contactSASChecked = 11
        case mutualTrustConfirmed = 9
        case cancelled = 10
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .initialState                  : return ConcreteProtocolInitialState.self
            case .waitingForSeed                : return WaitingForSeedState.self
            case .waitingForConfirmation        : return WaitingForConfirmationState.self
            case .waitingForDecommitment        : return WaitingForDecommitmentState.self
            case .waitingForUserSAS             : return WaitingForUserSASState.self
            case .contactIdentityTrustedLegacy  : return ContactIdentityTrustedLegacyState.self
            case .contactSASChecked             : return ContactSASCheckedState.self
            case .mutualTrustConfirmed          : return MutualTrustConfirmedState.self
            case .cancelled                     : return CancelledState.self
            }
        }
        
    }
    
    
    struct WaitingForSeedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.waitingForSeed
        
        let contactIdentity: ObvCryptoIdentity // The contact identity we seek to trust
        let decommitment: Data
        let seedAliceForSas: Seed
        let dialogUuid: UUID
        
        func obvEncode() -> ObvEncoded {
            return [contactIdentity, decommitment, seedAliceForSas, dialogUuid].obvEncode()
        }

        init(_ encoded: ObvEncoded) throws {
            (contactIdentity, decommitment, seedAliceForSas, dialogUuid) = try encoded.obvDecode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, decommitment: Data, seedAliceForSas: Seed, dialogUuid: UUID) {
            self.contactIdentity = contactIdentity
            self.decommitment = decommitment
            self.seedAliceForSas = seedAliceForSas
            self.dialogUuid = dialogUuid
        }
        
    }
    
    
    struct WaitingForConfirmationState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.waitingForConfirmation
        
        let contactIdentity: ObvCryptoIdentity // The contact identity we seek to trust
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let contactDeviceUids: [UID]
        let commitment: Data
        let dialogUuid: UUID
        
        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityCoreDetails: Data
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 5) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded elements") }
            contactIdentity = try encodedElements[0].obvDecode()
            encodedContactIdentityCoreDetails = try encodedElements[1].obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            contactDeviceUids = try TrustEstablishmentWithSASProtocol.decodeEncodedListOfDeviceUids(encodedElements[2])
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
        
        let id: ConcreteProtocolStateId = StateId.waitingForDecommitment
        
        let contactIdentity: ObvCryptoIdentity // The contact identity we seek to trust
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let contactDeviceUids: [UID]
        let commitment: Data
        let seedBobForSas: Seed
        let dialogUuid: UUID
        
        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityCoreDetails: Data
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 6) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded elements") }
            contactIdentity = try encodedElements[0].obvDecode()
            encodedContactIdentityCoreDetails = try encodedElements[1].obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            contactDeviceUids = try TrustEstablishmentWithSASProtocol.decodeEncodedListOfDeviceUids(encodedElements[2])
            commitment = try encodedElements[3].obvDecode()
            seedBobForSas = try encodedElements[4].obvDecode()
            dialogUuid = try encodedElements[5].obvDecode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, contactDeviceUids: [UID], commitment: Data, seedBobForSas: Seed, dialogUuid: UUID) {
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.contactDeviceUids = contactDeviceUids
            self.commitment = commitment
            self.seedBobForSas = seedBobForSas
            self.dialogUuid = dialogUuid
        }
        
        func obvEncode() -> ObvEncoded {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.jsonEncode()
            return [contactIdentity,
                    encodedContactIdentityCoreDetails,
                    contactDeviceUids as [ObvEncodable],
                    commitment,
                    seedBobForSas,
                    dialogUuid].obvEncode()
        }
    }
    
    
    struct WaitingForUserSASState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.waitingForUserSAS
        
        let contactIdentity: ObvCryptoIdentity // The contact identity we seek to trust
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let contactDeviceUids: [UID]
        let seedForSas: Seed
        let contactSeedForSas: Seed
        let dialogUuid: UUID
        let isAlice: Bool
        let numberOfBadEnteredSas: Int
        
        func obvEncode() -> ObvEncoded {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.jsonEncode()
            return [contactIdentity, encodedContactIdentityCoreDetails, contactDeviceUids as [ObvEncodable], seedForSas, contactSeedForSas, dialogUuid, isAlice, numberOfBadEnteredSas].obvEncode()
        }

        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityCoreDetails: Data
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 8) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded elements") }
            contactIdentity = try encodedElements[0].obvDecode()
            encodedContactIdentityCoreDetails = try encodedElements[1].obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            contactDeviceUids = try TrustEstablishmentWithSASProtocol.decodeEncodedListOfDeviceUids(encodedElements[2])
            seedForSas = try encodedElements[3].obvDecode()
            contactSeedForSas = try encodedElements[4].obvDecode()
            dialogUuid = try encodedElements[5].obvDecode()
            isAlice = try encodedElements[6].obvDecode()
            numberOfBadEnteredSas = try encodedElements[7].obvDecode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, contactDeviceUids: [UID], seedForSas: Seed, contactSeedForSas: Seed, dialogUuid: UUID, isAlice: Bool, numberOfBadEnteredSas: Int) {
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.contactDeviceUids = contactDeviceUids
            self.seedForSas = seedForSas
            self.contactSeedForSas = contactSeedForSas
            self.dialogUuid = dialogUuid
            self.isAlice = isAlice
            self.numberOfBadEnteredSas = numberOfBadEnteredSas
        }
        
    }
    
    
    struct ContactIdentityTrustedLegacyState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.contactIdentityTrustedLegacy
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let dialogUuid: UUID
        
        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityCoreDetails: Data
            (contactIdentity, encodedContactIdentityCoreDetails, dialogUuid) = try encoded.obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, dialogUuid: UUID) {
            assertionFailure("We should be using this state anymore, since it was replaced by ContactSASCheckedState")
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.dialogUuid = dialogUuid
        }
        
        func obvEncode() -> ObvEncoded {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.jsonEncode()
            return [contactIdentity, encodedContactIdentityCoreDetails, dialogUuid].obvEncode()
        }

    }

    
    struct ContactSASCheckedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.contactSASChecked
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let contactDeviceUids: [UID]
        let dialogUuid: UUID

        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityCoreDetails: Data
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 4) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded elements") }
            contactIdentity = try encodedElements[0].obvDecode()
            encodedContactIdentityCoreDetails = try encodedElements[1].obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            contactDeviceUids = try TrustEstablishmentWithSASProtocol.decodeEncodedListOfDeviceUids(encodedElements[2])
            dialogUuid = try encodedElements[3].obvDecode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, contactDeviceUids: [UID], dialogUuid: UUID) {
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.dialogUuid = dialogUuid
            self.contactDeviceUids = contactDeviceUids
        }
        
        func obvEncode() -> ObvEncoded {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.jsonEncode()
            return [contactIdentity, encodedContactIdentityCoreDetails, contactDeviceUids as [ObvEncodable], dialogUuid].obvEncode()
        }
        
    }

    
    struct MutualTrustConfirmedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.mutualTrustConfirmed
        
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

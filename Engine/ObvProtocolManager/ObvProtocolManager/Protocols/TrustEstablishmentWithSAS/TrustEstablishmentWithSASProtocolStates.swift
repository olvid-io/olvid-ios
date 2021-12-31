/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
        
        case InitialState = 0
        // Alice's side
        case WaitingForSeed = 1
        // Bob's side
        case WaitingForConfirmation = 2
        case WaitingForDecommitment = 6
        // On Alice's and Bob's sides
        case WaitingForUserSAS = 7
        case ContactIdentityTrustedLegacy = 8
        case ContactSASChecked = 11
        case MutualTrustConfirmed = 9
        case Cancelled = 10
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .InitialState                  : return ConcreteProtocolInitialState.self
            case .WaitingForSeed                : return WaitingForSeedState.self
            case .WaitingForConfirmation        : return WaitingForConfirmationState.self
            case .WaitingForDecommitment        : return WaitingForDecommitmentState.self
            case .WaitingForUserSAS             : return WaitingForUserSASState.self
            case .ContactIdentityTrustedLegacy  : return ContactIdentityTrustedLegacyState.self
            case .ContactSASChecked             : return ContactSASCheckedState.self
            case .MutualTrustConfirmed          : return MutualTrustConfirmedState.self
            case .Cancelled                     : return CancelledState.self
            }
        }
        
    }
    
    
    struct WaitingForSeedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.WaitingForSeed
        
        let contactIdentity: ObvCryptoIdentity // The contact identity we seek to trust
        let decommitment: Data
        let seedAliceForSas: Seed
        let dialogUuid: UUID
        
        func encode() -> ObvEncoded {
            return [contactIdentity, decommitment, seedAliceForSas, dialogUuid].encode()
        }

        init(_ encoded: ObvEncoded) throws {
            (contactIdentity, decommitment, seedAliceForSas, dialogUuid) = try encoded.decode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, decommitment: Data, seedAliceForSas: Seed, dialogUuid: UUID) {
            self.contactIdentity = contactIdentity
            self.decommitment = decommitment
            self.seedAliceForSas = seedAliceForSas
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
            contactIdentity = try encodedElements[0].decode()
            encodedContactIdentityCoreDetails = try encodedElements[1].decode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            contactDeviceUids = try TrustEstablishmentWithSASProtocol.decodeEncodedListOfDeviceUids(encodedElements[2])
            commitment = try encodedElements[3].decode()
            dialogUuid = try encodedElements[4].decode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, contactDeviceUids: [UID], commitment: Data, dialogUuid: UUID) {
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.contactDeviceUids = contactDeviceUids
            self.commitment = commitment
            self.dialogUuid = dialogUuid
        }
        
        func encode() -> ObvEncoded {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.encode()
            return [contactIdentity,
                    encodedContactIdentityCoreDetails,
                    contactDeviceUids as [ObvEncodable],
                    commitment,
                    dialogUuid].encode()
        }
    }
    
    
    
    struct WaitingForDecommitmentState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.WaitingForDecommitment
        
        let contactIdentity: ObvCryptoIdentity // The contact identity we seek to trust
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let contactDeviceUids: [UID]
        let commitment: Data
        let seedBobForSas: Seed
        let dialogUuid: UUID
        
        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityCoreDetails: Data
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 6) else { throw NSError() }
            contactIdentity = try encodedElements[0].decode()
            encodedContactIdentityCoreDetails = try encodedElements[1].decode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            contactDeviceUids = try TrustEstablishmentWithSASProtocol.decodeEncodedListOfDeviceUids(encodedElements[2])
            commitment = try encodedElements[3].decode()
            seedBobForSas = try encodedElements[4].decode()
            dialogUuid = try encodedElements[5].decode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, contactDeviceUids: [UID], commitment: Data, seedBobForSas: Seed, dialogUuid: UUID) {
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.contactDeviceUids = contactDeviceUids
            self.commitment = commitment
            self.seedBobForSas = seedBobForSas
            self.dialogUuid = dialogUuid
        }
        
        func encode() -> ObvEncoded {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.encode()
            return [contactIdentity,
                    encodedContactIdentityCoreDetails,
                    contactDeviceUids as [ObvEncodable],
                    commitment,
                    seedBobForSas,
                    dialogUuid].encode()
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
        let isAlice: Bool
        let numberOfBadEnteredSas: Int
        
        func encode() -> ObvEncoded {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.encode()
            return [contactIdentity, encodedContactIdentityCoreDetails, contactDeviceUids as [ObvEncodable], seedForSas, contactSeedForSas, dialogUuid, isAlice, numberOfBadEnteredSas].encode()
        }

        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityCoreDetails: Data
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 8) else { throw NSError() }
            contactIdentity = try encodedElements[0].decode()
            encodedContactIdentityCoreDetails = try encodedElements[1].decode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            contactDeviceUids = try TrustEstablishmentWithSASProtocol.decodeEncodedListOfDeviceUids(encodedElements[2])
            seedForSas = try encodedElements[3].decode()
            contactSeedForSas = try encodedElements[4].decode()
            dialogUuid = try encodedElements[5].decode()
            isAlice = try encodedElements[6].decode()
            numberOfBadEnteredSas = try encodedElements[7].decode()
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
        
        let id: ConcreteProtocolStateId = StateId.ContactIdentityTrustedLegacy
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let dialogUuid: UUID
        
        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityCoreDetails: Data
            (contactIdentity, encodedContactIdentityCoreDetails, dialogUuid) = try encoded.decode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, dialogUuid: UUID) {
            assertionFailure("We should be using this state anymore, since it was replaced by ContactSASCheckedState")
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.dialogUuid = dialogUuid
        }
        
        func encode() -> ObvEncoded {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.encode()
            return [contactIdentity, encodedContactIdentityCoreDetails, dialogUuid].encode()
        }

    }

    
    struct ContactSASCheckedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.ContactSASChecked
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let contactDeviceUids: [UID]
        let dialogUuid: UUID

        init(_ encoded: ObvEncoded) throws {
            let encodedContactIdentityCoreDetails: Data
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 4) else { throw NSError() }
            contactIdentity = try encodedElements[0].decode()
            encodedContactIdentityCoreDetails = try encodedElements[1].decode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            contactDeviceUids = try TrustEstablishmentWithSASProtocol.decodeEncodedListOfDeviceUids(encodedElements[2])
            dialogUuid = try encodedElements[3].decode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, contactDeviceUids: [UID], dialogUuid: UUID) {
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.dialogUuid = dialogUuid
            self.contactDeviceUids = contactDeviceUids
        }
        
        func encode() -> ObvEncoded {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.encode()
            return [contactIdentity, encodedContactIdentityCoreDetails, contactDeviceUids as [ObvEncodable], dialogUuid].encode()
        }
        
    }

    
    struct MutualTrustConfirmedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.MutualTrustConfirmed
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func encode() -> ObvEncoded { return 0.encode() }
        
    }
    
    
    struct CancelledState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.Cancelled
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func encode() -> ObvEncoded { return 0.encode() }
    }
    
}

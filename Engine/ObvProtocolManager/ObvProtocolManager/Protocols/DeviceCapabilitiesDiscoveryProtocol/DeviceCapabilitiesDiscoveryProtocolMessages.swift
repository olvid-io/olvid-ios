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
import ObvTypes
import ObvEncoder
import ObvCrypto

extension DeviceCapabilitiesDiscoveryProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {

        case InitialForAddingOwnCapabilities = 0
        case InitialSingleContactDevice = 1
        case InitialSingleOwnedDevice = 2
        case OwnCapabilitiesToContact = 3
        case OwnCapabilitiesToSelf = 4

        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .InitialForAddingOwnCapabilities : return InitialForAddingOwnCapabilitiesMessage.self
            case .InitialSingleContactDevice      : return InitialSingleContactDeviceMessage.self
            case .InitialSingleOwnedDevice        : return InitialSingleOwnedDeviceMessage.self
            case .OwnCapabilitiesToContact        : return OwnCapabilitiesToContactMessage.self
            case .OwnCapabilitiesToSelf           : return OwnCapabilitiesToSelfMessage.self
            }
        }

    }

 
    // MARK: - InitialForAddingOwnCapabilitiesMessage

    struct InitialForAddingOwnCapabilitiesMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.InitialForAddingOwnCapabilities
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message
        
        let newOwnCapabilities: Set<ObvCapability>
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, newOwnCapabilities: Set<ObvCapability>) {
            self.coreProtocolMessage = coreProtocolMessage
            self.newOwnCapabilities = newOwnCapabilities
        }

        var encodedInputs: [ObvEncoded] {
            let encodedOwnCapabilities = newOwnCapabilities.map({ $0.rawValue.encode() })
            return [encodedOwnCapabilities.encode()]
        }

        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else {
                assertionFailure()
                throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Unexpected number of encoded inputs")
            }
            let rawCapabilities = try DeviceCapabilitiesDiscoveryProtocol.decodeRawContactObvCapabilities(message.encodedInputs[0])
            let ownCapabilities = rawCapabilities.compactMap({ ObvCapability(rawValue: $0) })
            guard ownCapabilities.count == rawCapabilities.count else {
                throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Could not parse raw capabilities")
            }
            self.newOwnCapabilities = Set(ownCapabilities)
        }
        
    }

    
    // MARK: - InitialSingleContactDeviceMessage

    struct InitialSingleContactDeviceMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.InitialSingleContactDevice
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        let isResponse: Bool

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, isResponse: Bool) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
            self.contactDeviceUid = contactDeviceUid
            self.isResponse = isResponse
        }

        var encodedInputs: [ObvEncoded] {
            [contactIdentity.encode(), contactDeviceUid.encode(), isResponse.encode()]
        }

        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 3 else {
                assertionFailure()
                throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Unexpected number of encoded inputs")
            }
            self.contactIdentity = try message.encodedInputs[0].decode()
            self.contactDeviceUid = try message.encodedInputs[1].decode()
            self.isResponse = try message.encodedInputs[2].decode()
        }

    }

    
    // MARK: - InitialSingleOwnedDeviceMessage

    struct InitialSingleOwnedDeviceMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.InitialSingleOwnedDevice
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let otherOwnedDeviceUid: UID
        let isResponse: Bool

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, otherOwnedDeviceUid: UID, isResponse: Bool) {
            self.coreProtocolMessage = coreProtocolMessage
            self.otherOwnedDeviceUid = otherOwnedDeviceUid
            self.isResponse = isResponse
        }

        var encodedInputs: [ObvEncoded] {
            [otherOwnedDeviceUid.encode(), isResponse.encode()]
        }

        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else {
                assertionFailure()
                throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Unexpected number of encoded inputs")
            }
            self.otherOwnedDeviceUid = try message.encodedInputs[0].decode()
            self.isResponse = try message.encodedInputs[1].decode()
        }

    }

    
    // MARK: - OwnCapabilitiesToContactMessage

    struct OwnCapabilitiesToContactMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.OwnCapabilitiesToContact
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let rawContactObvCapabilities: Set<String>
        let isReponse: Bool

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, ownCapabilities: Set<ObvCapability>, isReponse: Bool) {
            self.coreProtocolMessage = coreProtocolMessage
            self.rawContactObvCapabilities = Set(ownCapabilities.map({ $0.rawValue }))
            self.isReponse = isReponse
        }

        var encodedInputs: [ObvEncoded] {
            let encodedRawCapabilities = rawContactObvCapabilities.map({ $0.encode() })
            return [encodedRawCapabilities.encode(), isReponse.encode()]
        }

        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else {
                assertionFailure()
                throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Unexpected number of encoded inputs")
            }
            self.rawContactObvCapabilities = try DeviceCapabilitiesDiscoveryProtocol.decodeRawContactObvCapabilities(message.encodedInputs[0])
            self.isReponse = try message.encodedInputs[1].decode()
        }

    }

    
    // MARK: - OwnCapabilitiesToSelfMessage

    struct OwnCapabilitiesToSelfMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.OwnCapabilitiesToContact
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let rawOtherOwnDeviceObvCapabilities: Set<String>
        let isReponse: Bool

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, ownCapabilities: Set<ObvCapability>, isReponse: Bool) {
            self.coreProtocolMessage = coreProtocolMessage
            self.rawOtherOwnDeviceObvCapabilities = Set(ownCapabilities.map({ $0.rawValue }))
            self.isReponse = isReponse
        }

        var encodedInputs: [ObvEncoded] {
            let encodedRawCapabilities = rawOtherOwnDeviceObvCapabilities.map({ $0.encode() })
            return [encodedRawCapabilities.encode(), isReponse.encode()]
        }

        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else {
                assertionFailure()
                throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Unexpected number of encoded inputs")
            }
            self.rawOtherOwnDeviceObvCapabilities = try DeviceCapabilitiesDiscoveryProtocol.decodeRawContactObvCapabilities(message.encodedInputs[0])
            self.isReponse = try message.encodedInputs[1].decode()
        }

    }

    
    // MARK: - Helpers for messages
    
    fileprivate static func decodeRawContactObvCapabilities(_ encoded: ObvEncoded) throws -> Set<String> {
        guard let encodedRawCapabilities = [ObvEncoded](encoded) else {
            throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Failed to decode to encoded raw capabilities")
        }
        let rawCapabilities = encodedRawCapabilities.compactMap({ String($0) })
        guard rawCapabilities.count == encodedRawCapabilities.count else {
            throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Failed to decode to raw capabilities")
        }
        return Set(rawCapabilities)
    }
    
}

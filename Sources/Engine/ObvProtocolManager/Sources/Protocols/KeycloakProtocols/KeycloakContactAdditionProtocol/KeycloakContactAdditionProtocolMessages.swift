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

extension KeycloakContactAdditionProtocol {

    enum MessageId: Int, ConcreteProtocolMessageId {
        case initial = 0
        case deviceDiscoveryDone = 1
        case propagateContactAdditionToOtherDevices = 2
        case inviteKeycloakContact = 3
        case checkForRevocationServerQuery = 4
        case confirmation = 5

        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initial                               : return InitialMessage.self
            case .deviceDiscoveryDone                   : return DeviceDiscoveryDoneMessage.self
            case .propagateContactAdditionToOtherDevices: return PropagateContactAdditionToOtherDevicesMessage.self
            case .inviteKeycloakContact                 : return InviteKeycloakContactMessage.self
            case .checkForRevocationServerQuery         : return CheckForRevocationServerQueryMessage.self
            case .confirmation                          : return ConfirmationMessage.self
            }
        }

    }

    // MARK: - InitialMessage

    struct InitialMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.initial
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let contactIdentity: ObvCryptoIdentity
        let signedContactDetails: String

        var encodedInputs: [ObvEncoded] {
            return [contactIdentity.obvEncode(), signedContactDetails.obvEncode()]
        }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.contactIdentity = try message.encodedInputs[0].obvDecode()
            self.signedContactDetails = try message.encodedInputs[1].obvDecode()
        }

        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity, signedContactDetails: String) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
            self.signedContactDetails = signedContactDetails
        }


    }

    // MARK: - DeviceDiscoveryDoneMessage

    struct DeviceDiscoveryDoneMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.deviceDiscoveryDone
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let childToParentProtocolMessageInputs: ChildToParentProtocolMessageInputs
        let deviceUidsSentState: DeviceDiscoveryForRemoteIdentityProtocol.DeviceUidsReceivedState

        var encodedInputs: [ObvEncoded] {
            return childToParentProtocolMessageInputs.toListOfEncoded()
        }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard let inputs = ChildToParentProtocolMessageInputs(message.encodedInputs) else { assertionFailure(); throw Self.makeError(message: "Could not obtain child inputs") }
            childToParentProtocolMessageInputs = inputs
            deviceUidsSentState = try DeviceDiscoveryForRemoteIdentityProtocol.DeviceUidsReceivedState(childToParentProtocolMessageInputs.childProtocolInstanceEncodedReachedState)
        }

    }

    // MARK: - PropagateContactAdditionToOtherDevicesMessage

    struct PropagateContactAdditionToOtherDevicesMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.propagateContactAdditionToOtherDevices
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let contactIdentity: ObvCryptoIdentity
        let keycloakServerURL: URL
        let identityCoreDetails: ObvIdentityCoreDetails
        let contactDeviceUids: [UID]
        let trustTimestamp: Date

        var encodedInputs: [ObvEncoded] {
            let encodedIdentityCoreDetails = try! identityCoreDetails.jsonEncode()
            let listOfEncodedUids = contactDeviceUids.map { $0.obvEncode() }
            return [contactIdentity.obvEncode(), keycloakServerURL.obvEncode(), encodedIdentityCoreDetails.obvEncode(), listOfEncodedUids.obvEncode(), trustTimestamp.obvEncode()]
        }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 5 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            self.contactIdentity = try encodedElements[0].obvDecode()
            self.keycloakServerURL = try encodedElements[1].obvDecode()
            let encodedIdentityCoreDetails: Data = try encodedElements[2].obvDecode()
            self.identityCoreDetails = try ObvIdentityCoreDetails(encodedIdentityCoreDetails)
            guard let listOfEncodedDeviceUids = [ObvEncoded](encodedElements[3]) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded device uids") }
            contactDeviceUids = try listOfEncodedDeviceUids.map { return try $0.obvDecode() }
            self.trustTimestamp = try encodedElements[4].obvDecode()
        }

        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity, keycloakServerURL: URL, identityCoreDetails: ObvIdentityCoreDetails, contactDeviceUids: [UID], trustTimestamp: Date) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
            self.keycloakServerURL = keycloakServerURL
            self.identityCoreDetails = identityCoreDetails
            self.contactDeviceUids = contactDeviceUids
            self.trustTimestamp = trustTimestamp
        }

    }

    // MARK: - InviteKeycloakContactMessage

    struct InviteKeycloakContactMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.inviteKeycloakContact
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let contactIdentity: ObvCryptoIdentity
        let signedContactDetails: String // This is a JWT
        let contactDeviceUids: [UID]
        let keycloakServerURL: URL

        var encodedInputs: [ObvEncoded] {
            let listOfEncodedUids = contactDeviceUids.map { $0.obvEncode() }
            return [contactIdentity.obvEncode(), signedContactDetails.obvEncode(), listOfEncodedUids.obvEncode(), keycloakServerURL.obvEncode()]
        }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 4 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            self.contactIdentity = try encodedElements[0].obvDecode()
            self.signedContactDetails = try encodedElements[1].obvDecode()
            guard let listOfEncodedDeviceUids = [ObvEncoded](encodedElements[2]) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded device uids") }
            self.contactDeviceUids = try listOfEncodedDeviceUids.map { return try $0.obvDecode() }
            self.keycloakServerURL = try encodedElements[3].obvDecode()
        }

        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity, signedContactDetails: String, contactDeviceUids: [UID], keycloakServerURL: URL) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
            self.signedContactDetails = signedContactDetails
            self.contactDeviceUids = contactDeviceUids
            self.keycloakServerURL = keycloakServerURL
        }

    }

    // MARK: - CheckForRevocationServerQueryMessage

    struct CheckForRevocationServerQueryMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.checkForRevocationServerQuery
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let userNotRevoked: Bool

        var encodedInputs: [ObvEncoded] { [] }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            self.userNotRevoked = try encodedElements[0].obvDecode()
        }

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.userNotRevoked = false
        }

    }
    // MARK: - ConfirmationMessage

    struct ConfirmationMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.confirmation
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let accepted: Bool

        var encodedInputs: [ObvEncoded] { [accepted.obvEncode()] }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            self.accepted = try encodedElements[0].obvDecode()
        }

        init(coreProtocolMessage: CoreProtocolMessage, accepted: Bool) {
            self.coreProtocolMessage = coreProtocolMessage
            self.accepted = accepted
        }



    }


}

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
import ObvMetaManager
import JWS
import OlvidUtils


// MARK: - Protocol Steps

extension KeycloakContactAdditionProtocol {

    enum StepId: Int, ConcreteProtocolStepId {
        case VerifyContactAndStartDeviceDiscovery = 0
        case AddContactAndSendRequest = 1
        case ProcessPropagatedContactAddition = 2
        case ProcessReceivedKeycloakInvite = 3
        case AddContactAndSendConfirmation = 4
        case ProcessConfirmation = 5

        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
            case .VerifyContactAndStartDeviceDiscovery:
                let step = VerifyContactAndStartDeviceDiscoveryStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .AddContactAndSendRequest:
                let step = AddContactAndSendRequestStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ProcessPropagatedContactAddition:
                let step = ProcessPropagatedContactAdditionStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ProcessReceivedKeycloakInvite:
                let step = ProcessReceivedKeycloakInviteStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .AddContactAndSendConfirmation:
                let step = AddContactAndSendConfirmationStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ProcessConfirmation:
                let step = ProcessConfirmationStep(from: concreteProtocol, and: receivedMessage)
                return step
            }
        }


    }

    final class VerifyContactAndStartDeviceDiscoveryStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: InitialMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: KeycloakContactAdditionProtocol.logCategory)

            let contactIdentity = receivedMessage.contactIdentity
            let signedContactDetails = receivedMessage.signedContactDetails

            // First verify the contact signature
            let keycloakState: ObvKeycloakState
            let signedOwnedDetails: SignedUserDetails
            do {
                let (_keycloakState, _signedOwnedDetails) = try identityDelegate.getOwnedIdentityKeycloakState(ownedIdentity: ownedIdentity, within: obvContext)
                guard let _keycloakState = _keycloakState else {
                    os_log("Could not find Keycloak State of owned identity", log: log, type: .fault)
                    return FinishedState()
                }
                guard let _signedOwnedDetails = _signedOwnedDetails else {
                    os_log("KeycloakContactAdditionProtocol: Could not find owned signed details", log: log, type: .fault)
                    return FinishedState()
                }
                keycloakState = _keycloakState
                signedOwnedDetails = _signedOwnedDetails
            }
            let jwks = keycloakState.jwks
            let keycloakServerUrl = keycloakState.keycloakServer

            let signedContactUserDetails: SignedUserDetails
            do {
                signedContactUserDetails = try SignedUserDetails.verifySignedUserDetails(signedContactDetails, with: jwks).signedUserDetails
            } catch {
                os_log("Could not create SignedUserDetails: %{public}@", log: log, type: .error, error.localizedDescription)
                return FinishedState()
            }
            
            guard let userCoreDetails = try? signedContactUserDetails.getObvIdentityCoreDetails() else {
                return FinishedState()
            }

            // Signatures are valid --> launch a deviceDiscovery before adding the contact

            let childProtocolInstanceUid = UID.gen(with: prng)
            os_log("Creating a link between the parent with uid %@ and the child protocol with uid %@, with owned identity %@", log: log, type: .debug, protocolInstanceUid.debugDescription, childProtocolInstanceUid.debugDescription, ownedIdentity.debugDescription)

            guard let thisProtocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId, uid: protocolInstanceUid, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
                os_log("Could not retrive this protocol instance", log: log, type: .fault)
                return FinishedState()
            }
            guard let _ = LinkBetweenProtocolInstances(parentProtocolInstance: thisProtocolInstance,
                                                       childProtocolInstanceUid: childProtocolInstanceUid,
                                                       expectedChildStateRawId: DeviceDiscoveryForRemoteIdentityProtocol.StateId.DeviceUidsReceived.rawValue,
                                                       messageToSendRawId: DeviceDiscoveryForContactIdentityProtocol.MessageId.ChildProtocolReachedExpectedState.rawValue)
            else {
                os_log("Could not create a link between protocol instances", log: log, type: .fault)
                return FinishedState()
            }

            // To actually create the child protocol instance, we post an appropriate message on the loopback channel

            let coreMessage = getCoreMessageForOtherLocalProtocol(
                otherCryptoProtocolId: .DeviceDiscoveryForRemoteIdentity,
                otherProtocolInstanceUid: childProtocolInstanceUid)
            let childProtocolInitialMessage = DeviceDiscoveryForRemoteIdentityProtocol.InitialMessage(
                coreProtocolMessage: coreMessage,
                remoteIdentity: contactIdentity)
            guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                assertionFailure()
                throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
            }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)


            return WaitingForDeviceDiscoveryState(contactIdentity: contactIdentity, identityCoreDetails: userCoreDetails, keycloakServerURL: keycloakServerUrl, signedOwnedDetails: signedOwnedDetails.signedUserDetails)
        }

    }

    final class AddContactAndSendRequestStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: WaitingForDeviceDiscoveryState
        let receivedMessage: DeviceDiscoveryDoneMessage

        init?(startState: WaitingForDeviceDiscoveryState, receivedMessage: DeviceDiscoveryDoneMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let contactIdentity = startState.contactIdentity
            let identityCoreDetails = startState.identityCoreDetails
            let keycloakServerURL = startState.keycloakServerURL
            let signedOwnedDetails = startState.signedOwnedDetails

            let deviceUidsSentState = receivedMessage.deviceUidsSentState

            let contactDeviceUids = Set(deviceUidsSentState.deviceUids)
            guard !contactDeviceUids.isEmpty else {
                return FinishedState()
            }

            // Actually create the contact
            
            let contactCreated: Bool
            let trustTimestamp = Date()
            let trustOrigin: TrustOrigin = .keycloak(timestamp: trustTimestamp, keycloakServer: keycloakServerURL)
            if (try? !identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true {
                contactCreated = true
                try identityDelegate.addContactIdentity(contactIdentity, with: identityCoreDetails, andTrustOrigin: trustOrigin, forOwnedIdentity: ownedIdentity, setIsOneToOneTo: true, within: obvContext)

                for contactDeviceUid in contactDeviceUids {
                    try identityDelegate.addDeviceForContactIdentity(contactIdentity, withUid: contactDeviceUid, ofOwnedIdentity: ownedIdentity, within: obvContext)
                }
            } else {
                contactCreated = false
                try identityDelegate.addTrustOrigin(trustOrigin, toContactIdentity: contactIdentity, ofOwnedIdentity: ownedIdentity, setIsOneToOneTo: true, within: obvContext)
                // No need to add devices, they should be in sync already
            }

            // Propagate the message to other known devices

            let numberOfOtherDevicesOfOwnedIdentity = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count
            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                let concreteProtocolMessage = PropagateContactAdditionToOtherDevicesMessage(coreProtocolMessage: coreMessage, contactIdentity: contactIdentity, keycloakServerURL: keycloakServerURL, identityCoreDetails: identityCoreDetails, contactDeviceUids: deviceUidsSentState.deviceUids, trustTimestamp: trustTimestamp)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    assertionFailure()
                    throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Send an "invitation" to all contact devices
            let ownedDeviceUids = try identityDelegate.getDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
            let coreMessage = self.getCoreMessage(for: .AsymmetricChannel(to: contactIdentity, remoteDeviceUids: Array(contactDeviceUids), fromOwnedIdentity: ownedIdentity))
            let concreteMessage = InviteKeycloakContactMessage(coreProtocolMessage: coreMessage, contactIdentity: ownedIdentity, signedContactDetails: signedOwnedDetails, contactDeviceUids: Array(ownedDeviceUids), keycloakServerURL: keycloakServerURL)
            guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

            if contactCreated {
                return WaitingForConfirmationState(contactIdentity: contactIdentity, keycloakServerUrl: keycloakServerURL)
            } else {
                return FinishedState()
            }
        }

    }

    final class ProcessPropagatedContactAdditionStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: ConcreteProtocolInitialState
        let receivedMessage: PropagateContactAdditionToOtherDevicesMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: PropagateContactAdditionToOtherDevicesMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let contactIdentity = receivedMessage.contactIdentity
            let keycloakServerURL = receivedMessage.keycloakServerURL
            let identityCoreDetails = receivedMessage.identityCoreDetails
            let contactDeviceUids = receivedMessage.contactDeviceUids
            let trustTimestamp = receivedMessage.trustTimestamp

            let trustOrigin: TrustOrigin = .keycloak(timestamp: trustTimestamp, keycloakServer: keycloakServerURL)
            if (try? !identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true {
                try identityDelegate.addContactIdentity(contactIdentity, with: identityCoreDetails, andTrustOrigin: trustOrigin, forOwnedIdentity: ownedIdentity, setIsOneToOneTo: true, within: obvContext)

                for contactDeviceUid in contactDeviceUids {
                    try identityDelegate.addDeviceForContactIdentity(contactIdentity, withUid: contactDeviceUid, ofOwnedIdentity: ownedIdentity, within: obvContext)
                }
            } else {
                try identityDelegate.addTrustOrigin(trustOrigin, toContactIdentity: contactIdentity, ofOwnedIdentity: ownedIdentity, setIsOneToOneTo: true, within: obvContext)
                // No need to add devices, they should be in sync already
            }

            return FinishedState()
        }

    }

    final class ProcessReceivedKeycloakInviteStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: ConcreteProtocolInitialState
        let receivedMessage: InviteKeycloakContactMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: InviteKeycloakContactMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AsymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let contactIdentity = receivedMessage.contactIdentity
            let signedContactDetails = receivedMessage.signedContactDetails
            let contactDeviceUids = receivedMessage.contactDeviceUids
            let keycloakServerURL = receivedMessage.keycloakServerURL

            // Verify the received contact signature
            // To the contrary of the Android version, the iOS version assumes that we only trust our own keycloak server.
            
            guard let jwks = try identityDelegate.getOwnedIdentityKeycloakState(ownedIdentity: ownedIdentity, within: obvContext).obvKeycloakState?.jwks,
                  let signedContactUserDetails = try? SignedUserDetails.verifySignedUserDetails(signedContactDetails, with: jwks).signedUserDetails,
                  let userCoreDetails = try? signedContactUserDetails.getObvIdentityCoreDetails()
            else {
                let coreMessage = self.getCoreMessage(for: .AsymmetricChannel(to: contactIdentity, remoteDeviceUids: contactDeviceUids, fromOwnedIdentity: self.ownedIdentity))
                let concreteProtocolMessage = ConfirmationMessage(coreProtocolMessage: coreMessage, accepted: false)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: self.prng) else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: self.prng, within: obvContext)

                return FinishedState()
            }

            let coreMessage = self.getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
            let concreteProtocolMessage = CheckForRevocationServerQueryMessage(coreProtocolMessage: coreMessage)
            guard let messageToSend = concreteProtocolMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: .checkKeycloakRevocation(keycloakServerUrl: keycloakServerURL, signedContactDetails: signedContactDetails)) else { throw NSError() }
            _ = try channelDelegate.post(messageToSend, randomizedWith: self.prng, within: obvContext)

            return CheckingForRevocationState(contactIdentity: contactIdentity, identityCoreDetails: userCoreDetails, contactDeviceUids: contactDeviceUids, keycloakServerURL: keycloakServerURL)
        }

    }

    final class AddContactAndSendConfirmationStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: CheckingForRevocationState
        let receivedMessage: CheckForRevocationServerQueryMessage

        init?(startState: CheckingForRevocationState, receivedMessage: CheckForRevocationServerQueryMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let contactIdentity = startState.contactIdentity
            let identityCoreDetails = startState.identityCoreDetails
            let contactDeviceUids = startState.contactDeviceUids
            let keycloakServerURL = startState.keycloakServerURL
            let userNotRevoked = receivedMessage.userNotRevoked

            guard userNotRevoked else {
                // User is revoked
                let coreMessage = self.getCoreMessage(for: .AsymmetricChannel(to: contactIdentity, remoteDeviceUids: contactDeviceUids, fromOwnedIdentity: self.ownedIdentity))
                let concreteProtocolMessage = ConfirmationMessage(coreProtocolMessage: coreMessage, accepted: false)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: self.prng) else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: self.prng, within: obvContext)

                return FinishedState()
            }

            // Add the contact and devices

            let trustTimestamp = Date()
            let trustOrigin: TrustOrigin = .keycloak(timestamp: trustTimestamp, keycloakServer: keycloakServerURL)
            if (try? !identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true {
                try identityDelegate.addContactIdentity(contactIdentity, with: identityCoreDetails, andTrustOrigin: trustOrigin, forOwnedIdentity: ownedIdentity, setIsOneToOneTo: true, within: obvContext)

                for contactDeviceUid in contactDeviceUids {
                    try identityDelegate.addDeviceForContactIdentity(contactIdentity, withUid: contactDeviceUid, ofOwnedIdentity: ownedIdentity, within: obvContext)
                }
            } else {
                try identityDelegate.addTrustOrigin(trustOrigin, toContactIdentity: contactIdentity, ofOwnedIdentity: ownedIdentity, setIsOneToOneTo: true, within: obvContext)
                // No need to add devices, they should be in sync already
            }

            let coreMessage = self.getCoreMessage(for: .AsymmetricChannel(to: contactIdentity, remoteDeviceUids: contactDeviceUids, fromOwnedIdentity: self.ownedIdentity))
            let concreteProtocolMessage = ConfirmationMessage(coreProtocolMessage: coreMessage, accepted: true)
            guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: self.prng) else { throw NSError() }
            _ = try channelDelegate.post(messageToSend, randomizedWith: self.prng, within: obvContext)

            return FinishedState()
        }

    }

    final class ProcessConfirmationStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: WaitingForConfirmationState
        let receivedMessage: ConfirmationMessage

        init?(startState: WaitingForConfirmationState, receivedMessage: ConfirmationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AsymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let contactIdentity = startState.contactIdentity
            let keycloakServerURL = startState.keycloakServerURL
            let accepted = receivedMessage.accepted

            // If rejected --> delete the contact
            if !accepted {
                let trustOrigins = try identityDelegate.getTrustOrigins(forContactIdentity: contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
                for trustOrigin in trustOrigins {
                    switch trustOrigin {
                    case .direct, .group, .introduction, .serverGroupV2:
                        // Found another kind of trust origin -> We keep the contact
                        return FinishedState()
                    case .keycloak(_, keycloakServer: let keycloakServer):
                        // Found another keycloak origin with different server -> We keep the contact
                        if keycloakServer != keycloakServerURL {
                            return FinishedState()
                        }
                    }
                }
                // The contact is only trusted through the keycloakServer which he just rejected --> delete the contact
                try identityDelegate.deleteContactIdentity(contactIdentity, forOwnedIdentity: ownedIdentity, failIfContactIsPartOfACommonGroup: false, within: obvContext)

            }
            // Else if accepted --> everything is fine, do nothing

            return FinishedState()
        }

    }

}

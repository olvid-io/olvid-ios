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
import OlvidUtils



// MARK: - Protocol Steps

extension ContactDeviceDiscoveryProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {

        case startChildProtocol = 0
        case processChildProtocolState = 1

        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
            case .startChildProtocol        : return StartChildProtocolStep(from: concreteProtocol, and: receivedMessage)
            case .processChildProtocolState : return ProcessChildProtocolStateStep(from: concreteProtocol, and: receivedMessage)
            }
        }
    }

    final class StartChildProtocolStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialMessage

        init?(startState: StartConcreteProtocolStateType, receivedMessage: ConcreteProtocolMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactDeviceDiscoveryProtocol.logCategory)

            let contactIdentity = receivedMessage.contactIdentity
            
            // We check that the identity is indeed a contact identity
            
            guard (try? identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true else {
                os_log("The identity %@ is not a contact identity of the owned identity %@", log: log, type: .fault, contactIdentity.debugDescription, ownedIdentity.debugDescription)
                return CancelledState()
            }
            
            guard try identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext) else {
                os_log("The identity %@ is not an active contact identity of the owned identity %@", log: log, type: .fault, contactIdentity.debugDescription, ownedIdentity.debugDescription)
                return CancelledState()
            }
            
            // We execute a child protocol : a DeviceDiscoveryForRemoteIdentityProtocol. So we create a link between this protocol instance and the future child protocol instance
            
            let childProtocolInstanceUid = UID.gen(with: prng)
            os_log("Creating a link between the parent with uid %@ and the child protocol with uid %@, with owned identity %@", log: log, type: .debug, protocolInstanceUid.debugDescription, childProtocolInstanceUid.debugDescription, ownedIdentity.debugDescription)
            
            guard let thisProtocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId, uid: protocolInstanceUid, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
                os_log("Could not retrive this protocol instance", log: log, type: .fault)
                return CancelledState()
            }
            guard let _ = LinkBetweenProtocolInstances(parentProtocolInstance: thisProtocolInstance,
                                                       childProtocolInstanceUid: childProtocolInstanceUid,
                                                       expectedChildStateRawId: DeviceDiscoveryForRemoteIdentityProtocol.StateId.deviceUidsReceived.rawValue,
                                                       messageToSendRawId: MessageId.childProtocolReachedExpectedState.rawValue)
                else {
                    os_log("Could not create a link between protocol instances", log: log, type: .fault)
                    return CancelledState()
            }

            // To actually create the child protocol instance, we post an appropriate message on the loopback channel
            
            let coreMessage = getCoreMessageForOtherLocalProtocol(otherCryptoProtocolId: .deviceDiscoveryForRemoteIdentity,
                                                                  otherProtocolInstanceUid: childProtocolInstanceUid)
            let childProtocolInitialMessage = DeviceDiscoveryForRemoteIdentityProtocol.InitialMessage(coreProtocolMessage: coreMessage,
                                                                                                      remoteIdentity: contactIdentity)
            guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                assertionFailure()
                throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
            }
            _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)

            // Return the new state

            return WaitingForChildProtocolState(contactIdentity: contactIdentity)
        }
    }


    final class ProcessChildProtocolStateStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: WaitingForChildProtocolState
        let receivedMessage: ChildProtocolReachedExpectedStateMessage

        init?(startState: WaitingForChildProtocolState, receivedMessage: ChildProtocolReachedExpectedStateMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactDeviceDiscoveryProtocol.logCategory)

            let contactIdentity: ObvCryptoIdentity
            do {
                let expectedContactIdentity = startState.contactIdentity
                let receivedContactIdentity = receivedMessage.deviceUidsSentState.remoteIdentity
                
                guard expectedContactIdentity == receivedContactIdentity else {
                    os_log("We received the device uids of an unexpected identity", log: log, type: .fault)
                    return CancelledState()
                }
                contactIdentity = expectedContactIdentity
            }

            let contactDeviceDiscoveryResult = receivedMessage.deviceUidsSentState.result

            try identityDelegate.processContactDeviceDiscoveryResult(contactDeviceDiscoveryResult, forContactCryptoId: contactIdentity, ofOwnedCryptoId: ownedIdentity, within: obvContext)
                        
            // Return the new state
            
            return ChildProtocolStateProcessedState()
            
        }
    }
}

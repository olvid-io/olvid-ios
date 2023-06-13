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
import os.log
import CoreData
import ObvMetaManager
import ObvOperation
import ObvTypes
import ObvCrypto
import OlvidUtils

/// This operation is queued by the `ProtocolStepMetaOperationsCoordinator`. Its purpose is to find a match between the protocol instance inputs and an existing protocol instance. If a match is found, it determines the correct step to execute. This step, itself, is an operation that we queue here on an internal queue.
/// Note that this operation receives a context. This context is used within the protocol step operation (if one is executed). This context is only commited by the coordinator.
final class ProtocolOperation: ObvOperation, ObvErrorMaker {
    
    private static let logCategory = "ProtocolOperation"
    let log: OSLog
    
    override var className: String {
        return "ProtocolOperation"
    }
    
    static let errorDomain = "ProtocolOperation"
    
    // MARK: Instance variables and constants
    
    let receivedMessageId: MessageIdentifier
    weak var delegateManager: ObvProtocolDelegateManager? = nil
    private(set) var reasonForCancel: PossibleReasonForCancel? = nil
    let prng: PRNGService

    let flowId: FlowIdentifier
    
    // If this operation finishes without cancelling, this is set
    var protocolInstanceUid: UID?
    var protocolInstanceOwnedIdentity: ObvCryptoIdentity?

    enum PossibleReasonForCancel {
        case contextCreatorDelegateNotSet
        case messageNotFoundInDatabase
        case couldNotReconstructConcreteCryptoProtocol
        case couldNotConstructConcreteProtocolMessageForTheGivenCryptoProtocol
        case couldNotFindConcreteStepToExecute
        case couldNotFindConcreteStepToExecuteForReceivedDialogResponse(uuid: UUID)
        case theProtocolStepCancelled
        case couldNotDetermineNewProtocolState
        case couldNotUpdateProtocolState
        case couldNotSaveContext
        case couldNotDetermineTheAssociatedOwnedIdentity
        case couldNotDeleteReceivedMessage
        
        var description: String {
            switch self {
            case .contextCreatorDelegateNotSet: return "contextCreatorDelegateNotSet"
            case .messageNotFoundInDatabase: return "messageNotFoundInDatabase"
            case .couldNotReconstructConcreteCryptoProtocol: return "couldNotReconstructConcreteCryptoProtocol"
            case .couldNotConstructConcreteProtocolMessageForTheGivenCryptoProtocol: return "couldNotConstructConcreteProtocolMessageForTheGivenCryptoProtocol"
            case .couldNotFindConcreteStepToExecute: return "couldNotFindConcreteStepToExecute"
            case .couldNotFindConcreteStepToExecuteForReceivedDialogResponse: return "couldNotFindConcreteStepToExecuteForReceivedDialogResponse"
            case .theProtocolStepCancelled: return "theProtocolStepCancelled"
            case .couldNotDetermineNewProtocolState: return "couldNotDetermineNewProtocolState"
            case .couldNotUpdateProtocolState: return "couldNotUpdateProtocolState"
            case .couldNotSaveContext: return "couldNotSaveContext"
            case .couldNotDetermineTheAssociatedOwnedIdentity: return "couldNotDetermineTheAssociatedOwnedIdentity"
            case .couldNotDeleteReceivedMessage: return "Could not delete ReceivedMessage instance"
            }
        }
    }

    // MARK: Initializer
    
    init(receivedMessageId: MessageIdentifier, flowId: FlowIdentifier, delegateManager: ObvProtocolDelegateManager, prng: PRNGService) {
        self.receivedMessageId = receivedMessageId
        self.flowId = flowId
        self.delegateManager = delegateManager
        self.prng = prng
        self.log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolOperation.logCategory)
        super.init(uid: receivedMessageId.uid)
    }
    
    // MARK: Helper cancel methods
    
    private func cancelAndFinish(forReason reason: PossibleReasonForCancel) {
        reasonForCancel = reason
        cancel()
        finish()
    }
    
    private func cancel(forReason reason: PossibleReasonForCancel) {
        reasonForCancel = reason
        cancel()
    }
        
    // MARK: - Trying to execute a protocol step and performing related actions
        
    override func execute() {
        
        guard let delegateManager = delegateManager else {
            os_log("The delegate manager is not set", log: self.log, type: .fault)
            cancelAndFinish(forReason: .contextCreatorDelegateNotSet)
            assertionFailure()
            return
        }

        os_log("Starting execute()", log: log, type: .debug)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            cancelAndFinish(forReason: .contextCreatorDelegateNotSet)
            assertionFailure()
            return
        }

        contextCreator.performBackgroundTask(flowId: flowId) { [weak self] (obvContext) in
            guard let _self = self else { return }
            
            // MARK: Getting the received message out of the ReceivedMessage database
            
            guard let message = ReceivedMessage.get(messageId: _self.receivedMessageId, delegateManager: delegateManager, within: obvContext) else {
                os_log("Could not find a ReceivedMessage corresponding to the given Uid for owned identity %{public}@", log: _self.log, type: .error, _self.receivedMessageId.ownedCryptoIdentity.debugDescription)
                _self.cancelAndFinish(forReason: .messageNotFoundInDatabase)
                return
            }
            
            // MARK: Given the message, try to execute a protocol step
            
            guard let (concreteCryptoProtocolInNewState, eraseReceivedMessagesAfterReachingAFinalState) = _self.tryToExecuteAnAppropriateCryptoProtocolStep(given: message, within: obvContext) else {
                os_log("Could not transition any crypto protocol to a new state using the received message", log: _self.log, type: .error)
                if _self.reasonForCancel == nil {
                    os_log("The reason for cancel should be set at this point. This is a bug.", log: _self.log, type: .fault)
                }
                assert(_self.isFinished) // Should cancelled and finished by `tryToExecuteAnAppropriateCryptoProtocolStep`
                return
            }
            
            _self.protocolInstanceUid = concreteCryptoProtocolInNewState.instanceUid
            _self.protocolInstanceOwnedIdentity = concreteCryptoProtocolInNewState.ownedIdentity
            
            // MARK: Saving the new state of the protocol instance
            
            os_log("About to save state of %{public}@", log: _self.log, type: .info, concreteCryptoProtocolInNewState.description)
            do {
                try _self.saveStateOf(concreteCryptoProtocolInNewState, within: obvContext)
            } catch {
                os_log("Could not save the new state of the protocol", log: _self.log, type: .fault)
                _self.cancelAndFinish(forReason: .couldNotUpdateProtocolState)
                return
            }
            
            os_log("State was saved: %{public}@", log: _self.log, type: .info, concreteCryptoProtocolInNewState.description)

            
            // MARK: If other received messages exist for this same protocol instance, we notify. Note that these messages will be processed within the completion handler of the ReceivedMessageCoordinator (thus, not here)
            
            // MARK: Notifying the linked protocols
            
            _self.notifyLinkedProtocols(ofConcreteCryptoProtocolInNewState: concreteCryptoProtocolInNewState, within: obvContext)
            
            if concreteCryptoProtocolInNewState.reachedFinalState() {
                _self.deleteProtocolInstanceRelatedTo(concreteCryptoProtocolInNewState, within: obvContext)
                if eraseReceivedMessagesAfterReachingAFinalState {
                    _self.deleteRemainingReceivedMessagesRelatedTo(concreteCryptoProtocolInNewState, ownedIdentity: concreteCryptoProtocolInNewState.ownedIdentity, within: obvContext)
                }
            }
            
            // MARK: Since the operation succesfully processed the protocol message, we can delete it

            do {
                try message.deleteReceivedMessage()
            } catch {
                assertionFailure()
                _self.cancelAndFinish(forReason: .couldNotSaveContext)
                return
            }

            // MARK: Saving the context
            
            do {
                try obvContext.save(logOnFailure: _self.log)
            } catch {
                assertionFailure()
                _self.cancelAndFinish(forReason: .couldNotSaveContext)
                return
            }
            os_log("Context saved", log: _self.log, type: .debug)

            _self.finish()

        }
        
        
    }
    
    
    // MARK: - Private helper methods
    
    private func notifyLinkedProtocols(ofConcreteCryptoProtocolInNewState concreteCryptoProtocolInNewState: ConcreteCryptoProtocol, within obvContext: ObvContext) {
    
        guard let delegateManager = delegateManager else {
            os_log("The delegate manager is not set", log: log, type: .fault)
            return
        }
                
        guard let channelDelegate = delegateManager.channelDelegate else {
            os_log("The channel delegate is not set", log: log, type: .fault)
            return
        }

        do {
            let messagesToSend = try LinkBetweenProtocolInstances.getGenericProtocolMessageToSendWhenChildProtocolInstance(withUid: concreteCryptoProtocolInNewState.instanceUid,
                                                                                                                           andOwnedIdentity: concreteCryptoProtocolInNewState.ownedIdentity,
                                                                                                                           reachesState: concreteCryptoProtocolInNewState.currentState,
                                                                                                                           delegateManager: delegateManager,
                                                                                                                           within: obvContext)
            for message in messagesToSend {
                guard let messageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else { throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend") }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
        } catch let error {
            os_log("Could not post a protocol message in order to notify the parent protocol instance: %@", log: log, type: .fault, error.localizedDescription)
        }
    }
    
    /// When receiving a protocol message, we are in one of the following situations :
    /// - We can find an instance ProtocolInstance in database that matches both the protocol id and the protocolInstanceUid: we can construct and return a `ConcreteCryptoProtocol` based on this instance, with a current state set to the one that was saved in database.
    /// - We cannot find such an instance: We return a `ConcreteCryptoProtocol` with a current state set to `ConcreteProtocolInitialState`
    private func getConcreteCryptoProtocol(given message: ReceivedMessage, prng: PRNGService, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) -> ConcreteCryptoProtocol? {
        
        let cryptoProtocolId = message.cryptoProtocolId
        let protocolInstanceUid = message.protocolInstanceUid
        let ownedIdentity = message.messageId.ownedCryptoIdentity
        let messageId = message.messageId
        
        os_log("Looking for a protocol instance with uid %@ and owned identity %@ for messageId %{public}@", log: log, type: .debug, protocolInstanceUid.debugDescription, ownedIdentity.debugDescription, messageId.debugDescription)
        
        
        let concreteCryptoProtocol: ConcreteCryptoProtocol?
        
        if let protocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId,
                                                       uid: protocolInstanceUid,
                                                       ownedIdentity: ownedIdentity,
                                                       delegateManager: delegateManager,
                                                       within: obvContext) {
            
            os_log("Protocol instance with uid %@ and owned identity %@ for messageId %{public}@ was found: %@", log: log, type: .debug, protocolInstanceUid.debugDescription, ownedIdentity.debugDescription, messageId.debugDescription, protocolInstance.cryptoProtocolId.debugDescription)
            
            concreteCryptoProtocol = cryptoProtocolId.getConcreteCryptoProtocol(from: protocolInstance, prng: prng)
            if concreteCryptoProtocol == nil {
                assertionFailure()
            }
            
        } else {
            
            os_log("We could not find a protocol instance with uid %@ and owned identity %@ for messageId %{public}@", log: log, type: .debug, protocolInstanceUid.debugDescription, ownedIdentity.debugDescription, messageId.debugDescription)
                        
            // We create a protocol instance in DB (note that this checks whether the identity in the message is indeed an owned identity)
            
            guard ProtocolInstance(cryptoProtocolId: cryptoProtocolId,
                                   protocolInstanceUid: protocolInstanceUid,
                                   ownedCryptoIdentity: ownedIdentity,
                                   initialState: ConcreteProtocolInitialState(),
                                   delegateManager: delegateManager,
                                   within: obvContext) != nil else {
                                    os_log("Could not create a protocol instance with uid %@ and owned identity %@", log: log, type: .error, protocolInstanceUid.debugDescription, ownedIdentity.debugDescription)
                                    return nil
            }
            
            os_log("We just created a protocol instance of %@ with uid %@ and owned identity %@ for messageId %{public}@", log: log, type: .debug, cryptoProtocolId.debugDescription, protocolInstanceUid.debugDescription, ownedIdentity.debugDescription, messageId.debugDescription)
            
            concreteCryptoProtocol =  cryptoProtocolId.getConcreteCryptoProtocolInInitialState(instanceUid: protocolInstanceUid,
                                                                                               ownedCryptoIdentity: ownedIdentity,
                                                                                               delegateManager: delegateManager,
                                                                                               prng: prng,
                                                                                               within: obvContext)
            
        }
        
        return concreteCryptoProtocol
    }
    
    
    /// This method tries to find an appropriate crypto protocol given the received message. If it manages to do so, it tries to find an appropriate step to execute, and execute it in order to transition the concrete crypto protocol to a new state. If it manages to do so, it returns the concrete crypto protocol it obtained after executing the step, that is, in a new state that still requires to be saved in DB.
    private func tryToExecuteAnAppropriateCryptoProtocolStep(given message: ReceivedMessage, within obvContext: ObvContext) -> (concreteCryptoProtocol: ConcreteCryptoProtocol, eraseReceivedMessagesAfterReachingAFinalState: Bool)? {
        
        guard let delegateManager = delegateManager else {
            os_log("The delegate manager is not set", log: log, type: .fault)
            cancelAndFinish(forReason: .contextCreatorDelegateNotSet)
            return nil
        }

        guard let concreteCryptoProtocol = getConcreteCryptoProtocol(given: message, prng: prng, delegateManager: delegateManager, within: obvContext) else {
            os_log("Could not construct a ConcreteCryptoProtocol given the ReceivedMessage", log: log, type: .info)
            cancelAndFinish(forReason: .couldNotReconstructConcreteCryptoProtocol)
            return nil
        }
        
        os_log("We managed to get a concrete crypto protocol: %@", log: log, type: .info, concreteCryptoProtocol.description)
        
        // We reconstructed a concrete crypto protocol, that is, a crypto protocol in a well defined state. We can now try to turn the (generic) received protocol message into one of the possible concrete protocol messages of the concrete crypto protocol.
        
        guard let concreteProtocolMessage = concreteCryptoProtocol.getConcreteProtocolMessage(from: message) else {
            os_log("Could not turn the generic protocol message into a concrete protocol message for the concrete crypto protocol", log: log, type: .error)
            cancelAndFinish(forReason: .couldNotConstructConcreteProtocolMessageForTheGivenCryptoProtocol)
            assertionFailure()
            return nil
        }
        
        // We constructed a concrete crypto protocol and have a concrete protocol message for this protocol. We now try to find an appropriate concrete protocol step to execute, given the current state the protocol is in and the message we received.
        
        os_log("Trying to find a concrete step to execute with message: %@", log: log, type: .info, concreteProtocolMessage.description)
        guard let stepToExecute = concreteCryptoProtocol.getConcreteStepToExecute(message: concreteProtocolMessage) as? ProtocolStep else {
            if let userDialogUuid = message.userDialogUuid {
                cancelAndFinish(forReason: .couldNotFindConcreteStepToExecuteForReceivedDialogResponse(uuid: userDialogUuid))
            } else {
                cancelAndFinish(forReason: .couldNotFindConcreteStepToExecute)
            }
            return nil
        }
        
        // We have a step to execute.
        
        stepToExecute.execute()
        
        guard !stepToExecute.isCancelled else {
            os_log("The protocol step cancelled", log: log, type: .error)
            cancelAndFinish(forReason: .theProtocolStepCancelled)
            return nil
        }
        
        guard let newProtocolState = stepToExecute.endState else {
            os_log("Although the protocol step did not cancel, we could not determine a new protocol state", log: log, type: .fault)
            cancelAndFinish(forReason: .couldNotDetermineNewProtocolState)
            return nil
        }
        
        os_log("The message %@ lead the protocol into a new state: %@", log: log, type: .debug, concreteProtocolMessage.description, newProtocolState.description)
        
        // If we reached this point, we have a concrete crypto protocol and a new state for this protocol.
        
        let concreteCryptoProtocolInNewState = concreteCryptoProtocol.transitionedTo(newProtocolState)
        
        return (concreteCryptoProtocolInNewState, stepToExecute.eraseReceivedMessagesAfterReachingAFinalState)
    }
    
    
    /// This method looks for a protocol instance related to the concrete protocol instance passed as an input. If it manages to do
    /// so, it updates this instance with the state of the concrete crypto protocol.
    private func saveStateOf(_ concreteCryptoProtocolInNewState: ConcreteCryptoProtocol, within obvContext: ObvContext) throws {
        
        guard let delegateManager = delegateManager else {
            os_log("The delegate manager is not set", log: log, type: .fault)
            throw Self.makeError(message: "The delegate manager is not set")
        }

        let cryptoProtocolId = type(of: concreteCryptoProtocolInNewState).id
        
        guard let protocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId,
                                                          uid: concreteCryptoProtocolInNewState.instanceUid,
                                                          ownedIdentity: concreteCryptoProtocolInNewState.ownedIdentity,
                                                          delegateManager: delegateManager,
                                                          within: obvContext) else {
            throw Self.makeError(message: "Could not get protocol instance")
        }
        
        try protocolInstance.updateCurrentState(with: concreteCryptoProtocolInNewState.currentState)
    }
    
    
    private func deleteRemainingReceivedMessagesRelatedTo(_ concreteCryptoProtocol: ConcreteCryptoProtocol, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) {
        
        do {
            try ReceivedMessage.deleteAllAssociatedWithProtocolInstance(withUid: concreteCryptoProtocol.instanceUid, ownedIdentity: ownedIdentity, within: obvContext)
        } catch {
            os_log("Could not delete all the received messages associated to the protocol instance to abort", log: log, type: .error)
            return
        }
    }
    
    
    private func deleteProtocolInstanceRelatedTo(_ concreteCryptoProtocol: ConcreteCryptoProtocol, within obvContext: ObvContext) {
        do {
            try ProtocolInstance.delete(uid: concreteCryptoProtocol.instanceUid,
                                        ownedCryptoIdentity: concreteCryptoProtocol.ownedIdentity,
                                        within: obvContext)
        } catch {
            os_log("Could not delete a protocol instance that reached a final state", log: log, type: .error)
        }
    }
}

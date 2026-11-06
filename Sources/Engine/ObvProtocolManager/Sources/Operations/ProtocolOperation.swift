/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import OSLog
import CoreData
import ObvMetaManager
import ObvOperation
import ObvTypes
import ObvCrypto
import OlvidUtils

/// This operation is queued by the `ProtocolStepMetaOperationsCoordinator`.
/// Its purpose is to find a match between the protocol instance inputs and an existing protocol instance.
/// If a match is found, it determines the correct step to execute. This step, itself, is an operation that we queue here on an internal queue.
/// Note that this operation receives a context. This context is used within the protocol step operation (if one is executed). This context is only commited by the coordinator.
final class ProtocolOperation: ObvOperation, @unchecked Sendable, ObvErrorMaker {
    
    private static let logCategory = "ProtocolOperation"
    let log: OSLog
    let logger: Logger
    
    override var debugClassName: String {
        return "ProtocolOperation"
    }
    
    static let errorDomain = "ProtocolOperation"
    
    // MARK: Instance variables and constants
    
    let receivedMessageId: ObvMessageIdentifier
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
    
    init(receivedMessageId: ObvMessageIdentifier, flowId: FlowIdentifier, delegateManager: ObvProtocolDelegateManager, prng: PRNGService) {
        self.receivedMessageId = receivedMessageId
        self.flowId = flowId
        self.delegateManager = delegateManager
        self.prng = prng
        self.log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolOperation.logCategory)
        self.logger = Logger(subsystem: delegateManager.logSubsystem, category: ProtocolOperation.logCategory)
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
            logger.fault("The delegate manager is not set")
            cancelAndFinish(forReason: .contextCreatorDelegateNotSet)
            assertionFailure()
            return
        }

        logger.debug("Starting execute()")
        
        guard let contextCreator = delegateManager.contextCreator else {
            logger.fault("The context creator is not set")
            cancelAndFinish(forReason: .contextCreatorDelegateNotSet)
            assertionFailure()
            return
        }

        contextCreator.performBackgroundTask(flowId: flowId) { [weak self] obvContext in
            guard let _self = self else { return }
            let logger = _self.logger
            
            // MARK: Getting the received message out of the ReceivedMessage database
            
            guard let message = try? ReceivedMessage.get(messageId: _self.receivedMessageId, within: obvContext.context) else {
                logger.error("Could not find a ReceivedMessage corresponding to the given Uid for owned identity \(_self.receivedMessageId.ownedCryptoIdentity.debugDescription)")
                _self.cancelAndFinish(forReason: .messageNotFoundInDatabase)
                return
            }
            
            // MARK: Given the message, try to execute a protocol step
            
            guard let (concreteCryptoProtocolInNewState, eraseReceivedMessagesAfterReachingAFinalState) = _self.tryToExecuteAnAppropriateCryptoProtocolStep(given: message, within: obvContext) else {
                logger.error("Could not transition any crypto protocol to a new state using the received message")
                if _self.reasonForCancel == nil {
                    logger.fault("The reason for cancel should be set at this point. This is a bug.")
                }
                assert(_self.isFinished) // Should cancelled and finished by `tryToExecuteAnAppropriateCryptoProtocolStep`
                return
            }
            
            _self.protocolInstanceUid = concreteCryptoProtocolInNewState.instanceUid
            _self.protocolInstanceOwnedIdentity = concreteCryptoProtocolInNewState.ownedIdentity
            
            // MARK: Saving the new state of the protocol instance
            
            logger.info("About to save state of \(concreteCryptoProtocolInNewState.description, privacy: .public)")
            do {
                try _self.saveStateOf(concreteCryptoProtocolInNewState, within: obvContext)
            } catch {
                logger.fault("Could not save the new state of the protocol: \(error.localizedDescription, privacy: .public)")
                _self.cancelAndFinish(forReason: .couldNotUpdateProtocolState)
                return
            }
            
            logger.info("State was saved: \(concreteCryptoProtocolInNewState.description, privacy: .public)")

            
            // MARK: If other received messages exist for this same protocol instance, we notify. Note that these messages will be processed within the completion handler of the ReceivedMessageCoordinator (thus, not here)
            
            // MARK: Notifying the linked protocols
                        
            if concreteCryptoProtocolInNewState.reachedFinalState() {
                _self.notifyLinkedProtocols(ofConcreteCryptoProtocolInFinalState: concreteCryptoProtocolInNewState)
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
    
    private func notifyLinkedProtocols(ofConcreteCryptoProtocolInFinalState finalState: ConcreteCryptoProtocol) {
    
        guard let delegateManager = delegateManager else {
            logger.fault("The delegate manager is not set")
            assertionFailure()
            return
        }
                
        guard let channelDelegate = delegateManager.channelDelegate else {
            logger.fault("The channel delegate is not set")
            assertionFailure()
            return
        }

        do {
            let messagesToSend = try LinkBetweenProtocolInstances.getGenericProtocolMessageToSendWhenChildProtocolInstanceReachesFinalState(finalState)
            for message in messagesToSend {
                guard let messageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else { throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend") }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: finalState.obvContext)
            }
        } catch let error {
            logger.fault("Could not post a protocol message in order to notify the parent protocol instance: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    /// When receiving a protocol message, we are in one of the following situations :
    /// - We can find an instance ProtocolInstance in database that matches both the protocol id and the protocolInstanceUid: we can construct and return a `ConcreteCryptoProtocol` based on this instance, with a current state set to the one that was saved in database.
    /// - We cannot find such an instance: We return a `ConcreteCryptoProtocol` with a current state set to `ConcreteProtocolInitialState`
    private func getConcreteCryptoProtocol(given message: ReceivedMessage, prng: PRNGService, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) throws -> ConcreteCryptoProtocol? {
        
        let cryptoProtocolId = try message.cryptoProtocolId
        let protocolInstanceUid = try message.protocolInstanceUid
        let messageId = try message.messageId
        let ownedIdentity = messageId.ownedCryptoIdentity
        
        logger.debug("Looking for a protocol instance with uid \(protocolInstanceUid.debugDescription, privacy: .public) and owned identity \(ownedIdentity.debugDescription) for messageId \(messageId.debugDescription, privacy: .public)")
        
        
        let concreteCryptoProtocol: ConcreteCryptoProtocol?
        
        if let protocolInstance = try ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId,
                                                           uid: protocolInstanceUid,
                                                           ownedIdentity: ownedIdentity,
                                                           within: obvContext.context) {
            
            let cryptoProtocolIdDescription: String = (try? protocolInstance.cryptoProtocolId.debugDescription) ?? "<Could not parse crypto protocol Id>"
            logger.debug("Protocol instance with uid \(protocolInstanceUid.debugDescription, privacy: .public) and owned identity \(ownedIdentity.debugDescription) for messageId \(messageId.debugDescription, privacy: .public) was found: \(cryptoProtocolIdDescription, privacy: .public)")
            
            concreteCryptoProtocol = cryptoProtocolId.getConcreteCryptoProtocol(from: protocolInstance, prng: prng, delegateManager: delegateManager, within: obvContext)
            if concreteCryptoProtocol == nil {
                assertionFailure()
            }
            
        } else {
            
            logger.debug("We could not find a protocol instance with uid \(protocolInstanceUid.debugDescription, privacy: .public) and owned identity \(ownedIdentity.debugDescription) for messageId \(messageId.debugDescription, privacy: .public)")
                        
            // We create a protocol instance in DB (note that this checks whether the identity in the message is indeed an owned identity)
            
            guard ProtocolInstance(cryptoProtocolId: cryptoProtocolId,
                                   protocolInstanceUid: protocolInstanceUid,
                                   ownedCryptoIdentity: ownedIdentity,
                                   initialState: ConcreteProtocolInitialState(),
                                   delegateManager: delegateManager,
                                   within: obvContext) != nil else
            {
                logger.error("Could not create a protocol instance with uid \(protocolInstanceUid.debugDescription, privacy: .public) and owned identity \(ownedIdentity.debugDescription)")
                return nil
            }
            
            logger.debug("We just created a protocol instance of \(cryptoProtocolId.debugDescription, privacy: .public) with uid \(protocolInstanceUid.debugDescription, privacy: .public) and owned identity \(ownedIdentity.debugDescription) for messageId \(messageId.debugDescription, privacy: .public)")
            
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
            logger.fault("The delegate manager is not set")
            cancelAndFinish(forReason: .contextCreatorDelegateNotSet)
            return nil
        }

        guard let concreteCryptoProtocol = try? getConcreteCryptoProtocol(given: message, prng: prng, delegateManager: delegateManager, within: obvContext) else {
            logger.error("Could not construct a ConcreteCryptoProtocol given the ReceivedMessage")
            cancelAndFinish(forReason: .couldNotReconstructConcreteCryptoProtocol)
            return nil
        }
        
        logger.info("We managed to get a concrete crypto protocol: \(concreteCryptoProtocol.description, privacy: .public)")
        
        // We reconstructed a concrete crypto protocol, that is, a crypto protocol in a well defined state. We can now try to turn the (generic) received protocol message into one of the possible concrete protocol messages of the concrete crypto protocol.
        
        guard let concreteProtocolMessage = concreteCryptoProtocol.getConcreteProtocolMessage(from: message) else {
            logger.error("Could not turn the generic protocol message into a concrete protocol message for the concrete crypto protocol")
            cancelAndFinish(forReason: .couldNotConstructConcreteProtocolMessageForTheGivenCryptoProtocol)
            assertionFailure()
            return nil
        }
        
        // We constructed a concrete crypto protocol and have a concrete protocol message for this protocol. We now try to find an appropriate concrete protocol step to execute, given the current state the protocol is in and the message we received.
        
        logger.info("Trying to find a concrete step to execute with message: \(concreteProtocolMessage.description, privacy: .public)")
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
            logger.error("The protocol step cancelled")
            cancelAndFinish(forReason: .theProtocolStepCancelled)
            return nil
        }
        
        guard let newProtocolState = stepToExecute.endState else {
            logger.fault("Although the protocol step did not cancel, we could not determine a new protocol state")
            cancelAndFinish(forReason: .couldNotDetermineNewProtocolState)
            return nil
        }
        
        logger.debug("The message \(concreteProtocolMessage.description, privacy: .public) lead the protocol into a new state: \(newProtocolState.description, privacy: .public)")
        
        // If we reached this point, we have a concrete crypto protocol and a new state for this protocol.
        
        let concreteCryptoProtocolInNewState = concreteCryptoProtocol.transitionedTo(newProtocolState)
        
        return (concreteCryptoProtocolInNewState, stepToExecute.eraseReceivedMessagesAfterReachingAFinalState)
    }
    
    
    /// This method looks for a protocol instance related to the concrete protocol instance passed as an input. If it manages to do
    /// so, it updates this instance with the state of the concrete crypto protocol.
    private func saveStateOf(_ concreteCryptoProtocolInNewState: ConcreteCryptoProtocol, within obvContext: ObvContext) throws {
        
        let cryptoProtocolId = type(of: concreteCryptoProtocolInNewState).id
        
        guard let protocolInstance = try ProtocolInstance.get(
            cryptoProtocolId: cryptoProtocolId,
            uid: concreteCryptoProtocolInNewState.instanceUid,
            ownedIdentity: concreteCryptoProtocolInNewState.ownedIdentity,
            within: obvContext.context) else {
            throw Self.makeError(message: "Could not get protocol instance")
        }
        
        try protocolInstance.updateCurrentState(with: concreteCryptoProtocolInNewState.currentState)
    }
    
    
    private func deleteRemainingReceivedMessagesRelatedTo(_ concreteCryptoProtocol: ConcreteCryptoProtocol, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) {
        
        do {
            try ReceivedMessage.deleteAllAssociatedWithProtocolInstance(withUid: concreteCryptoProtocol.instanceUid, ownedIdentity: ownedIdentity, within: obvContext.context)
        } catch {
            logger.error("Could not delete all the received messages associated to the protocol instance to abort: \(error.localizedDescription, privacy: .public)")
            return
        }
    }
    
    
    private func deleteProtocolInstanceRelatedTo(_ concreteCryptoProtocol: ConcreteCryptoProtocol, within obvContext: ObvContext) {
        do {
            try ProtocolInstance.deleteProtocolInstance(uid: concreteCryptoProtocol.instanceUid,
                                                        ownedCryptoIdentity: concreteCryptoProtocol.ownedIdentity,
                                                        within: obvContext.context)
        } catch {
            logger.error("Could not delete a protocol instance that reached a final state: \(error.localizedDescription, privacy: .public)")
        }
    }
}

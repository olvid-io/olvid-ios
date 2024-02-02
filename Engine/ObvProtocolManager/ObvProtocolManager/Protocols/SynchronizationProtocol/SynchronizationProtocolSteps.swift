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


import Foundation
import os.log
import ObvTypes
import ObvMetaManager
import ObvCrypto
import OlvidUtils
import ObvEncoder

// MARK: - Protocol Steps

extension SynchronizationProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        case sendSyncAtomRequest = 0
        case processSyncAtomRequest = 1
        // case updateStateAndSendSyncSnapshot = 2
        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
                
            case .sendSyncAtomRequest:
                let step = SendSyncAtomRequestStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            case .processSyncAtomRequest:
                let step = ProcessSyncAtomRequestStep(from: concreteProtocol, and: receivedMessage)
                return step
                
//            case .updateStateAndSendSyncSnapshot:
//                if let step = UpdateStateAndSendSyncSnapshotOnInitiateSyncSnapshotMessageFromConcreteProtocolInitialState(from: concreteProtocol, and: receivedMessage) {
//                    return step
//                } else if let step = UpdateStateAndSendSyncSnapshotOnTriggerSyncSnapshotMessageFromConcreteProtocolInitialState(from: concreteProtocol, and: receivedMessage) {
//                    return step
//                } else if let step = UpdateStateAndSendSyncSnapshotOnTransferSyncSnapshotMessageFromConcreteProtocolInitialState(from: concreteProtocol, and: receivedMessage) {
//                    return step
//                } else if let step = UpdateStateAndSendSyncSnapshotOnAtomProcessedMessageFromConcreteProtocolInitialState(from: concreteProtocol, and: receivedMessage) {
//                    return step
//                } else if let step = UpdateStateAndSendSyncSnapshotOnInitiateSyncSnapshotMessageFromOngoingSyncSnapshotState(from: concreteProtocol, and: receivedMessage) {
//                    return step
//                } else if let step = UpdateStateAndSendSyncSnapshotOnTriggerSyncSnapshotMessageFromOngoingSyncSnapshotState(from: concreteProtocol, and: receivedMessage) {
//                    return step
//                } else if let step = UpdateStateAndSendSyncSnapshotOnTransferSyncSnapshotMessageFromOngoingSyncSnapshotState(from: concreteProtocol, and: receivedMessage) {
//                    return step
//                } else if let step = UpdateStateAndSendSyncSnapshotOnAtomProcessedMessageFromOngoingSyncSnapshotState(from: concreteProtocol, and: receivedMessage) {
//                    return step
//                } else {
//                    return nil
//                }
                
            }
        }
    }
    
    // MARK: - SendSyncAtomRequestStep
    
    final class SendSyncAtomRequestStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateSyncAtomMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: InitiateSyncAtomMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let syncAtom = receivedMessage.syncAtom
            
            // Send the sync atom to our other owned devices
            
            let otherDeviceUids = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
            
            if otherDeviceUids.count > 0 {
                do {
                    let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                    let concreteProtocolMessage = SyncAtomMessage(coreProtocolMessage: coreMessage, syncAtom: syncAtom)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
            }
            
            // Send an AtomProcessedMessage to all ongoing instances of the synchronisation protocol
            
//            let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
//            for otherDeviceUid in otherDeviceUids {
//                let otherProtocolInstanceUid = try SynchronizationProtocol.computeOngoingProtocolInstanceUid(ownedCryptoId: ownedIdentity, currentDeviceUid: currentDeviceUid, otherOwnedDeviceUid: otherDeviceUid)
//                let coreMessage = getCoreMessageForOtherLocalProtocol(otherCryptoProtocolId: .synchronization, otherProtocolInstanceUid: otherProtocolInstanceUid)
//                let concreteProtocolMessage = AtomProcessedMessage(coreProtocolMessage: coreMessage)
//                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
//                    assertionFailure()
//                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
//                }
//                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
//            }

            return FinalState()
            
        }
        
    }

    
    // MARK: - ProcessSyncAtomRequestStep
    
    final class ProcessSyncAtomRequestStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: SyncAtomMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: SyncAtomMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let syncAtom = receivedMessage.syncAtom
            
            // Determine the origin of the message
            
            guard let otherOwnedDeviceUID = receivedMessage.receptionChannelInfo?.getRemoteDeviceUid() else {
                assertionFailure()
                return FinalState()
            }

            // The received ObvSyncAtom shall either be transferred to the app, or to the identity manager.

            switch syncAtom.recipient {
                
            case .app:
                
                let dialogUuid = UUID()
                let dialogType = ObvChannelDialogToSendType.syncRequestReceivedFromOtherOwnedDevice(otherOwnedDeviceUID: otherOwnedDeviceUID, syncAtom: syncAtom)
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = SyncAtomDialogMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                
            case .identityManager:
                
                do {
                    try identityDelegate.processSyncAtom(syncAtom, ownedCryptoIdentity: ownedIdentity, within: obvContext)
                } catch {
                    assertionFailure(error.localizedDescription)
                    throw error
                }
                                
            case .notImplementedOniOS:
                
                break
                
            }

            // Send an AtomProcessedMessage to all ongoing instances of the synchronisation protocol
            
//            let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
//            let otherDeviceUids = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
//            for otherDeviceUid in otherDeviceUids {
//                let otherProtocolInstanceUid = try SynchronizationProtocol.computeOngoingProtocolInstanceUid(ownedCryptoId: ownedIdentity, currentDeviceUid: currentDeviceUid, otherOwnedDeviceUid: otherDeviceUid)
//                let coreMessage = getCoreMessageForOtherLocalProtocol(otherCryptoProtocolId: .synchronization, otherProtocolInstanceUid: otherProtocolInstanceUid)
//                let concreteProtocolMessage = AtomProcessedMessage(coreProtocolMessage: coreMessage)
//                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
//                    assertionFailure()
//                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
//                }
//                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
//            }

            return FinalState()
            
        }
        
    }

    
    // MARK: - UpdateStateAndSendSyncSnapshotStep
    
//    class UpdateStateAndSendSyncSnapshotStep: ProtocolStep {
//
//        enum StartStateType {
//            case initial(startState: ConcreteProtocolInitialState)
//            case ongoingSyncSnapshot(startState: OngoingSyncSnapshotState)
//        }
//
//        enum ReceivedMessageType {
//            case initiateSyncSnapshotMessage(receivedMessage: InitiateSyncSnapshotMessage)
//            case triggerSyncSnapshotMessage(receivedMessage: TriggerSyncSnapshotMessage)
//            case transferSyncSnapshot(receivedMessage: TransferSyncSnapshotMessage)
//            case atomProcessed(receivedMessage: AtomProcessedMessage)
//        }
//
//
//        private let startState: StartStateType
//        private let receivedMessage: ReceivedMessageType
//
//        init?(startState: StartStateType, receivedMessage: ReceivedMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
//            self.startState = startState
//            self.receivedMessage = receivedMessage
//            switch receivedMessage {
//            case .initiateSyncSnapshotMessage(let receivedMessage):
//                super.init(
//                    expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
//                    expectedReceptionChannelInfo: .Local,
//                    receivedMessage: receivedMessage,
//                    concreteCryptoProtocol: concreteCryptoProtocol)
//            case .triggerSyncSnapshotMessage(let receivedMessage):
//                super.init(
//                    expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
//                    expectedReceptionChannelInfo: .Local,
//                    receivedMessage: receivedMessage,
//                    concreteCryptoProtocol: concreteCryptoProtocol)
//            case .transferSyncSnapshot(let receivedMessage):
//                super.init(
//                    expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
//                    expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
//                    receivedMessage: receivedMessage,
//                    concreteCryptoProtocol: concreteCryptoProtocol)
//            case .atomProcessed(let receivedMessage):
//                super.init(
//                    expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
//                    expectedReceptionChannelInfo: .Local,
//                    receivedMessage: receivedMessage,
//                    concreteCryptoProtocol: concreteCryptoProtocol)
//            }
//        }
//
//        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
//
//            let defaultStateToReturn: ConcreteProtocolState
//            let otherOwnedDeviceUid: UID
//            let currentlyShowingDiff: Bool
//
//            let localSnapshot: ObvSyncSnapshotAndVersion?
//            let localSnapshotVersionKnownByRemote: Int?
//
//            let previouslyReceivedRemoteSnapshot: ObvSyncSnapshotAndVersion?
//            let justReceivedRemoteSnapshot: ObvSyncSnapshotAndVersion?
//
//            var sendOurSnapshot = false
//
//            switch (startState, receivedMessage) {
//
//            case (.initial, .initiateSyncSnapshotMessage(let receivedMessage)):
//                defaultStateToReturn = FinalState()
//                otherOwnedDeviceUid = receivedMessage.otherOwnedDeviceUID
//                currentlyShowingDiff = false
//                localSnapshot = nil
//                localSnapshotVersionKnownByRemote = nil
//                previouslyReceivedRemoteSnapshot = nil
//                justReceivedRemoteSnapshot = nil
//
//            case (.initial, .triggerSyncSnapshotMessage):
//                return FinalState()
//
//            case (.initial(let startState), .transferSyncSnapshot(let receivedMessage)):
//                defaultStateToReturn = FinalState()
//                guard let remoteDeviceUid = receivedMessage.receptionChannelInfo?.getRemoteDeviceUid() else {
//                    assertionFailure()
//                    return startState
//                }
//                otherOwnedDeviceUid = remoteDeviceUid
//                currentlyShowingDiff = false
//                localSnapshot = nil
//                localSnapshotVersionKnownByRemote = receivedMessage.localVersionKnownBySender
//                previouslyReceivedRemoteSnapshot = nil
//                justReceivedRemoteSnapshot = receivedMessage.remoteSyncSnapshotAndVersion
//
//            case (.initial, .atomProcessed):
//                return FinalState()
//
//            case (.ongoingSyncSnapshot(let startState), .initiateSyncSnapshotMessage):
//                return startState
//
//            case (.ongoingSyncSnapshot(let startState), .triggerSyncSnapshotMessage(let receivedMessage)):
//                defaultStateToReturn = startState
//                otherOwnedDeviceUid = startState.otherOwnedDeviceUid
//                currentlyShowingDiff = startState.currentlyShowingDiff
//                localSnapshot = startState.localSnapshot
//                localSnapshotVersionKnownByRemote = nil
//                previouslyReceivedRemoteSnapshot = startState.remoteSnapshot
//                justReceivedRemoteSnapshot = nil
//                sendOurSnapshot = receivedMessage.forceSendSnapshot
//
//            case (.ongoingSyncSnapshot(let startState), .transferSyncSnapshot(let receivedMessage)):
//                defaultStateToReturn = startState
//                guard let remoteDeviceUid = receivedMessage.receptionChannelInfo?.getRemoteDeviceUid() else {
//                    assertionFailure()
//                    return startState
//                }
//                guard remoteDeviceUid == startState.otherOwnedDeviceUid else {
//                    assertionFailure()
//                    return startState
//                }
//                otherOwnedDeviceUid = remoteDeviceUid
//                currentlyShowingDiff = startState.currentlyShowingDiff
//                localSnapshot = startState.localSnapshot
//                localSnapshotVersionKnownByRemote = receivedMessage.localVersionKnownBySender
//                previouslyReceivedRemoteSnapshot = startState.remoteSnapshot
//                justReceivedRemoteSnapshot = receivedMessage.remoteSyncSnapshotAndVersion
//
//            case (.ongoingSyncSnapshot(let startState), .atomProcessed):
//                defaultStateToReturn = startState
//                otherOwnedDeviceUid = startState.otherOwnedDeviceUid
//                currentlyShowingDiff = startState.currentlyShowingDiff
//                localSnapshot = startState.localSnapshot
//                localSnapshotVersionKnownByRemote = nil
//                previouslyReceivedRemoteSnapshot = startState.remoteSnapshot
//                justReceivedRemoteSnapshot = nil
//
//            }
//
//            // Check that the protocolUid matches what we expect
//
//            let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
//            guard try self.protocolInstanceUid == SynchronizationProtocol.computeOngoingProtocolInstanceUid(ownedCryptoId: ownedIdentity, currentDeviceUid: currentDeviceUid, otherOwnedDeviceUid: otherOwnedDeviceUid) else {
//                assertionFailure()
//                return defaultStateToReturn
//            }
//
//            // In case we received a snapshot or have a previously received snapshot, we want to determine the one that is the most appropriate to continue with (we call it the "last seen" snapshot)
//
//            let updatedRemoteSnapshot: ObvSyncSnapshotAndVersion?
//
//            switch determineUpdatedRemoteSnapshot(justReceivedRemoteSnapshot: justReceivedRemoteSnapshot, previouslyReceivedRemoteSnapshot: previouslyReceivedRemoteSnapshot) {
//            case .stopStep:
//                return defaultStateToReturn
//            case .updatedRemoteSnapshot(let snapshot):
//                updatedRemoteSnapshot = snapshot
//            }
//
//            // In rare cases, we might have restarted this protocol and, consequently, reset the version of the localSnapshot back to 0.
//            // In that situation, the remote device might have previously received from us a snapshot with a version larger than ours.
//            // If we do nothing, the snapshot we would send her now would be discarder. So we update our version if required.
//            // In case we update our version, we always decide to eventually send our local snapshot back.
//
//            let updatedLocalSnapshot: ObvSyncSnapshotAndVersion
//
//            do {
//
//                let localSnapshotWithUpdatedVersion: ObvSyncSnapshotAndVersion?
//
//                if let localSnapshotVersionKnownByRemote, let localSnapshot, localSnapshotVersionKnownByRemote > localSnapshot.version {
//
//                    localSnapshotWithUpdatedVersion = ObvSyncSnapshotAndVersion(
//                        version: localSnapshotVersionKnownByRemote + 1,
//                        syncSnapshot: localSnapshot.syncSnapshot)
//
//                    sendOurSnapshot = true
//
//                } else {
//
//                    localSnapshotWithUpdatedVersion = localSnapshot
//
//                }
//
//                // Now that the version of the local snapshot is correct, we want it to reflect the latest state of the current device.
//
//                let syncSnapshot = try syncSnapshotDelegate.makeObvSyncSnapshot(within: obvContext)
//                let localSnapshotChanged = syncSnapshot.isContentIdenticalTo(other: localSnapshotWithUpdatedVersion?.syncSnapshot)
//                let version: Int
//
//                if localSnapshotChanged {
//                    version = (localSnapshotWithUpdatedVersion?.version ?? 0) + 1
//                    sendOurSnapshot = true
//                } else {
//                    version = (localSnapshotWithUpdatedVersion?.version ?? 0)
//                }
//
//                updatedLocalSnapshot = ObvSyncSnapshotAndVersion(version: version, syncSnapshot: syncSnapshot)
//
//            }
//
//            // Decide whether we should compute a diff to show to the user. This will be the case if:
//            // - We have a remote snapshot to compare to (obviously)
//            // - AND:
//            //   - we are currently showing a diff
//            //   - OR we received a snapshot with a localSnapshotKnownByRemote.version == updatedLocalSnapshot.version
//            // In both cases, if the diff we compute is empty, we stop showing a diff to the user
//
//            let computedDiffsToShow: Set<ObvSyncDiff>?
//            if let updatedRemoteSnapshot {
//                let shouldComputeDiff = currentlyShowingDiff || (localSnapshotVersionKnownByRemote == updatedLocalSnapshot.version)
//                if shouldComputeDiff {
//                    computedDiffsToShow = updatedLocalSnapshot.syncSnapshot.computeDiff(withOther: updatedRemoteSnapshot.syncSnapshot)
//                } else {
//                    computedDiffsToShow = nil
//                }
//            } else {
//                computedDiffsToShow = nil
//            }
//
//            // If we decided to send our updated local snapshot, do it now
//
//            if sendOurSnapshot {
//                let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.ObliviousChannel(to: ownedIdentity, remoteDeviceUids: [otherOwnedDeviceUid], fromOwnedIdentity: ownedIdentity, necessarilyConfirmed: true))
//                let concreteMessage = TransferSyncSnapshotMessage(coreProtocolMessage: coreMessage, remoteSyncSnapshotAndVersion: updatedLocalSnapshot, localVersionKnownBySender: updatedRemoteSnapshot?.version)
//                guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
//                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
//            }
//
//            // If we decided to show diffs to the user, do it now
//
//            if let computedDiffsToShow {
//                syncSnapshotDelegate.newSyncDiffsToProcessOrShowToUser(computedDiffsToShow, withOtherOwnedDeviceUid: otherOwnedDeviceUid)
//            }
//
//            // We stay in an ongoing state "forever" (until the remote device is removed)
//
//            return OngoingSyncSnapshotState(
//                otherOwnedDeviceUid: otherOwnedDeviceUid,
//                localSnapshot: updatedLocalSnapshot,
//                remoteSnapshot: updatedRemoteSnapshot,
//                currentlyShowingDiff: computedDiffsToShow != nil)
//
//        }
//
//
//        private enum LastSeenReceivedSnapShotAndVersionOrStopStep {
//            case updatedRemoteSnapshot(snapshot: ObvSyncSnapshotAndVersion?)
//            case stopStep
//        }
//
//
//        /// Returns the most appropriate snapshot and version to consider in the rest of the step. In some occasions, we want to stop the step execution.
//        private func determineUpdatedRemoteSnapshot(justReceivedRemoteSnapshot: ObvSyncSnapshotAndVersion?, previouslyReceivedRemoteSnapshot: ObvSyncSnapshotAndVersion?) -> LastSeenReceivedSnapShotAndVersionOrStopStep {
//
//            if let justReceivedRemoteSnapshot {
//
//                if let previouslyReceivedRemoteSnapshot {
//
//                    // We have both a previously received snapshot and a just received snapshot
//                    if justReceivedRemoteSnapshot.version < previouslyReceivedRemoteSnapshot.version {
//                        // The snapshot we just received is older than the one we already knew about, we discard it and there is nothing left to do
//                        return .stopStep
//                    } else if justReceivedRemoteSnapshot.version == previouslyReceivedRemoteSnapshot.version {
//                        // Weird, the snapshot we just received has the same version than the one we already knew about. If the content are the same, we can ignore the received message.
//                        if justReceivedRemoteSnapshot.syncSnapshot.isContentIdenticalTo(other: previouslyReceivedRemoteSnapshot.syncSnapshot) {
//                            return .stopStep
//                        } else {
//                            // The just received snapshot "replaces" the previous one
//                            return .updatedRemoteSnapshot(snapshot: justReceivedRemoteSnapshot)
//                        }
//                    } else {
//                        // The snapshot we received is more recent than the one we received previously, we keep the most recent one
//                        return .updatedRemoteSnapshot(snapshot: justReceivedRemoteSnapshot)
//                    }
//
//                } else {
//
//                    return .updatedRemoteSnapshot(snapshot: justReceivedRemoteSnapshot)
//
//                }
//
//            } else {
//
//                return .updatedRemoteSnapshot(snapshot: previouslyReceivedRemoteSnapshot)
//
//            }
//
//        }
//
//    }
    

    // MARK: UpdateStateAndSendSyncSnapshotStep on InitiateSyncSnapshotMessage from ConcreteProtocolInitialState

//    final class UpdateStateAndSendSyncSnapshotOnInitiateSyncSnapshotMessageFromConcreteProtocolInitialState: UpdateStateAndSendSyncSnapshotStep, TypedConcreteProtocolStep {
//
//        let startState: ConcreteProtocolInitialState
//        let receivedMessage: InitiateSyncSnapshotMessage
//
//        init?(startState: ConcreteProtocolInitialState, receivedMessage: InitiateSyncSnapshotMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
//            self.startState = startState
//            self.receivedMessage = receivedMessage
//            super.init(
//                startState: .initial(startState: startState),
//                receivedMessage: .initiateSyncSnapshotMessage(receivedMessage: receivedMessage),
//                concreteCryptoProtocol: concreteCryptoProtocol)
//        }
//
//    }

    
    // MARK: UpdateStateAndSendSyncSnapshotStep on TriggerSyncSnapshotMessage from ConcreteProtocolInitialState

//    final class UpdateStateAndSendSyncSnapshotOnTriggerSyncSnapshotMessageFromConcreteProtocolInitialState: UpdateStateAndSendSyncSnapshotStep, TypedConcreteProtocolStep {
//
//        let startState: ConcreteProtocolInitialState
//        let receivedMessage: TriggerSyncSnapshotMessage
//
//        init?(startState: ConcreteProtocolInitialState, receivedMessage: TriggerSyncSnapshotMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
//            self.startState = startState
//            self.receivedMessage = receivedMessage
//            super.init(
//                startState: .initial(startState: startState),
//                receivedMessage: .triggerSyncSnapshotMessage(receivedMessage: receivedMessage),
//                concreteCryptoProtocol: concreteCryptoProtocol)
//        }
//
//    }

    
    // MARK: UpdateStateAndSendSyncSnapshotStep on TransferSyncSnapshotMessage from ConcreteProtocolInitialState

//    final class UpdateStateAndSendSyncSnapshotOnTransferSyncSnapshotMessageFromConcreteProtocolInitialState: UpdateStateAndSendSyncSnapshotStep, TypedConcreteProtocolStep {
//
//        let startState: ConcreteProtocolInitialState
//        let receivedMessage: TransferSyncSnapshotMessage
//
//        init?(startState: ConcreteProtocolInitialState, receivedMessage: TransferSyncSnapshotMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
//            self.startState = startState
//            self.receivedMessage = receivedMessage
//            super.init(
//                startState: .initial(startState: startState),
//                receivedMessage: .transferSyncSnapshot(receivedMessage: receivedMessage),
//                concreteCryptoProtocol: concreteCryptoProtocol)
//        }
//
//    }

    
    // MARK: UpdateStateAndSendSyncSnapshotStep on AtomProcessedMessage from ConcreteProtocolInitialState

//    final class UpdateStateAndSendSyncSnapshotOnAtomProcessedMessageFromConcreteProtocolInitialState: UpdateStateAndSendSyncSnapshotStep, TypedConcreteProtocolStep {
//
//        let startState: ConcreteProtocolInitialState
//        let receivedMessage: AtomProcessedMessage
//
//        init?(startState: ConcreteProtocolInitialState, receivedMessage: AtomProcessedMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
//            self.startState = startState
//            self.receivedMessage = receivedMessage
//            super.init(
//                startState: .initial(startState: startState),
//                receivedMessage: .atomProcessed(receivedMessage: receivedMessage),
//                concreteCryptoProtocol: concreteCryptoProtocol)
//        }
//
//    }

    
    // MARK: UpdateStateAndSendSyncSnapshotStep on InitiateSyncSnapshotMessage from OngoingSyncSnapshotState

//    final class UpdateStateAndSendSyncSnapshotOnInitiateSyncSnapshotMessageFromOngoingSyncSnapshotState: UpdateStateAndSendSyncSnapshotStep, TypedConcreteProtocolStep {
//
//        let startState: OngoingSyncSnapshotState
//        let receivedMessage: InitiateSyncSnapshotMessage
//
//        init?(startState: OngoingSyncSnapshotState, receivedMessage: InitiateSyncSnapshotMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
//            self.startState = startState
//            self.receivedMessage = receivedMessage
//            super.init(
//                startState: .ongoingSyncSnapshot(startState: startState),
//                receivedMessage: .initiateSyncSnapshotMessage(receivedMessage: receivedMessage),
//                concreteCryptoProtocol: concreteCryptoProtocol)
//        }
//
//    }

    
    // MARK: UpdateStateAndSendSyncSnapshotStep on TriggerSyncSnapshotMessage from OngoingSyncSnapshotState

//    final class UpdateStateAndSendSyncSnapshotOnTriggerSyncSnapshotMessageFromOngoingSyncSnapshotState: UpdateStateAndSendSyncSnapshotStep, TypedConcreteProtocolStep {
//
//        let startState: OngoingSyncSnapshotState
//        let receivedMessage: TriggerSyncSnapshotMessage
//
//        init?(startState: OngoingSyncSnapshotState, receivedMessage: TriggerSyncSnapshotMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
//            self.startState = startState
//            self.receivedMessage = receivedMessage
//            super.init(
//                startState: .ongoingSyncSnapshot(startState: startState),
//                receivedMessage: .triggerSyncSnapshotMessage(receivedMessage: receivedMessage),
//                concreteCryptoProtocol: concreteCryptoProtocol)
//        }
//
//    }

    
    // MARK: UpdateStateAndSendSyncSnapshotStep on TransferSyncSnapshotMessage from OngoingSyncSnapshotState

//    final class UpdateStateAndSendSyncSnapshotOnTransferSyncSnapshotMessageFromOngoingSyncSnapshotState: UpdateStateAndSendSyncSnapshotStep, TypedConcreteProtocolStep {
//
//        let startState: OngoingSyncSnapshotState
//        let receivedMessage: TransferSyncSnapshotMessage
//
//        init?(startState: OngoingSyncSnapshotState, receivedMessage: TransferSyncSnapshotMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
//            self.startState = startState
//            self.receivedMessage = receivedMessage
//            super.init(
//                startState: .ongoingSyncSnapshot(startState: startState),
//                receivedMessage: .transferSyncSnapshot(receivedMessage: receivedMessage),
//                concreteCryptoProtocol: concreteCryptoProtocol)
//        }
//
//    }

    
    // MARK: UpdateStateAndSendSyncSnapshotStep on AtomProcessedMessage from OngoingSyncSnapshotState

//    final class UpdateStateAndSendSyncSnapshotOnAtomProcessedMessageFromOngoingSyncSnapshotState: UpdateStateAndSendSyncSnapshotStep, TypedConcreteProtocolStep {
//
//        let startState: OngoingSyncSnapshotState
//        let receivedMessage: AtomProcessedMessage
//
//        init?(startState: OngoingSyncSnapshotState, receivedMessage: AtomProcessedMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
//            self.startState = startState
//            self.receivedMessage = receivedMessage
//            super.init(
//                startState: .ongoingSyncSnapshot(startState: startState),
//                receivedMessage: .atomProcessed(receivedMessage: receivedMessage),
//                concreteCryptoProtocol: concreteCryptoProtocol)
//        }
//
//    }
    
}

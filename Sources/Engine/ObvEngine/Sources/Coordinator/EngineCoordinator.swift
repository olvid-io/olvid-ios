/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvMetaManager
import ObvTypes
import ObvCrypto
import OlvidUtils


// This engine coordinator is *only* used when starting the full engine.
final class EngineCoordinator {
        
    private let logger: Logger
    private let log: OSLog
    private let logSubsystem: String
    private let prng: PRNGService
    private weak var appNotificationCenter: NotificationCenter?
    private let queueForComposedOperations: OperationQueue
    
    init(logSubsystem: String, prng: PRNGService, queueForComposedOperations: OperationQueue, appNotificationCenter: NotificationCenter) {
        self.log = OSLog(subsystem: logSubsystem, category: "EngineCoordinator")
        self.logger = Logger(subsystem: logSubsystem, category: "EngineCoordinator")
        self.logSubsystem = logSubsystem
        self.prng = prng
        self.appNotificationCenter = appNotificationCenter
        self.queueForComposedOperations = queueForComposedOperations
    }
    
    private var notificationCenterTokens = [NSObjectProtocol]()
    weak var delegateManager: ObvMetaManager? {
        didSet {
            if delegateManager != nil {
                listenToEngineNotifications()
                Task { [weak self] in await self?.bootstrap() }
            }
        }
    }
    weak var obvEngine: ObvEngine?
    
    private func listenToEngineNotifications() {
        
        guard let notificationDelegate = self.delegateManager?.notificationDelegate else { assertionFailure(); return }
        
        // Listening to ObvIdentityNotificationNew
        
        notificationCenterTokens.append(contentsOf: [
            ObvIdentityNotificationNew.observeOwnedIdentityWasReactivated(within: notificationDelegate) { [weak self] (ownedCryptoIdentity, flowId) in
                self?.processOwnedIdentityWasReactivated(ownedCryptoIdentity: ownedCryptoIdentity, flowId: flowId) // ok
            },
            ObvIdentityNotificationNew.observeNewActiveOwnedIdentity(within: notificationDelegate) { [weak self] (ownedCryptoIdentity, flowId) in
                self?.processNewActiveOwnedIdentity(ownedCryptoIdentity: ownedCryptoIdentity, flowId: flowId) // ok
            },
            ObvIdentityNotificationNew.observeDeletedContactDevice(within: notificationDelegate) { [weak self] (ownedIdentity, contactIdentity, contactDeviceUid, flowId) in
                self?.deleteObliviousChannelBetweenThisDeviceAndRemoteDevice(ownedIdentity: ownedIdentity, remoteDeviceUid: contactDeviceUid, remoteIdentity: contactIdentity, flowId: flowId) // ok
            },
            ObvIdentityNotificationNew.observeNewOwnedIdentityWithinIdentityManager(within: notificationDelegate) { [weak self] cryptoIdentity in
                Task { [weak self] in await self?.processNewOwnedIdentityWithinIdentityManager(ownedCryptoIdentity: cryptoIdentity) }
            },
            ObvIdentityNotificationNew.observeContactIsCertifiedByOwnKeycloakStatusChanged(within: notificationDelegate) { [weak self] ownedIdentity, contactIdentity, newIsCertifiedByOwnKeycloak in
                Task { [weak self] in await self?.processContactIsCertifiedByOwnKeycloakStatusChanged(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, newIsCertifiedByOwnKeycloak: newIsCertifiedByOwnKeycloak) }
            },
            ObvIdentityNotificationNew.observeContactIdentityIsNowTrusted(within: notificationDelegate) { [weak self] contactIdentity, ownedIdentity, flowId in
                Task { [weak self] in await self?.processContactIdentityIsNowTrusted(contactIdentity: contactIdentity, ownedIdentity: ownedIdentity, flowId: flowId) }
            },
            ObvIdentityNotificationNew.observeNewContactDevice(within: notificationDelegate) { [weak self] (ownedIdentity, contactIdentity, contactDeviceUid, createdDuringChannelCreation, flowId) in
                self?.processNewContactDevice(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, contactDeviceUid: contactDeviceUid, createdDuringChannelCreation: createdDuringChannelCreation, flowId: flowId)
            },
            ObvIdentityNotificationNew.observeNewRemoteOwnedDevice(within: notificationDelegate) { [weak self] ownedCryptoId, remoteDeviceUid, createdDuringChannelCreation in
                Task { [weak self] in await self?.processNewRemoteOwnedDevice(ownedCryptoId: ownedCryptoId, remoteDeviceUid: remoteDeviceUid, createdDuringChannelCreation: createdDuringChannelCreation) }
            },
        ])
        
        // Listening to ObvChannelNotification

        notificationCenterTokens.append(contentsOf: [
            ObvChannelNotification.observeNewConfirmedObliviousChannel(within: notificationDelegate) { [weak self] (currentDeviceUid, remoteCryptoIdentity, remoteDeviceUid) in
                self?.processNewConfirmedObliviousChannelNotification(currentDeviceUid: currentDeviceUid, remoteCryptoIdentity: remoteCryptoIdentity, remoteDeviceUid: remoteDeviceUid) // ok
            },
        ])
        
        // Listening to ObvNetworkFetchNotificationNew

        notificationCenterTokens.append(contentsOf: [
            ObvNetworkFetchNotificationNew.observeOwnedDevicesMessageReceivedViaWebsocket(within: notificationDelegate) { [weak self] ownedCryptoIdentity in
                self?.processOwnedDevicesMessageReceivedViaWebsocket(ownedIdentity: ownedCryptoIdentity)
            },
            ObvNetworkFetchNotificationNew.observeServerAndInboxContainNoMoreUnprocessedMessages(within: notificationDelegate) { [weak self] ownedCryptoIdentity, downloadTimestampFromServer in
                Task { [weak self] in await self?.processServerAndInboxContainNoMoreUnprocessedMessages(ownedIdentity: ownedCryptoIdentity, downloadTimestampFromServer: downloadTimestampFromServer) }
            },
            ObvNetworkFetchNotificationNew.observeApplicationMessagesDecrypted(within: notificationDelegate) { obvMessageOrObvOwnedMessages, flowId in
                Task { [weak self] in await self?.processApplicationMessageDecrypted(obvMessageOrObvOwnedMessages: obvMessageOrObvOwnedMessages, flowId: flowId) }
            },
        ])
        
    }
    
}

extension EngineCoordinator {
    
    private func bootstrap() async {
        let flowId = FlowIdentifier()
        deleteItemsAssociatedToNonExistingOwnedIdentity(flowId: flowId)
        await deleteObsoleteObliviousChannels(flowId: flowId)
        await pingAppropriateRemoteDevicesWithoutChannelOperation(flowId: flowId)
        startDeviceDiscoveryProtocolForContactsHavingNoDevice(flowId: flowId)
        await pruneObsoletePersistedEngineDialogs(flowId: flowId)
        await sendTargetedPingMessageForKeycloakGroupV2ProtocolWhereContactIsPending(flowId: flowId)
    }
    

    private func sendTargetedPingMessageForKeycloakGroupV2ProtocolWhereContactIsPending(flowId: FlowIdentifier) async {
        do {

            guard let delegateManager else { assertionFailure(); throw ObvError.delegateManagerIsNotSet }
            guard let identityDelegate = delegateManager.identityDelegate else { assertionFailure(); throw ObvError.theIdentityDelegateIsNotSet }
            guard let channelDelegate = delegateManager.channelDelegate else { assertionFailure(); return }
            guard let protocolDelegate = delegateManager.protocolDelegate else { assertionFailure(); return }

            let keycloakPendingContactMembersForOwnedIdentity = try await getAllKeycloakContactsThatArePendingInSomeKeycloakGroup(flowId: flowId)
            
            let contactIdentifiers = Set(keycloakPendingContactMembersForOwnedIdentity.flatMap { (ownedCryptoId, pendingContactsCryptoIds) in
                pendingContactsCryptoIds.map { pendingContact in
                    return ObvContactIdentifier(contactCryptoId: ObvCryptoId(cryptoIdentity: pendingContact), ownedCryptoId: ObvCryptoId(cryptoIdentity: ownedCryptoId))
                }
            })
            
            guard !contactIdentifiers.isEmpty else { return }
            
            let op1 = SendTargetedPingMessageForKeycloakGroupV2ProtocolWhereContactIsPendingMemberOperation(
                identityDelegate: identityDelegate,
                channelDelegate: channelDelegate,
                protocolDelegate: protocolDelegate,
                prng: prng,
                contactIdentifiers: contactIdentifiers,
                logSubsystem: logSubsystem)
            
            do {
                let composedOp = try createCompositionOfOneContextualOperation(op1: op1)
                try await protocolDelegate.executeOnQueueForProtocolOperations(operation: composedOp)
                os_log("Successful pinged keycloak contacts in group where they are pending", log: log, type: .info)
            } catch {
                assertionFailure(error.localizedDescription)
                os_log("Failed to ping keycloak contacts in group where they are pending: %{public}@", log: log, type: .fault, error.localizedDescription)
            }

        } catch {
            assertionFailure(error.localizedDescription)
        }
    }
    
    
    private func getAllKeycloakContactsThatArePendingInSomeKeycloakGroup(flowId: FlowIdentifier) async throws -> [ObvCryptoIdentity: Set<ObvCryptoIdentity>] {
        
        guard let delegateManager else { assertionFailure(); throw ObvError.delegateManagerIsNotSet }
        guard let identityDelegate = delegateManager.identityDelegate else { assertionFailure(); throw ObvError.theIdentityDelegateIsNotSet }
        guard let createContextDelegate = delegateManager.createContextDelegate else { assertionFailure(); throw ObvError.theCreateContextDelegateIsNotSet }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ObvCryptoIdentity: Set<ObvCryptoIdentity>], Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let result = try identityDelegate.getAllKeycloakContactsThatArePendingInSomeKeycloakGroup(within: obvContext)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
    
    private func pingAppropriateRemoteDevicesWithoutChannelOperation(flowId: FlowIdentifier) async {
        
        do {
            
            guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }
            guard let channelDelegate = delegateManager?.channelDelegate else { assertionFailure(); return }
            guard let protocolDelegate = delegateManager?.protocolDelegate else { assertionFailure(); return }
            
            let op1 = PingAppropriateRemoteDevicesWithoutChannelOperation(
                identityDelegate: identityDelegate,
                channelDelegate: channelDelegate,
                protocolDelegate: protocolDelegate,
                prng: prng)
            
            let composedOp = try createCompositionOfOneContextualOperation(op1: op1)
            
            try await protocolDelegate.executeOnQueueForProtocolOperations(operation: composedOp)
            
        } catch {
            assertionFailure(error.localizedDescription)
            os_log("Failed to ping appropriate remote devices without channel: %{public}@", log: log, type: .fault, error.localizedDescription)
        }
        
    }
    
    
    private func processNewOwnedIdentityWithinIdentityManager(ownedCryptoIdentity: ObvCryptoIdentity) async {
        guard let obvEngine else { assertionFailure(); return }
        do {
            try obvEngine.downloadAllUserData()
        } catch {
            os_log("Could not download all user data after restoring backup: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
        do {
            try await informTheNetworkFetchManagerOfTheLatestSetOfOwnedIdentities()
        } catch {
            os_log("Failed to inform the network fetch manager about the latest owned identities: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
    
    
    private func pruneObsoletePersistedEngineDialogs(flowId: FlowIdentifier) async {
        
        guard let delegateManager else { assertionFailure(); return }
        guard let protocolDelegate = delegateManager.protocolDelegate else { assertionFailure(); return }
        guard let appNotificationCenter = self.appNotificationCenter else { return }
        
        let op1 = PruneObsoletePersistedEngineDialogsOperation(appNotificationCenter: appNotificationCenter)

        do {
            let composedOp = try createCompositionOfOneContextualOperation(op1: op1, flowId: flowId)
            try await protocolDelegate.executeOnQueueForProtocolOperations(operation: composedOp)
            logger.info("Successful prunned obsolete persisted engine dialogs")
        } catch {
            assertionFailure(error.localizedDescription)
            logger.fault("Failed to prune obsolete persisted engine dialogs: \(error.localizedDescription)")
        }
        
    }

    
    /// When we delete a contact device, we normaly catch a notification allowing to delete all associated oblivious channels, but this is not atomic.
    /// This method scans all Oblivious channels an makes sure that there is still an associated device within the identity manager.
    /// If not, we delete the channel.
    private func deleteObsoleteObliviousChannels(flowId: FlowIdentifier) async {
        
        guard let delegateManager else { assertionFailure(); return }
        guard let channelDelegate = delegateManager.channelDelegate else { assertionFailure(); return }
        guard let identityDelegate = delegateManager.identityDelegate else { assertionFailure(); return }
        guard let protocolDelegate = delegateManager.protocolDelegate else { assertionFailure(); return }
        
        let op1 = DeleteObsoleteObliviousChannelsOperation(channelDelegate: channelDelegate, identityDelegate: identityDelegate, logSubsystem: logSubsystem)
        
        do {
            let composedOp = try createCompositionOfOneContextualOperation(op1: op1, flowId: flowId)
            try await protocolDelegate.executeOnQueueForProtocolOperations(operation: composedOp)
            logger.info("Successful deleted obsolete oblivious channels")
        } catch {
            assertionFailure(error.localizedDescription)
            logger.fault("Failed to delete obsolete oblivious channels: \(error.localizedDescription)")
        }
        
    }

}

// MARK: - Finalizing initialization

extension EngineCoordinator {
    
    /// Ask for all contact devices then check if a channel exists with that device. If not, check whether there is an ongoing channel creation protocol. If not, launch one.
    private func startChannelCreationProtocolWithContactDevicesHavingNoChannelAndNoOngoingChannelCreationProtocol(flowId: FlowIdentifier) {
        
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }
        guard let protocolDelegate = delegateManager?.protocolDelegate else { assertionFailure(); return }
        guard let channelDelegate = delegateManager?.channelDelegate else { assertionFailure(); return }

        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            guard let ownedIdentities = try? identityDelegate.getOwnedIdentities(restrictToActive: true, within: obvContext) else {
                os_log("Could not get owned identities", log: log, type: .fault)
                assertionFailure()
                return
            }
            
            let channelCreationProtocols: Set<ObliviousChannelIdentifierAlt>
            do {
                channelCreationProtocols = try protocolDelegate.getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithContactDeviceProtocolInstances(within: obvContext)
            } catch {
                os_log("Could not get the list of ongoing channel creations protocols", log: log, type: .fault)
                assertionFailure()
                return
            }

            for ownedIdentity in ownedIdentities {
                
                let contacts: Set<ObvCryptoIdentity>
                do {
                    contacts = try identityDelegate.getContactsOfOwnedIdentity(ownedIdentity, within: obvContext)
                } catch {
                    os_log("Could not get contacts", log: log, type: .fault)
                    assertionFailure()
                    continue
                }
                
                for contact in contacts {

                    let contactDevices: Set<UID>
                    do {
                        contactDevices = try identityDelegate.getDeviceUidsOfContactIdentity(contact, ofOwnedIdentity: ownedIdentity, within: obvContext)
                    } catch {
                        os_log("Could not get contact devices", log: log, type: .fault)
                        assertionFailure()
                        continue
                    }
                    
                    for device in contactDevices {
                        
                        let channelExists: Bool
                        do {
                            channelExists = try channelDelegate.anObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andRemoteIdentity: contact, withRemoteDeviceUid: device, within: obvContext)
                        } catch {
                            os_log("Could not query de channel manager", log: log, type: .fault)
                            assertionFailure()
                            continue
                        }
                        
                        if channelExists { continue }
                        
                        // If we reach this point, we have no channel with the contact device.
                        // We check whether there is a channel creation protocol already handling this situation.
                        
                        let channelCreationToFind = ObliviousChannelIdentifierAlt(ownedCryptoIdentity: ownedIdentity, remoteCryptoIdentity: contact, remoteDeviceUid: device)
                        if channelCreationProtocols.contains(channelCreationToFind) { continue }
                        
                        // If we reach this point, we can start a channel creation protocol
                        
                        os_log("🛟 [%{public}@] Since no channel exists with a device of the contact, and there is no ongoing channel creation, we start a channel creation now", log: log, type: .info, contact.debugDescription)

                        let msg: ObvChannelProtocolMessageToSend
                        do {
                            msg = try protocolDelegate.getInitialMessageForChannelCreationWithContactDeviceProtocol(betweenTheCurrentDeviceOfOwnedIdentity: ownedIdentity, andTheDeviceUid: device, ofTheContactIdentity: contact)
                        } catch {
                            os_log("Could not get initial message for starting a channel creation with contact device", log: log, type: .fault)
                            assertionFailure()
                            continue
                        }
                        
                        do {
                            _ = try channelDelegate.postChannelMessage(msg, randomizedWith: prng, within: obvContext)
                        } catch {
                            os_log("Could not start channel creation protocol with contact device", log: log, type: .fault)
                            assertionFailure()
                            continue
                        }
                        
                    }

                }
                
            }
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not perform startChannelCreationProtocolWithContactDevicesHavingNoChannelAndNoOngoingChannelCreationProtocol: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
            
        }
        
    }
    
    
    /// Ask for all other owned devices then check if a channel exists with that device. If not, check whether there is an ongoing channel creation protocol. If not, launch one.
    private func startChannelCreationProtocolWithOtherOwnedDevicesHavingNoChannelAndNoOngoingChannelCreationProtocol(flowId: FlowIdentifier) {
        
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }
        guard let protocolDelegate = delegateManager?.protocolDelegate else { assertionFailure(); return }
        guard let channelDelegate = delegateManager?.channelDelegate else { assertionFailure(); return }

        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            guard let ownedIdentities = try? identityDelegate.getOwnedIdentities(restrictToActive: true, within: obvContext) else {
                os_log("Could not get owned identities", log: log, type: .fault)
                assertionFailure()
                return
            }
            
            let channelCreationProtocols: Set<ObliviousChannelIdentifierAlt>
            do {
                channelCreationProtocols = try protocolDelegate.getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithOwnedDeviceProtocolInstances(within: obvContext)
            } catch {
                os_log("Could not get the list of ongoing channel creations protocols", log: log, type: .fault)
                assertionFailure()
                return
            }

            for ownedIdentity in ownedIdentities {
                
                let otherOwnedDevices: Set<UID>
                let currentDeviceUid: UID
                do {
                    otherOwnedDevices = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
                    currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
                } catch {
                    os_log("Could not get owned devices or current device uid", log: log, type: .fault)
                    assertionFailure()
                    continue
                }
                
                
                for otherOwnedDevice in otherOwnedDevices {
                    
                    let channelExists: Bool
                    do {
                        channelExists = try channelDelegate.anObliviousChannelExistsBetweenCurrentDeviceUid(currentDeviceUid, andRemoteDeviceUid: otherOwnedDevice, of: ownedIdentity, within: obvContext)
                    } catch {
                        os_log("Could not query de channel manager", log: log, type: .fault)
                        assertionFailure()
                        continue
                    }
                    
                    if channelExists { continue }

                    // If we reach this point, we have no channel with the remote owned device.
                    // We check whether there is a channel creation protocol already handling this situation.
                    
                    let channelCreationToFind = ObliviousChannelIdentifierAlt(ownedCryptoIdentity: ownedIdentity, remoteCryptoIdentity: ownedIdentity, remoteDeviceUid: otherOwnedDevice)
                    if channelCreationProtocols.contains(channelCreationToFind) { continue }

                    // If we reach this point, we can start a channel creation protocol
                    
                    let msg: ObvChannelProtocolMessageToSend
                    do {
                        msg = try protocolDelegate.getInitialMessageForChannelCreationWithOwnedDeviceProtocol(ownedIdentity: ownedIdentity, remoteDeviceUid: otherOwnedDevice)
                    } catch {
                        os_log("Could not get initial message for starting a channel creation with owned device", log: log, type: .fault)
                        assertionFailure()
                        continue
                    }
                    
                    do {
                        _ = try channelDelegate.postChannelMessage(msg, randomizedWith: prng, within: obvContext)
                    } catch {
                        os_log("Could not start channel creation protocol with owned device", log: log, type: .fault)
                        assertionFailure()
                        continue
                    }
                    
                }
                
            }
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not perform startChannelCreationProtocolWithOtherOwnedDevicesHavingNoChannelAndNoOngoingChannelCreationProtocol: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
            
        }
        
    }
    
    
    // This method is not asynchronous since we should not await for it.
    // It is called during bootstrap and when an owned identity is deleted from database
    private func deleteItemsAssociatedToNonExistingOwnedIdentity(flowId: FlowIdentifier) {
        Task {
            do {
                guard let delegateManager else { assertionFailure(); throw ObvError.delegateManagerIsNotSet }
                guard let networkFetchDelegate = delegateManager.networkFetchDelegate else { assertionFailure(); throw ObvError.networkFetchDelegateIsNil }
                guard let protocolDelegate = delegateManager.protocolDelegate else { assertionFailure(); throw ObvError.theProtocolDelegateIsNotSet }
                
                let ownedCryptoIds = try await getOwnedIdentities(restrictToActive: false, flowId: flowId)
                
                Task {
                    do {
                        try await networkFetchDelegate.deleteServerSessionsAssociatedToNonExistingOwnedIdentity(existingOwnedCryptoIds: ownedCryptoIds, flowId: flowId)
                        logger.info("Successfully deleted server sessions associated to non-existing owned identities.")
                    } catch {
                        assertionFailure()
                        logger.fault("Could not delete server sessions associated to non-existing owned identities: \(error.localizedDescription)")
                    }
                }

                Task {
                    do {
                        try await protocolDelegate.deleteAppropriateProtocolInstancesAssociatedToNonExistingOwnedIdentity(existingOwnedCryptoIds: ownedCryptoIds, flowId: flowId)
                        logger.info("Successfully deleted certain protocol instances associated to non existing owned identities")
                    } catch {
                        assertionFailure()
                        logger.fault("Could not delete protocol instances associated to non existing owned identities: \(error.localizedDescription)")
                    }
                }
                
                Task {
                    do {
                        guard let obvEngine else { assertionFailure(); throw ObvError.obvEngineIsNil }
                        guard let obvBackupManagerNew = obvEngine.obvBackupManagerNew else { assertionFailure(); throw ObvError.obvBackupManagerNewIsNil }
                        let existingOwnedCryptoIds = Set(ownedCryptoIds.map({ ObvCryptoId(cryptoIdentity: $0) }))
                        try await obvBackupManagerNew.deleteProfileBackupThreadsAssociatedToNonExistingOwnedIdentity(existingOwnedCryptoIds: existingOwnedCryptoIds, flowId: flowId)
                        logger.info("Successfully deleted backup threads associated to non existing owned identities")
                    } catch {
                        assertionFailure()
                        logger.fault("Could not delete backup threads associated to non existing owned identities: \(error.localizedDescription)")
                    }
                }
                                
            } catch {
                
                logger.fault("Could not delete items associated to non-existing owned identities: \(error.localizedDescription)")

            }
        }
    }
    
    
    private func getOwnedIdentities(restrictToActive: Bool, flowId: FlowIdentifier) async throws -> Set<ObvCryptoIdentity> {
    
        guard let delegateManager else { assertionFailure(); throw ObvError.delegateManagerIsNotSet }
        guard let identityDelegate = delegateManager.identityDelegate else { assertionFailure(); throw ObvError.theIdentityDelegateIsNotSet }
        guard let createContextDelegate = delegateManager.createContextDelegate else { assertionFailure(); throw ObvError.theCreateContextDelegateIsNotSet }
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<ObvCryptoIdentity>, any Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let ownedCryptoIds = try identityDelegate.getOwnedIdentities(restrictToActive: restrictToActive, within: obvContext)
                    return continuation.resume(returning: ownedCryptoIds)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }

        
    }

    /// Check whether each contact has at least one device. If not, perform a device discovery protocol.
    private func startDeviceDiscoveryProtocolForContactsHavingNoDevice(flowId: FlowIdentifier) {

        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }
        guard let protocolDelegate = delegateManager?.protocolDelegate else { assertionFailure(); return }
        guard let channelDelegate = delegateManager?.channelDelegate else { assertionFailure(); return }

        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            guard let ownedIdentities = try? identityDelegate.getOwnedIdentities(restrictToActive: true, within: obvContext) else {
                os_log("Could not get owned identities", log: log, type: .fault)
                assertionFailure()
                return
            }
            
            for ownedIdentity in ownedIdentities {
                
                let contactsWithoutDevice: Set<ObvCryptoIdentity>
                do {
                    contactsWithoutDevice = try identityDelegate.getContactsWithNoDeviceOfOwnedIdentity(ownedIdentity, within: obvContext)
                } catch {
                    os_log("Could not get contacts", log: log, type: .fault)
                    assertionFailure()
                    continue
                }

                for contactWithoutDevice in contactsWithoutDevice {

                    let dateOfLastBootstrappedContactDeviceDiscovery: Date
                    do {
                        dateOfLastBootstrappedContactDeviceDiscovery = try identityDelegate.getDateOfLastBootstrappedContactDeviceDiscovery(forContactCryptoId: contactWithoutDevice, ofOwnedCryptoId: ownedIdentity, within: obvContext)
                    } catch {
                        os_log("Could get date of last boostrapped contact device discovery", log: log, type: .fault)
                        assertionFailure()
                        continue
                    }
                    
                    guard abs(dateOfLastBootstrappedContactDeviceDiscovery.timeIntervalSinceNow) > TimeInterval(days: 3) else {
                        // We do not want to perform a bootstrapped contact discovery to often
                        continue
                    }
                    
                    do {
                        try identityDelegate.setDateOfLastBootstrappedContactDeviceDiscovery(forContactCryptoId: contactWithoutDevice, ofOwnedCryptoId: ownedIdentity, to: Date(), within: obvContext)
                    } catch {
                        os_log("Could not set date of last boostrapped contact device discovery", log: log, type: .fault)
                        assertionFailure()
                        // Continue anyway
                    }
                    
                    let msg: ObvChannelProtocolMessageToSend
                    do {
                        msg = try protocolDelegate.getInitialMessageForContactDeviceDiscoveryProtocol(ownedIdentity: ownedIdentity, contactIdentity: contactWithoutDevice)
                    } catch {
                        os_log("Could get message for device discovery protocol", log: log, type: .fault)
                        assertionFailure()
                        continue
                    }
                    
                    do {
                        _ = try channelDelegate.postChannelMessage(msg, randomizedWith: prng, within: obvContext)
                    } catch {
                        os_log("Could not start device discovery protocol for a contact", log: log, type: .fault)
                        assertionFailure()
                        return
                    }
                                        
                }
                
            }
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not perform startDeviceDiscoveryProtocolForContactsHavingNoDevice: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
        
    }
    
}


// MARK: - Processing engine notifications

extension EngineCoordinator {
    

    /// When the `isCertifiedByOwnKeycloak` changes from `false` to `true`, we want to send a "ping" to her
    private func processContactIsCertifiedByOwnKeycloakStatusChanged(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, newIsCertifiedByOwnKeycloak: Bool) async {
        
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }
        guard let protocolDelegate = delegateManager?.protocolDelegate else { assertionFailure(); return }
        guard let channelDelegate = delegateManager?.channelDelegate else { assertionFailure(); return }

        guard newIsCertifiedByOwnKeycloak else { return }
        
        let contactIdentifier = ObvContactIdentifier(contactCryptoId: ObvCryptoId(cryptoIdentity: contactIdentity), ownedCryptoId: ObvCryptoId(cryptoIdentity: ownedIdentity))
        
        let op1 = SendTargetedPingMessageForKeycloakGroupV2ProtocolWhereContactIsPendingMemberOperation(
            identityDelegate: identityDelegate,
            channelDelegate: channelDelegate,
            protocolDelegate: protocolDelegate,
            prng: prng,
            contactIdentifiers: Set([contactIdentifier]),
            logSubsystem: logSubsystem)
        
        do {
            let composedOp = try createCompositionOfOneContextualOperation(op1: op1)
            try await protocolDelegate.executeOnQueueForProtocolOperations(operation: composedOp)
            os_log("Successful pinged keycloak contact in group where she is pending", log: log, type: .info)
        } catch {
            assertionFailure(error.localizedDescription)
            os_log("Failed to ping keycloak contact in group where she is pending: %{public}@", log: log, type: .fault, error.localizedDescription)
        }

    }

    
    /// When a new remote owned device is inserted, we immediately try to create an oblivious channel between the current device of the owned identity and this other remote owned device, but only if the remote device was *not* inserted during an existing channel creation.
    /// We also perform an owned device discovery.
    /// See also ``ObvEngine.processNewRemoteOwnedDevice(ownedCryptoId:remoteDeviceUid:)`` where we notify the app.
    private func processNewRemoteOwnedDevice(ownedCryptoId: ObvCryptoIdentity, remoteDeviceUid: UID, createdDuringChannelCreation: Bool) async {

        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let protocolDelegate = delegateManager?.protocolDelegate else { assertionFailure(); return }
        guard let channelDelegate = delegateManager?.channelDelegate else { assertionFailure(); return }

        // Perform a channel creation with the new remote owned device, if appropriate
        
        if !createdDuringChannelCreation {
            
            let msg: ObvChannelProtocolMessageToSend
            do {
                msg = try protocolDelegate.getInitialMessageForChannelCreationWithOwnedDeviceProtocol(ownedIdentity: ownedCryptoId, remoteDeviceUid: remoteDeviceUid)
            } catch {
                os_log("Could get initial message for starting channel creation with owned device protocol", log: log, type: .fault)
                assertionFailure()
                return
            }
            
            let flowId = FlowIdentifier()
            let prng = self.prng
            let log = self.log
            
            createContextDelegate.performBackgroundTask(flowId: flowId) { (obvContext) in
                
                do {
                    _ = try channelDelegate.postChannelMessage(msg, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not start channel creation with owned device protocol", log: log, type: .fault)
                    assertionFailure()
                    return
                }
                
                do {
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not perform processNewRemoteOwnedDevice: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                }
                
            }
            
        }
        
        // Perform an owned device discovery
        
        do {
            assert(obvEngine != nil)
            try await obvEngine?.performOwnedDeviceDiscovery(ownedCryptoId: ObvCryptoId(cryptoIdentity: ownedCryptoId))
        } catch {
            assertionFailure(error.localizedDescription) // In production, continue anyway
        }
        
    }
    
    
    /// When a contact becomes trusted, we start a contact device discovery protocol to found out about all her devices.
    /// We also notify the fetch manager in case we previously received messages from that contact, using our current device prekeys: in that case we kept the messages within the inbox, waiting for the (unknown) remote identity
    /// to become a contact (which is exactly what happened).
    private func processContactIdentityIsNowTrusted(contactIdentity: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async {
        
        guard let networkFetchDelegate = delegateManager?.networkFetchDelegate else { assertionFailure(); return }
        
        startDeviceDiscoveryProtocolForContactIdentity(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, flowId: flowId)
        
        do {
            let contactIdentifier = ObvContactIdentifier(contactCryptoIdentity: contactIdentity, ownedCryptoIdentity: ownedIdentity)
            try await networkFetchDelegate.remoteIdentityIsNowAContact(contactIdentifier: contactIdentifier, flowId: flowId)
        } catch {
            assertionFailure()
        }
        
    }

    
    /// When a new contact device is inserted, we immediately try to create an oblivious channel between the current device of the owned identity and this contact device, but only if the contact device was *not* inserted during an existing channel creation.
    /// We also perform an contact device discovery.
    /// See also ``ObvEngine.processNewRemoteOwnedDevice(ownedCryptoId:remoteDeviceUid:)`` where we notify the app.
    private func processNewContactDevice(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, createdDuringChannelCreation: Bool, flowId: FlowIdentifier) {
        
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let protocolDelegate = delegateManager?.protocolDelegate else { assertionFailure(); return }
        guard let channelDelegate = delegateManager?.channelDelegate else { assertionFailure(); return }

        // Perform a channel creation with the new remote owned device, if appropriate
        
        if !createdDuringChannelCreation {
            
            os_log("🛟 [%{public}@] Since the contact has a new device (not added as the result of a channel creation), we start a channel creation now", log: log, type: .info, contactIdentity.debugDescription)

            let msg: ObvChannelProtocolMessageToSend
            do {
                msg = try protocolDelegate.getInitialMessageForChannelCreationWithContactDeviceProtocol(betweenTheCurrentDeviceOfOwnedIdentity: ownedIdentity, andTheDeviceUid: contactDeviceUid, ofTheContactIdentity: contactIdentity)
            } catch {
                os_log("Could get initial message for starting channel creation with contact device protocol", log: log, type: .fault)
                assertionFailure()
                return
            }
            
            let flowId = FlowIdentifier()
            let prng = self.prng
            let log = self.log
            
            createContextDelegate.performBackgroundTask(flowId: flowId) { (obvContext) in
                
                do {
                    _ = try channelDelegate.postChannelMessage(msg, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not start channel creation with contact device protocol", log: log, type: .fault)
                    assertionFailure()
                    return
                }
                
                do {
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not perform channel creation with contact device protocol: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                }
                
            }
            
        }

        // Perform an contact device discovery

        startDeviceDiscoveryProtocolForContactIdentity(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, flowId: flowId)
        
    }

    
    private func startDeviceDiscoveryProtocolForContactIdentity(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }
        guard let protocolDelegate = delegateManager?.protocolDelegate else { assertionFailure(); return }
        guard let channelDelegate = delegateManager?.channelDelegate else { assertionFailure(); return }

        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            guard (try? identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true else {
                os_log("Trying to perform a device discovery of an identity which is not a contact identity", log: log, type: .fault)
                assertionFailure()
                return
            }
            
            guard (try? identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext)) == true else {
                os_log("Trying to perform a device discovery of an inactive contact identity", log: log, type: .fault)
                return
            }
            
            let msg: ObvChannelProtocolMessageToSend
            do {
                msg = try protocolDelegate.getInitialMessageForContactDeviceDiscoveryProtocol(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity)
            } catch {
                os_log("Could get initial message for starting contact device discovery protocol", log: log, type: .fault)
                assertionFailure()
                return
            }
            
            do {
                _ = try channelDelegate.postChannelMessage(msg, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not start contact device discovery protocol", log: log, type: .fault)
                assertionFailure()
                return
            }
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not perform startDeviceDiscoveryProtocolForContactIdentity: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
            
        }
        
    }

    
    private func informTheNetworkFetchManagerOfTheLatestSetOfOwnedIdentities() async throws {
        
        guard let networkFetchDelegate = delegateManager?.networkFetchDelegate else { assertionFailure(); return }
        
        let flowId = FlowIdentifier()
        let activeOwnedCryptoIdsAndCurrentDeviceUIDs = try await getActiveOwnedIdentitiesAndCurrentDeviceUids(flowId: flowId)
        try await networkFetchDelegate.updatedListOfOwnedIdentites(activeOwnedCryptoIdsAndCurrentDeviceUIDs: activeOwnedCryptoIdsAndCurrentDeviceUIDs, flowId: flowId)

    }
    
    
    private func getActiveOwnedIdentitiesAndCurrentDeviceUids(flowId: FlowIdentifier) async throws -> Set<OwnedCryptoIdentityAndCurrentDeviceUID> {
        guard let delegateManager else { assertionFailure(); throw ObvError.delegateManagerIsNotSet }
        guard let identityDelegate = delegateManager.identityDelegate else { assertionFailure(); throw ObvError.theIdentityDelegateIsNotSet }
        guard let createContextDelegate = delegateManager.createContextDelegate else { assertionFailure(); throw ObvError.theCreateContextDelegateIsNotSet }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<OwnedCryptoIdentityAndCurrentDeviceUID>, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let ownedCryptoIds = try identityDelegate.getActiveOwnedIdentitiesAndCurrentDeviceUids(within: obvContext)
                    return continuation.resume(returning: ownedCryptoIds)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
        
        
    }
    
    
    /// When receiving an `OwnedDevicesMessage` on the websocket, we perform an owned device discovery
    private func processOwnedDevicesMessageReceivedViaWebsocket(ownedIdentity: ObvCryptoIdentity) {
        
        startOwnedDeviceDiscoveryProtocol(ownedIdentity)
        
        // Note that the NotificationSend sends a serverRequiresAllActiveOwnedIdentitiesToRegisterToPushNotifications notification,
        // so that we will also re-register to push notifications.
        
    }
    
    
    /// When the fetch manager notifies us that there are no more inbox messages to process (and no more unlisted messages on the server), it notify the identity delegate that old
    /// current device's pre-keys can be deleted.
    private func processServerAndInboxContainNoMoreUnprocessedMessages(ownedIdentity: ObvCryptoIdentity, downloadTimestampFromServer: Date) async {
        
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }
        guard let protocolDelegate = delegateManager?.protocolDelegate else { assertionFailure(); return }

        let op1 = DeleteCurrentDeviceExpiredPreKeysOfOwnedIdentityOperation(ownedCryptoId: ownedIdentity, identityDelegate: identityDelegate, downloadTimestampFromServer: downloadTimestampFromServer)
        do {
            let composedOp = try createCompositionOfOneContextualOperation(op1: op1)
            try await protocolDelegate.executeOnQueueForProtocolOperations(operation: composedOp)
        } catch {
            assertionFailure(error.localizedDescription)
            os_log("Failed to delete current device's expired pre-keys for an owned identity: %{public}@", log: log, type: .fault, error.localizedDescription)
        }
        
    }
    
    
    /// When an application message gets decrypted, we check if it comes from a contact. If it is the case, we make sure that this contact is indicated as "recently online".
    private func processApplicationMessageDecrypted(obvMessageOrObvOwnedMessages: [ObvMessageOrObvOwnedMessage], flowId: FlowIdentifier) async {
        
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }
        guard let protocolDelegate = delegateManager?.protocolDelegate else { assertionFailure(); return }

        // Extract ObvMessages only (discard ObvOwnedMessages)
        
        let obvMessages: [ObvMessage] = obvMessageOrObvOwnedMessages.compactMap { message in
            switch message {
            case .obvMessage(let obvMessage):
                return obvMessage
            case .obvOwnedMessage:
                return nil
            }
        }
        
        for obvMessage in obvMessages {
            let op1 = MarkContactAsRecentlyOnlineOperation(contactIdentifier: obvMessage.fromContactIdentity, identityDelegate: identityDelegate)

            do {
                let composedOp = try createCompositionOfOneContextualOperation(op1: op1)
                try await protocolDelegate.executeOnQueueForProtocolOperations(operation: composedOp)
                os_log("Successful pinged keycloak contacts in group where they are pending", log: log, type: .info)
            } catch {
                assertionFailure(error.localizedDescription)
                os_log("Failed to ping keycloak contacts in group where they are pending: %{public}@", log: log, type: .fault, error.localizedDescription)
            }
        }
        
    }
    
    
    private func deleteObliviousChannelBetweenThisDeviceAndRemoteDevice(ownedIdentity: ObvCryptoIdentity, remoteDeviceUid: UID, remoteIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let channelDelegate = delegateManager?.channelDelegate else { assertionFailure(); return }
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }

        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            // Make sure the owned identity still exists, as this method gets called also when an owned identity was deleted
            
            do {
                guard try identityDelegate.isOwned(ownedIdentity, within: obvContext) else { return }
            } catch {
                os_log("Could not check if the identity is owned. This is typically the case while deleting a owned identity.", log: log, type: .info)
                return
            }
            
            do {
                try channelDelegate.deleteObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andTheRemoteDeviceWithUid: remoteDeviceUid, ofRemoteIdentity: remoteIdentity, within: obvContext)
            } catch {
                os_log("Could not delete an Oblivious channel with a contact device", log: log, type: .fault)
                assertionFailure()
                return
            }
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }

        }

    }
    
    
    /// When a new owned identity is reactivated, we start a device discovery for all her contacts and for all her other owned devices.
    /// We also start a channel creation protocol between the current device and other (contact and owned) devices, if no channel already exists,
    /// and if no such protocol already exists.
    ///
    /// For a new owned identity, this does nothing, since she does not have any contact yet.
    /// But for an owned identity that was restored by means of a backup, there might by several
    /// contacts already. In that case, since the backup does not restore any contact device, we want to refresh those devices.
    private func processOwnedIdentityWasReactivated(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        startOwnedDeviceDiscoveryProtocol(ownedCryptoIdentity)
        startDeviceDiscoveryForAllContactsOfOwnedIdentity(ownedCryptoIdentity)
        startChannelCreationProtocolWithContactDevicesHavingNoChannelAndNoOngoingChannelCreationProtocol(flowId: flowId)
        startChannelCreationProtocolWithOtherOwnedDevicesHavingNoChannelAndNoOngoingChannelCreationProtocol(flowId: flowId)
    }
    
    
    /// When a new identity is created in an active state, we do the exact same things than when an identity is reactivated.
    func processNewActiveOwnedIdentity(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        processOwnedIdentityWasReactivated(ownedCryptoIdentity: ownedCryptoIdentity, flowId: flowId)
    }

    
    private func startDeviceDiscoveryForAllContactsOfOwnedIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity) {
        
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let protocolDelegate = delegateManager?.protocolDelegate else { assertionFailure(); return }
        guard let channelDelegate = delegateManager?.channelDelegate else { assertionFailure(); return }

        let prng = self.prng
        let log = self.log

        createContextDelegate.performBackgroundTask(flowId: FlowIdentifier()) { (obvContext) in

            let contacts: Set<ObvCryptoIdentity>
            do {
                contacts = try identityDelegate.getContactsOfOwnedIdentity(ownedCryptoIdentity, within: obvContext)
            } catch {
                os_log("Could not get contacts of owned identity", log: log, type: .fault)
                assertionFailure()
                return
            }

            for contact in contacts {
                
                let message: ObvChannelProtocolMessageToSend
                do {
                    message = try protocolDelegate.getInitialMessageForContactDeviceDiscoveryProtocol(ownedIdentity: ownedCryptoIdentity, contactIdentity: contact)
                } catch {
                    os_log("Could not get initial message for device discovery for contact identity protocol", log: log, type: .fault)
                    continue
                }
                
                do {
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not post a local protocol message allowing to start a device discovery for a contact", log: log, type: .fault)
                    continue
                }
                
            }
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
            }
            
        }
    }
    
    
    private func startOwnedDeviceDiscoveryProtocol(_ ownedCryptoIdentity: ObvCryptoIdentity) {
        
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let protocolDelegate = delegateManager?.protocolDelegate else { assertionFailure(); return }
        guard let channelDelegate = delegateManager?.channelDelegate else { assertionFailure(); return }
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }

        let prng = self.prng
        let log = self.log

        createContextDelegate.performBackgroundTask(flowId: FlowIdentifier()) { (obvContext) in
            
            do {
                guard try identityDelegate.isOwned(ownedCryptoIdentity, within: obvContext) else {
                    os_log("We do not start an owned discovery protocol for an owned identity that does not exist", log: log, type: .fault)
                    return
                }
            } catch {
                assertionFailure(error.localizedDescription)
                return
            }
            
            let message: ObvChannelProtocolMessageToSend
            do {
                message = try protocolDelegate.getInitiateOwnedDeviceDiscoveryMessage(ownedCryptoIdentity: ownedCryptoIdentity)
            } catch {
                os_log("Could not get initial message for owned device discovery protocol", log: log, type: .fault)
                assertionFailure(error.localizedDescription)
                return
            }
                
            do {
                _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not post a local protocol message allowing to start an owned device discovery", log: log, type: .fault)
                assertionFailure(error.localizedDescription)
                return
            }

            do {
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
            }

        }

    }

        
    private func processNewConfirmedObliviousChannelNotification(currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID) {

        /* When a new confirmed channel is created with a remote crypto identity, we send to her all the information we have about
         * all the groups V2 that we have in common.
         */
        
        sendBatchKeysAboutSharedGroupsV2(currentDeviceUid: currentDeviceUid, remoteCryptoIdentity: remoteCryptoIdentity, remoteDeviceUid: remoteDeviceUid)

        /* When a new confirmed channel is created with a remote crypto identity, we check whether this identity is
         * a pending member or a member in some group V1 that we own. If she is pending, we should invite this remote identy again since
         * the protocol step that was supposed to add her certainly failed. If she is a member, she might not be aware of this in case
         * we are in the middle of a backup restore and there is a discrepancy between the restored list of group members and the list
         * she has on her side. For these reasons, we execute a ReinviteAndUpdateMembers step of the (owned) group management protocol
         */

        reinviteMembersForAllOwnedGroupsWhereContactIsMemberOrPending(currentDeviceUid: currentDeviceUid, remoteCryptoIdentity: remoteCryptoIdentity)
        
        /* When a new confirmed channel is created with a remote crypto identity, we check whether this identity is
         * a group owned of some group we joined. If this is the case, we ask for the latest details about this group. In case, e.g.,
         * where this identy restored a backup, it might be the case that we are not part of the group anymore (in case we were not
         * part of the group at the time of the backup). In that case, the call we make here will result in us being kicked out of the
         * group. This is a good thing since this will allow everybody to be at the same page.
         */
        
        askForTheLatestGroupMembersOfAllTheGroupsWeJoinedAndOwnedByTheRemoteCryptoIdentity(currentDeviceUid: currentDeviceUid, remoteCryptoIdentity: remoteCryptoIdentity)
                        
    }
    
    
    private func sendBatchKeysAboutSharedGroupsV2(currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID) {
        
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let protocolDelegate = delegateManager?.protocolDelegate else { assertionFailure(); return }
        guard let channelDelegate = delegateManager?.channelDelegate else { assertionFailure(); return }

        let prng = self.prng
        let log = self.log

        let flowId = FlowIdentifier()
        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { [weak self] (obvContext) in
            
            guard let _self = self else { return }
            
            guard let ownedCryptoIdentity = try? identityDelegate.getOwnedIdentityOfCurrentDeviceUid(currentDeviceUid, within: obvContext) else {
                os_log("The device uid does not correspond to any owned identity (1)", log: _self.log, type: .fault)
                return
            }
            
            do {
                let message = try protocolDelegate.getInitiateBatchKeysResendMessageForGroupV2Protocol(ownedIdentity: ownedCryptoIdentity,
                                                                                                       remoteIdentity: remoteCryptoIdentity,
                                                                                                       remoteDeviceUID: remoteDeviceUid,
                                                                                                       flowId: flowId)
                _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("We failed to initiate a batch keys resend following a new confirmed channel with a contact: %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
            
        }
        
    }
    
    
    private func askForTheLatestGroupMembersOfAllTheGroupsWeJoinedAndOwnedByTheRemoteCryptoIdentity(currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity) {
    
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let protocolDelegate = delegateManager?.protocolDelegate else { assertionFailure(); return }
        guard let channelDelegate = delegateManager?.channelDelegate else { assertionFailure(); return }

        let prng = self.prng
        let log = self.log

        createContextDelegate.performBackgroundTask(flowId: FlowIdentifier()) { [weak self] (obvContext) in
            
            guard let _self = self else { return }
            
            guard let ownedCryptoIdentity = try? identityDelegate.getOwnedIdentityOfCurrentDeviceUid(currentDeviceUid, within: obvContext) else {
                os_log("The device uid does not correspond to any owned identity (2)", log: _self.log, type: .fault)
                return
            }
            
            guard (try? identityDelegate.isIdentity(remoteCryptoIdentity, aContactIdentityOfTheOwnedIdentity: ownedCryptoIdentity, within: obvContext)) == true else {
                return
            }
            
            guard (try? identityDelegate.isContactIdentityActive(ownedIdentity: ownedCryptoIdentity, contactIdentity: remoteCryptoIdentity, within: obvContext)) == true else {
                os_log("Asking for the latest group members of groups owned by an inactive identity", log: _self.log, type: .fault)
                return
            }
            
            guard let allGroupStructures = try? identityDelegate.getAllGroupStructures(ownedIdentity: ownedCryptoIdentity, within: obvContext) else {
                os_log("Could not get all group structures", log: _self.log, type: .fault)
                return
            }
            
            let allJoinedGroupStructures = allGroupStructures.filter { $0.groupType == .joined }
            let joinedGroupsOwnedByTheRemoteIdentity = allJoinedGroupStructures.filter { $0.groupOwner == remoteCryptoIdentity }
            
            for group in joinedGroupsOwnedByTheRemoteIdentity {
                
                do {
                    let message = try protocolDelegate.getInitiateGroupMembersQueryMessageForGroupManagementProtocol(groupUid: group.groupUid,
                                                                                                                     ownedIdentity: ownedCryptoIdentity,
                                                                                                                     groupOwner: remoteCryptoIdentity,
                                                                                                                     within: obvContext)
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                } catch let error {
                    os_log("Could not ask for the latest group members of a group we joined with the identity whith whom we just created a channel: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    // We continue anyway with the other groups
                }

                
            }

            // We save the context only once (trying to save for each item of the for loop won't work, because this obvContext has completionHandlers, and cannot be save twice for this reason).
            do {
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }

            
        }
        
    }
    
    
    private func reinviteMembersForAllOwnedGroupsWhereContactIsMemberOrPending(currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity) {
        
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let protocolDelegate = delegateManager?.protocolDelegate else { assertionFailure(); return }
        guard let channelDelegate = delegateManager?.channelDelegate else { assertionFailure(); return }
        
        let prng = self.prng
        let log = self.log

        createContextDelegate.performBackgroundTask(flowId: FlowIdentifier()) { [weak self] (obvContext) in
            
            guard let _self = self else { return }
            
            guard let ownedCryptoIdentity = try? identityDelegate.getOwnedIdentityOfCurrentDeviceUid(currentDeviceUid, within: obvContext) else {
                os_log("The device uid does not correspond to any owned identity (3)", log: _self.log, type: .fault)
                return
            }
            
            guard (try? identityDelegate.isIdentity(remoteCryptoIdentity, aContactIdentityOfTheOwnedIdentity: ownedCryptoIdentity, within: obvContext)) == true else {
                return
            }
            
            guard (try? identityDelegate.isContactIdentityActive(ownedIdentity: ownedCryptoIdentity, contactIdentity: remoteCryptoIdentity, within: obvContext)) == true else {
                assertionFailure()
                return
            }
            
            guard let allGroupStructures = try? identityDelegate.getAllGroupStructures(ownedIdentity: ownedCryptoIdentity, within: obvContext) else {
                os_log("Could not get all group structures", log: _self.log, type: .fault)
                return
            }
            
            let allOwnedGroupStructures = allGroupStructures.filter { $0.groupType == .owned }
            let ownedGroupsWhereContactIsPendingOrMember = allOwnedGroupStructures.filter { $0.pendingGroupMembersIdentities.contains(remoteCryptoIdentity) || $0.groupMembers.contains(remoteCryptoIdentity) }
            
            for group in ownedGroupsWhereContactIsPendingOrMember {
                
                do {
                    let message = try protocolDelegate.getTriggerReinviteMessageForGroupManagementProtocol(groupUid: group.groupUid,
                                                                                                           ownedIdentity: ownedCryptoIdentity,
                                                                                                           memberIdentity: remoteCryptoIdentity,
                                                                                                           within: obvContext)
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                } catch let error {
                    os_log("Could not trigger a reinvite and update members of a group owned for a contact with whom we just created a channel: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    // We continue with the other groups
                }
                
            }

            // We save the context only once (trying to save for each item of the for loop won't work, because this obvContext has completionHandlers, and cannot be save twice for this reason).
            do {
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }

            
        }

        
    }
    
    /// Called when an owned identity gets deleted from identity manager database
    /// Almost all the owned identity deletion work is performed in the OwnedIdentityDeletionProtocol (including deleting messages from the Inbox/Outbox).
    /// Here, we simply clean the PersistedEngineDialog database and inform the network fetch manager about the new list of active owned identities (this essentially makes sure the appropriate WebSockets are connected).
    public func anOwnedIdentityWasDeleted(deletedOwnedCryptoId: ObvCryptoIdentity) async {
        let flowId = FlowIdentifier()
        
        deleteItemsAssociatedToNonExistingOwnedIdentity(flowId: flowId)
        
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let appNotificationCenter = self.appNotificationCenter else { return }
        
        let log = self.log
        
        do {
            try await informTheNetworkFetchManagerOfTheLatestSetOfOwnedIdentities()
        } catch {
            os_log("Failed inform the fetch manager about the deleted owned identity: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure() // In production, continue anyway
        }

        createContextDelegate.performBackgroundTask(flowId: FlowIdentifier()) { obvContext in
            
            guard let obvDialogs = try? PersistedEngineDialog.getAll(appNotificationCenter: appNotificationCenter, within: obvContext) else { assertionFailure(); return }
            for obvDialog in obvDialogs {
                guard obvDialog.obvDialog?.ownedCryptoId == ObvCryptoId(cryptoIdentity: deletedOwnedCryptoId) else { continue }
                try? obvDialog.delete()
            }
            try? obvContext.save(logOnFailure: log)

        }

        
    }
        
}


// MARK: - Possible errors

extension EngineCoordinator {
    
    enum ObvError: Error {
        
        case theCreateContextDelegateIsNotSet
        case theChannelDelegateIsNotSet
        case theIdentityDelegateIsNotSet
        case theProtocolDelegateIsNotSet
        case delegateManagerIsNotSet
        case networkFetchDelegateIsNil
        case obvEngineIsNil
        case obvBackupManagerNewIsNil
        
    }

}


// MARK: - Helpers for operations

extension EngineCoordinator {
        
    private func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>, flowId: FlowIdentifier? = nil) throws -> CompositionOfOneContextualOperation<T> {
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); throw ObvError.theCreateContextDelegateIsNotSet  }
        let log = self.log
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: createContextDelegate, queueForComposedOperations: queueForComposedOperations, log: log, flowId: flowId ?? FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: log)
        }
        return composedOp
    }

}

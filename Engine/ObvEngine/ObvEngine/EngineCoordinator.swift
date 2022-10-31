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
import ObvMetaManager
import ObvTypes
import ObvCrypto
import OlvidUtils


// This engine coordinator is *only* used when starting the full engine.
final class EngineCoordinator {
        
    private let log: OSLog
    private let prng: PRNGService
    private weak var appNotificationCenter: NotificationCenter?
    
    init(logSubsystem: String, prng: PRNGService, appNotificationCenter: NotificationCenter) {
        self.log = OSLog(subsystem: logSubsystem, category: "EngineCoordinator")
        self.prng = prng
        self.appNotificationCenter = appNotificationCenter
    }
    
    private let internalQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .default
        queue.name = "EngineCoordinator internal queue"
        return queue
    }()

    private var notificationCenterTokens = [NSObjectProtocol]()
    weak var delegateManager: ObvMetaManager? {
        didSet {
            if delegateManager != nil {
                listenToEngineNotifications()
                bootstrap()
            }
        }
    }
    weak var obvEngine: ObvEngine?
    
    private func listenToEngineNotifications() {
        
        guard let notificationDelegate = self.delegateManager?.notificationDelegate else { assertionFailure(); return }
        
        do {
            let token = ObvChannelNotification.observeNewConfirmedObliviousChannel(within: notificationDelegate) { [weak self] (currentDeviceUid, remoteCryptoIdentity, remoteDeviceUid) in
                self?.processNewConfirmedObliviousChannelNotification(currentDeviceUid: currentDeviceUid, remoteCryptoIdentity: remoteCryptoIdentity, remoteDeviceUid: remoteDeviceUid)
            }
            notificationCenterTokens.append(token)
        }
        
        do {
            let token = ObvIdentityNotificationNew.observeOwnedIdentityWasReactivated(within: notificationDelegate, queue: internalQueue) { [weak self] (cryptoIdentity, _) in
                /*
                 * When a new owned identity is reactivated, we start a device discovery for all her contacts. For a new owned identity, this does nothing,
                 * since she does not have any contact yet. But for an owned identity that was restored by means of a backup, there might by several
                 * contacts already. In that case, since the backup does not restore any contact device, we want to refresh those devices.
                 */
                self?.startDeviceDiscoveryForAllContactsOfOwnedIdentity(cryptoIdentity)
            }
            notificationCenterTokens.append(token)
        }
        
        notificationCenterTokens.append(contentsOf: [
            ObvNetworkFetchNotificationNew.observeServerReportedThatAnotherDeviceIsAlreadyRegistered(within: notificationDelegate, queue: internalQueue) { [weak self] (ownedCryptoIdentity, flowId) in
                self?.deactivateOwnedIdentity(ownedCryptoIdentity: ownedCryptoIdentity, flowId: flowId)
            },
            ObvNetworkFetchNotificationNew.observeServerReportedThatThisDeviceWasSuccessfullyRegistered(within: notificationDelegate, queue: internalQueue) { [weak self] (ownedCryptoIdentity, flowId) in
                self?.reactivateOwnedIdentity(ownedCryptoIdentity: ownedCryptoIdentity, flowId: flowId)
            },
            ObvIdentityNotificationNew.observeDeletedContactDevice(within: notificationDelegate, queue: internalQueue) { [weak self] (ownedIdentity, contactIdentity, contactDeviceUid, flowId) in
                self?.deleteObliviousChannelBetweenThisDeviceAndRemoteDevice(ownedIdentity: ownedIdentity, remoteDeviceUid: contactDeviceUid, remoteIdentity: contactIdentity, flowId: flowId)
            },
            ObvIdentityNotificationNew.observeNewContactDevice(within: notificationDelegate) { [weak self] (ownedIdentity, contactIdentity, _, flowId) in
                self?.startDeviceDiscoveryProtocolForContactIdentity(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, flowId: flowId)
            },
            ObvNetworkFetchNotificationNew.observeNewFreeTrialAPIKeyForOwnedIdentity(within: notificationDelegate) { [weak self] (ownedIdentity, apiKey, flowId) in
                self?.setAPIKeyAndResetServerSession(ownedIdentity: ownedIdentity, apiKey: apiKey, transactionIdentifier: nil, flowId: flowId)
            },
            ObvNetworkFetchNotificationNew.observeAppStoreReceiptVerificationSucceededAndSubscriptionIsValid(within: notificationDelegate) { [weak self] (ownedIdentity, transactionIdentifier, apiKey, flowId) in
                self?.setAPIKeyAndResetServerSession(ownedIdentity: ownedIdentity, apiKey: apiKey, transactionIdentifier: transactionIdentifier, flowId: flowId)
            },
            ObvIdentityNotificationNew.observeNewOwnedIdentityWithinIdentityManager(within: notificationDelegate) { [weak self] _ in
                guard let _self = self else { return }
                guard let obvEngine = _self.obvEngine else { assertionFailure(); return }
                do {
                    try obvEngine.downloadAllUserData()
                } catch {
                    os_log("Could not download all user data after restoring backup: %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                    assertionFailure()
                }
                self?.informTheNetworkFetchManagerOfTheLatestSetOfOwnedIdentities()
            },
        ])

    }
    
}

extension EngineCoordinator {
    
    private func bootstrap() {
        let flowId = FlowIdentifier()
        deleteObsoleteObliviousChannels(flowId: flowId)
        startDeviceDiscoveryProtocolForContactsHavingNoDeviceOrTooManyDevices(flowId: flowId)
        startChannelCreationProtocolWithContactDevicesHavingNoChannelAndNoOngoingChannelCreationProtocol(flowId: flowId)
        pruneObsoletePersistedEngineDialogs(flowId: flowId)
    }
    
    
    private func pruneObsoletePersistedEngineDialogs(flowId: FlowIdentifier) {
        
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let appNotificationCenter = self.appNotificationCenter else { return }
        let log = self.log
        
        createContextDelegate.performBackgroundTask(flowId: flowId) { (obvContext) in

            do {
                let dialogs = try PersistedEngineDialog.getAll(appNotificationCenter: appNotificationCenter, within: obvContext)
                let dialogsToDelete = dialogs.filter({ $0.dialogIsObsolete })
                guard !dialogsToDelete.isEmpty else { return }
                try dialogsToDelete.forEach {
                    try $0.delete()
                }
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not prune obsolete PersistedEngineDialogs: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            
        }
        
    }

    
    /// When we delete a contact device, we normaly catch a notification allowing to delete all associated oblivious channels, but this is not atomic.
    /// This method scans all Olbivious channels an makes sure that there is still an associated device within the identity manager.
    private func deleteObsoleteObliviousChannels(flowId: FlowIdentifier) {
        
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let channelDelegate = delegateManager?.channelDelegate else { assertionFailure(); return }
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }

        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in

            // Get the remote device uids associated to all the oblivious channels we have
            let remoteDeviceUidsAssociatedToAnObliviousChannel: Set<ObliviousChannelIdentifier>
            do {
                remoteDeviceUidsAssociatedToAnObliviousChannel = try channelDelegate.getAllRemoteDeviceUidsAssociatedToAnObliviousChannel(within: obvContext)
            } catch let error {
                os_log("Could not get all remote device uids associated to an oblivious channel: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            
            // Get the remote device uids associated to all the device we have within the identity manager

            let remoteDeviceUidsKnownToTheIdentityManager: Set<ObliviousChannelIdentifier>
            do {
                remoteDeviceUidsKnownToTheIdentityManager = try identityDelegate.getAllRemoteOwnedDevicesUidsAndContactDeviceUids(within: obvContext)
            } catch let error {
                os_log("Could not get all device uids known to the identity manager: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            
            // Get a set of device corresponding to obsolete oblivious channels
            
            let obsoleteObliviousChannels = remoteDeviceUidsAssociatedToAnObliviousChannel.subtracting(remoteDeviceUidsKnownToTheIdentityManager)
            
            // Delete all the obsolete oblivious channels
            
            os_log("[Bootstraping] Number of obsolete oblivious channels to delete: %d", log: log, type: .info, obsoleteObliviousChannels.count)
            
            for obsoleteChannel in obsoleteObliviousChannels {
                do {
                    try channelDelegate.deleteObliviousChannelBetweenCurentDeviceWithUid(currentDeviceUid: obsoleteChannel.currentDeviceUid,
                                                                                         andTheRemoteDeviceWithUid: obsoleteChannel.remoteDeviceUid,
                                                                                         ofRemoteIdentity: obsoleteChannel.remoteCryptoIdentity,
                                                                                         within: obvContext)
                } catch let error {
                    os_log("Could not delete an obsolete oblivious channel: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    // Continue anyway
                }
            }
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
            
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
            
            guard let ownedIdentities = try? identityDelegate.getOwnedIdentities(within: obvContext) else {
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
                        
                        let msg: ObvChannelProtocolMessageToSend
                        do {
                            msg = try protocolDelegate.getInitialMessageForChannelCreationWithContactDeviceProtocol(betweenTheCurrentDeviceOfOwnedIdentity: ownedIdentity, andTheDeviceUid: device, ofTheContactIdentity: contact)
                        } catch {
                            os_log("Could not get initial message for starting a channel creation with contact device", log: log, type: .fault)
                            assertionFailure()
                            continue
                        }
                        
                        do {
                            _ = try channelDelegate.post(msg, randomizedWith: prng, within: obvContext)
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
    
    /// Check whether each contact has one, and only one device. If not, perform a device discovery protocol
    private func startDeviceDiscoveryProtocolForContactsHavingNoDeviceOrTooManyDevices(flowId: FlowIdentifier) {

        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }
        guard let protocolDelegate = delegateManager?.protocolDelegate else { assertionFailure(); return }
        guard let channelDelegate = delegateManager?.channelDelegate else { assertionFailure(); return }

        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            guard let ownedIdentities = try? identityDelegate.getOwnedIdentities(within: obvContext) else {
                os_log("Could not get owned identities", log: log, type: .fault)
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

                    if contactDevices.count == 1 { continue }
                    
                    // If we reach this point, the contact has either no device, or "too many" devices

                    let msg: ObvChannelProtocolMessageToSend
                    do {
                        msg = try protocolDelegate.getInitialMessageForDeviceDiscoveryForContactIdentityProtocol(ownedIdentity: ownedIdentity, contactIdentity: contact)
                    } catch {
                        os_log("Could get message for device discovery protocol", log: log, type: .fault)
                        assertionFailure()
                        continue
                    }
                    
                    do {
                        _ = try channelDelegate.post(msg, randomizedWith: prng, within: obvContext)
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
    
    private func informTheNetworkFetchManagerOfTheLatestSetOfOwnedIdentities() {
        
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }
        guard let networkFetchDelegate = delegateManager?.networkFetchDelegate else { assertionFailure(); return }
        
        let flowId = FlowIdentifier()
        var _ownedIdentities: Set<ObvCryptoIdentity>?
        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { obvContext in
            _ownedIdentities = try? identityDelegate.getOwnedIdentities(within: obvContext)
        }
        guard let ownedIdentities = _ownedIdentities else {
            os_log("Could not get set of all owned identities", log: log, type: .fault)
            assertionFailure()
            return
        }
        networkFetchDelegate.updatedListOfOwnedIdentites(ownedIdentities: ownedIdentities, flowId: flowId)
    }
    
    
    /// This happens when the user requested, and received, a new free trial API Key, or when an AppStore receipt was successfully verified by our server.
    /// In that case, we set this key within the identity manager and reset the network session. We know
    /// that this will trigger the creation of a new session. This, in turn, will lead to a notification containing new API Key elements.
    /// In the case we received the new API key thanks to an AppStore purchase, the transactionIdentifier will be set and we notify in case of success/failure
    private func setAPIKeyAndResetServerSession(ownedIdentity: ObvCryptoIdentity, apiKey: UUID, transactionIdentifier: String?, flowId: FlowIdentifier) {
        
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }
        guard let networkFetchDelegate = delegateManager?.networkFetchDelegate else { assertionFailure(); return }
        guard let appNotificationCenter = self.appNotificationCenter else { return }

        let log = self.log
        
        let ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedIdentity)

        let randomFlowId = FlowIdentifier()
        createContextDelegate.performBackgroundTask(flowId: randomFlowId) { (obvContext) in
            do {
                try identityDelegate.setAPIKey(apiKey, forOwnedIdentity: ownedIdentity, keycloakServerURL: nil, within: obvContext)
                try networkFetchDelegate.resetServerSession(for: ownedIdentity, within: obvContext)
            } catch {
                os_log("Could not set new API Key / reset user's server session: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                if let transactionIdentifier = transactionIdentifier {
                    ObvEngineNotificationNew.appStoreReceiptVerificationFailed(ownedIdentity: ownedCryptoId, transactionIdentifier: transactionIdentifier)
                        .postOnBackgroundQueue(within: appNotificationCenter)
                }
                return
            }
            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not set API Key: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                if let transactionIdentifier = transactionIdentifier {
                    ObvEngineNotificationNew.appStoreReceiptVerificationFailed(ownedIdentity: ownedCryptoId, transactionIdentifier: transactionIdentifier)
                        .postOnBackgroundQueue(within: appNotificationCenter)
                }
                return
            }
            
            if let transactionIdentifier = transactionIdentifier {
                ObvEngineNotificationNew.appStoreReceiptVerificationSucceededAndSubscriptionIsValid(ownedIdentity: ownedCryptoId, transactionIdentifier: transactionIdentifier)
                    .postOnBackgroundQueue(within: appNotificationCenter)
            }
            
        }

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
                msg = try protocolDelegate.getInitialMessageForDeviceDiscoveryForContactIdentityProtocol(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity)
            } catch {
                os_log("Could get initial message for starting contact device discovery protocol", log: log, type: .fault)
                assertionFailure()
                return
            }
            
            do {
                _ = try channelDelegate.post(msg, randomizedWith: prng, within: obvContext)
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
    
    
    private func deleteObliviousChannelBetweenThisDeviceAndRemoteDevice(ownedIdentity: ObvCryptoIdentity, remoteDeviceUid: UID, remoteIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }
        guard let channelDelegate = delegateManager?.channelDelegate else { assertionFailure(); return }
        
        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
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
    
        
    private func deactivateOwnedIdentity(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }

        let log = self.log

        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            do {
                try identityDelegate.deactivateOwnedIdentity(ownedIdentity: ownedCryptoIdentity, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not deactivate owned identity: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            
            os_log("The owned identity %{public}@ was deactivated", log: log, type: .info, ownedCryptoIdentity.debugDescription)
            
        }
        
    }
    
    
    private func reactivateOwnedIdentity(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        guard let identityDelegate = delegateManager?.identityDelegate else { assertionFailure(); return }
        guard let createContextDelegate = delegateManager?.createContextDelegate else { assertionFailure(); return }

        let log = self.log

        createContextDelegate.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            do {
                try identityDelegate.reactivateOwnedIdentity(ownedIdentity: ownedCryptoIdentity, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not reactivate owned identity: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
            
            os_log("The owned identity %{public}@ was reactivated", log: log, type: .info, ownedCryptoIdentity.debugDescription)
            
        }

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
                    message = try protocolDelegate.getInitialMessageForDeviceDiscoveryForContactIdentityProtocol(ownedIdentity: ownedCryptoIdentity, contactIdentity: contact)
                } catch {
                    os_log("Could not get initial message for device discovery for contact identity protocol", log: log, type: .fault)
                    continue
                }
                
                do {
                    _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
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
                os_log("The device uid does not correspond to any owned identity", log: _self.log, type: .fault)
                return
            }
            
            guard (try? identityDelegate.isIdentity(remoteCryptoIdentity, aContactIdentityOfTheOwnedIdentity: ownedCryptoIdentity, within: obvContext)) == true else {
                return
            }
            
            guard (try? identityDelegate.isContactIdentityActive(ownedIdentity: ownedCryptoIdentity, contactIdentity: remoteCryptoIdentity, within: obvContext)) == true else {
                os_log("Asking for the latest group members of groups owned by an inactive identity", log: _self.log, type: .fault)
                return
            }

            do {
                let message = try protocolDelegate.getInitiateBatchKeysResendMessageForGroupV2Protocol(ownedIdentity: ownedCryptoIdentity,
                                                                                                       contactIdentity: remoteCryptoIdentity,
                                                                                                       contactDeviceUID: remoteDeviceUid,
                                                                                                       flowId: flowId)
                _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
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
                os_log("The device uid does not correspond to any owned identity", log: _self.log, type: .fault)
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
                    _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
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
                os_log("The device uid does not correspond to any owned identity", log: _self.log, type: .fault)
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
                    _ = try channelDelegate.post(message, randomizedWith: prng, within: obvContext)
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
    
}

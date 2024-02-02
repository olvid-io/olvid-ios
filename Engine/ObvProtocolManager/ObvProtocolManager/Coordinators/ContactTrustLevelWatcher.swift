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
import ObvCrypto
import ObvEncoder
import ObvTypes
import OlvidUtils


final class ContactTrustLevelWatcher {
    
    weak var delegateManager: ObvProtocolDelegateManager! 

    private let prng: PRNGService
    private let internalQueue = OperationQueue.createSerialQueue(name: "ContactTrustLevelWatcherQueue", qualityOfService: .background)
    private let logCategory = String(describing: ContactTrustLevelWatcher.self)
    private var notificationTokens = [NSObjectProtocol]()

    init(prng: PRNGService) {
        self.prng = prng
    }
    
    deinit {
        notificationTokens.forEach { delegateManager.notificationDelegate?.removeObserver($0) }
    }
    
    func finalizeInitialization() {
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            let log = OSLog(subsystem: ObvProtocolDelegateManager.defaultLogSubsystem, category: "ContactTrustLevelWatcher")
            os_log("The notification delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        notificationTokens.append(contentsOf: [
            ObvIdentityNotificationNew.observeContactIdentityOneToOneStatusChanged(within: notificationDelegate, queue: internalQueue) { [weak self] (ownedIdentity, contactIdentity, flowId) in
                self?.processContactIdentityOneToOneStatusChanged(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, flowId: flowId)
            },
        ])
        
    }
    
    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {
        if forTheFirstTime {
            self.reEvaluateAllProtocolInstanceWaitingForContactUpgradeToOneToOne()
        }
    }
    
    /// This method, launched when finalizing the initialization, goes trough all protocol instances that wait for a contact to be promoted to OneToOne.
    /// This code is only meaningfull in the rare cases where a notification of Trust Level increase has been "missed".
    private func reEvaluateAllProtocolInstanceWaitingForContactUpgradeToOneToOne() {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let contextCreator = self.delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            return
        }
        
        guard let identityDelegate = self.delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }

        guard let channelDelegate = self.delegateManager.channelDelegate else {
            os_log("The channel delegate is not set", log: log, type: .fault)
            return
        }

        self.internalQueue.addOperation {
            let randomFlowId = FlowIdentifier()
            contextCreator.performBackgroundTaskAndWait(flowId: randomFlowId) { [weak self] (obvContext) in
                
                guard let _self = self else { return }
                
                var contextNeedsToBeSaved = false
                
                let protocolInstances: Set<ProtocolInstanceWaitingForContactUpgradeToOneToOne>
                do {
                    protocolInstances = try ProtocolInstanceWaitingForContactUpgradeToOneToOne.getAll(delegateManager: _self.delegateManager, within: obvContext)
                } catch {
                    os_log("Could not query the ProtocolInstanceWaitingForContactUpgradeToOneToOne database", log: log, type: .fault)
                    return
                }
                guard !protocolInstances.isEmpty else {
                    os_log("Did not find any protocol instance to notify of the trust level increase of the contact", log: log, type: .debug)
                    return
                }
                
                for protocolInstance in protocolInstances {
                    
                    do {
                        guard try identityDelegate.isIdentity(protocolInstance.contactCryptoIdentity, aContactIdentityOfTheOwnedIdentity: protocolInstance.ownedCryptoIdentity, within: obvContext) else {
                            continue
                        }
                        
                        guard try identityDelegate.isContactIdentityActive(ownedIdentity: protocolInstance.ownedCryptoIdentity, contactIdentity: protocolInstance.contactCryptoIdentity, within: obvContext) else {
                            continue
                        }
                        
                        guard try identityDelegate.isOneToOneContact(ownedIdentity: protocolInstance.ownedCryptoIdentity, contactIdentity: protocolInstance.contactCryptoIdentity, within: obvContext) else {
                            continue
                        }
                    } catch {
                        os_log("Error when evaluating if we can re-launch a protocol instance waiting for contact upgrade to OneToOne: %{public}@", log: log, type: .fault, error.localizedDescription)
                        assertionFailure()
                        continue
                    }
                                        
                    // If we reach this point, there exists a contact that reached a high enough trust level in order to re-launch a protocol instance.
                    
                    let message = protocolInstance.getGenericProtocolMessageToSendWhenContactReachesTargetTrustLevel()
                    guard let protocolMessageToSend = message.generateObvChannelProtocolMessageToSend(with: _self.prng) else {
                        os_log("Could not generate protocol message to send", log: log, type: .fault)
                        return
                    }

                    do {
                        _ = try channelDelegate.postChannelMessage(protocolMessageToSend, randomizedWith: _self.prng, within: obvContext)
                    } catch {
                        os_log("Could not post message", log: log, type: .fault)
                        return
                    }
                    
                    contextNeedsToBeSaved = true

                }
                
                guard contextNeedsToBeSaved else { return }
                
                do {
                    try obvContext.save(logOnFailure: log)
                } catch {
                    os_log("Could not perform the initial re-launch the protocol instances waiting for a trust level increase of a contact.", log: log, type: .fault)
                    return
                }
                
            }
        }
        
    }
    
    
    private func processContactIdentityOneToOneStatusChanged(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let identityDelegate = self.delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return
        }

        guard let channelDelegate = delegateManager.channelDelegate else {
            os_log("The channel delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in

            do {
                guard try identityDelegate.isOneToOneContact(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext) else {
                    return
                }
            } catch {
                os_log("Could not test whether the contact is a OneToOne contact: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }

            // Query the ProtocolInstanceWaitingForContactUpgradeToOneToOne to see if there is a protocol instance to "wake up"
            let protocolInstances: Set<ProtocolInstanceWaitingForContactUpgradeToOneToOne>
            do {
                protocolInstances = try ProtocolInstanceWaitingForContactUpgradeToOneToOne.getAll(ownedCryptoIdentity: ownedIdentity, contactCryptoIdentity: contactIdentity, delegateManager: delegateManager, within: obvContext)
            } catch {
                os_log("Could not query the ProtocolInstanceWaitingForContactUpgradeToOneToOne database", log: log, type: .fault)
                return
            }
            guard !protocolInstances.isEmpty else {
                os_log("Did not find any protocol instance to notify of the trust level increase of the contact", log: log, type: .debug)
                return
            }
            
            // For each protocol instance, create a ReceivedMessage and post it
            
            for waitingProtocolInstance in protocolInstances {
                
                let message = waitingProtocolInstance.getGenericProtocolMessageToSendWhenContactReachesTargetTrustLevel()
                guard let protocolMessageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else {
                    os_log("Could not generate protocol message to send", log: log, type: .fault)
                    return
                }
                
                do {
                    _ = try channelDelegate.postChannelMessage(protocolMessageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not post message", log: log, type: .fault)
                    return
                }
                
            }
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not process the increase in the contact trust level", log: log, type: .fault)
            }
        }

        
    }
    
}

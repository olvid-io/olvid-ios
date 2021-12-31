/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
    private let internalQueue = DispatchQueue(label: "ContactTrustLevelWatcherQueue")
    private let logCategory = String(describing: ContactTrustLevelWatcher.self)
    private var notificationTokens = [NSObjectProtocol]()
    
    init(prng: PRNGService) {
        self.prng = prng
    }
    
    func finalizeInitialization() {
        self.observeContactTrustLevelWasIncreasedNotifications()
        self.reEvaluateAllProtocolInstanceWaitingForTrustLevelIncrease()
    }
    
    /// This method, launched when finalizing the initialization, goes trough all protocol instances that wait for a trust level increase. It checks whether this level is now sufficient and, if this is the case, send the appropriate message to re-launch the protocol instance. This code is only meaningfull in the rare cases where a notification of Trust Level increase has been "missed".
    private func reEvaluateAllProtocolInstanceWaitingForTrustLevelIncrease() {
        
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

        self.internalQueue.async {
            let randomFlowId = FlowIdentifier()
            contextCreator.performBackgroundTaskAndWait(flowId: randomFlowId) { [weak self] (obvContext) in
                
                guard let _self = self else { return }
                
                var contextNeedsToBeSaved = false
                
                let protocolInstances: Set<ProtocolInstanceWaitingForTrustLevelIncrease>
                do {
                    protocolInstances = try ProtocolInstanceWaitingForTrustLevelIncrease.getAll(delegateManager: _self.delegateManager, within: obvContext)
                } catch {
                    os_log("Could not query the ProtocolInstanceWaitingForTrustLevelIncrease database", log: log, type: .fault)
                    return
                }
                guard !protocolInstances.isEmpty else {
                    os_log("Did not find any protocol instance to notify of the trust level increase of the contact", log: log, type: .debug)
                    return
                }
                
                for protocolInstance in protocolInstances {
                    
                    guard (try? identityDelegate.isIdentity(protocolInstance.contactCryptoIdentity, aContactIdentityOfTheOwnedIdentity: protocolInstance.ownedCryptoIdentity, within: obvContext)) == true else {
                        continue
                    }
                    
                    guard (try? identityDelegate.isContactIdentityActive(ownedIdentity: protocolInstance.ownedCryptoIdentity, contactIdentity: protocolInstance.contactCryptoIdentity, within: obvContext)) == true else {
                        continue
                    }
                    
                    let contactTrustLevel: TrustLevel
                    do {
                        contactTrustLevel = try identityDelegate.getTrustLevel(forContactIdentity: protocolInstance.contactCryptoIdentity,
                                                                                   ofOwnedIdentity: protocolInstance.ownedCryptoIdentity,
                                                                                   within: obvContext)
                    } catch {
                        os_log("Could not get the trust level of a contact", log: log, type: .fault)
                        continue
                    }
                    
                    guard contactTrustLevel >= protocolInstance.targetTrustLevel else {
                        continue
                    }
                    
                    // If we reach this point, there exists a contact that reached a high enough trust level in order to re-launch a protocol instance.
                    
                    let message = protocolInstance.getGenericProtocolMessageToSendWhenContactReachesTargetTrustLevel()
                    guard let protocolMessageToSend = message.generateObvChannelProtocolMessageToSend(with: _self.prng) else {
                        os_log("Could not generate protocol message to send", log: log, type: .fault)
                        return
                    }

                    do {
                        _ = try channelDelegate.post(protocolMessageToSend, randomizedWith: _self.prng, within: obvContext)
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
    
    private func observeContactTrustLevelWasIncreasedNotifications() {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }
        
        let NotificationType = ObvIdentityNotification.ContactTrustLevelWasIncreased.self
        let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
            debugPrint("Within observeContactTrustLevelWasIncreasedNotifications")
            guard let _self = self else { return }
            guard let (ownedIdentity, contactIdentity, trustLevelOfContactIdentity, flowId) = NotificationType.parse(notification) else { return }
            
            guard let contextCreator = _self.delegateManager.contextCreator else {
                os_log("The context creator is not set", log: log, type: .fault)
                return
            }
            
            guard let channelDelegate = _self.delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return
            }
            
            _self.internalQueue.async {
                contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
                    // Query the ProtocolInstanceWaitingForTrustLevelIncrease to see if there is a protocol instance to "wake up"
                    let protocolInstances: Set<ProtocolInstanceWaitingForTrustLevelIncrease>
                    do {
                        protocolInstances = try ProtocolInstanceWaitingForTrustLevelIncrease.get(ownedCryptoIdentity: ownedIdentity, contactCryptoIdentity: contactIdentity, maxTrustLevel: trustLevelOfContactIdentity, delegateManager: _self.delegateManager, within: obvContext)
                    } catch {
                        os_log("Could not query the ProtocolInstanceWaitingForTrustLevelIncrease database", log: log, type: .fault)
                        return
                    }
                    guard !protocolInstances.isEmpty else {
                        os_log("Did not find any protocol instance to notify of the trust level increase of the contact", log: log, type: .debug)
                        return
                    }
                    
                    // For each protocol instance, create a ReceivedMessage and post it
                    
                    for waitingProtocolInstance in protocolInstances {
                        
                        let message = waitingProtocolInstance.getGenericProtocolMessageToSendWhenContactReachesTargetTrustLevel()
                        guard let protocolMessageToSend = message.generateObvChannelProtocolMessageToSend(with: _self.prng) else {
                            os_log("Could not generate protocol message to send", log: log, type: .fault)
                            return
                        }
                        
                        do {
                            _ = try channelDelegate.post(protocolMessageToSend, randomizedWith: _self.prng, within: obvContext)
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
        notificationTokens.append(token)
    }
    
}

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
import ObvTypes
import ObvMetaManager
import ObvCrypto
import OlvidUtils


// MARK: - Protocol Steps

extension ObliviousChannelManagementProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        case DeleteContact = 0
        case ProcessContactDeletionNotification = 1
        case ProcessPropagatedContactDeletion = 2
        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            
            switch self {
                
            case .DeleteContact:
                let step = DeleteContactStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ProcessContactDeletionNotification:
                let step = ProcessContactDeletionNotificationStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ProcessPropagatedContactDeletion:
                let step = ProcessPropagatedContactDeletionStep(from: concreteProtocol, and: receivedMessage)
                return step
            }
        }
    }
    
    
    // MARK: - DeleteContactStep
    
    final class DeleteContactStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateContactDeletionMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: ObliviousChannelManagementProtocol.InitiateContactDeletionMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: IdentityDetailsPublicationProtocol.logCategory)
            os_log("ObliviousChannelManagementProtocol: starting DeleteContactStep", log: log, type: .debug)
            defer { os_log("ObliviousChannelManagementProtocol: ending DeleteContactStep", log: log, type: .debug) }

            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            let contactIdentity = receivedMessage.contactIdentity
            
            // Propagate to other devices
            
            guard let numberOfOtherDevicesOfOwnedIdentity = try? identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count else {
                os_log("Could not determine whether the owned identity has other (remote) devices", log: log, type: .fault)
                return CancelledState()
            }
            
            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                let concreteProtocolMessage = PropagateContactDeletionMessage(coreProtocolMessage: coreMessage, contactIdentity: contactIdentity)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    return CancelledState()
                }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Notify contact (we need the oblivious channel --> before deleting the contact). Do so only if we still have a confirmed oblivious channel with this contact.
            
            let confirmedObliviousChannelExistsWithContact: Bool
            do {
                confirmedObliviousChannelExistsWithContact = try channelDelegate.aConfirmedObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity,
                                                                                                                                           andRemoteIdentity: contactIdentity,
                                                                                                                                           within: obvContext)
            } catch {
                os_log("Could not determine if we still have a confirmed oblivious channel with the contact", log: log, type: .error)
                return CancelledState()
            }

            
            if confirmedObliviousChannelExistsWithContact {
                let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set([contactIdentity]), fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = ContactDeletionNotificationMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    return CancelledState()
                }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Delete all channels
            
            do {
                try channelDelegate.deleteAllObliviousChannelsBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andTheDevicesOfContactIdentity: contactIdentity, within: obvContext)
            } catch {
                os_log("Could not delete the oblivious channels we have with the remove devices of our contact to delete", log: log, type: .error)
                return CancelledState()
            }
            
            // Remove contact from all owned groups where it is pending
            
            let allOwnedGroupStructuresWhereContactIsPending: Set<GroupStructure>
            do {
                let allGroupStructures = try identityDelegate.getAllGroupStructures(ownedIdentity: ownedIdentity, within: obvContext)
                let allOwnedGroupStructures = allGroupStructures.filter { $0.groupType == .owned }
                allOwnedGroupStructuresWhereContactIsPending = allOwnedGroupStructures.filter {
                    let cryptoIdentityOfPendingMembers = $0.pendingGroupMembers.map { $0.cryptoIdentity }
                    return cryptoIdentityOfPendingMembers.contains(contactIdentity)
                }
            } catch {
                os_log("Could not get all group structures", log: log, type: .fault)
                return CancelledState()
            }
            
            for groupStructure in allOwnedGroupStructuresWhereContactIsPending {
                
                let groupInformationWithPhoto: GroupInformationWithPhoto
                do {
                    groupInformationWithPhoto = try identityDelegate.getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: ownedIdentity,
                                                                                     groupUid: groupStructure.groupUid,
                                                                                     within: obvContext)
                } catch {
                    os_log("Could not get owned group information", log: log, type: .fault)
                    return CancelledState()
                }
                
                let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                                      cryptoProtocolId: .GroupManagement,
                                                      protocolInstanceUid: groupInformationWithPhoto.associatedProtocolUid)
                let concreteProtocolMessage = GroupManagementProtocol.RemoveGroupMembersMessage(coreProtocolMessage: coreMessage,
                                                                                                groupInformation: groupInformationWithPhoto.groupInformation,
                                                                                                removedGroupMembers: Set([contactIdentity]))
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    return CancelledState()
                }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                
            }
            
            // Delete contact (if there are no groups)
            
            try identityDelegate.deleteContactIdentity(contactIdentity, forOwnedIdentity: ownedIdentity, failIfContactIsPartOfAGroupJoined: true, within: obvContext)
            
            return FinalState()
        }
        
    }


    // MARK: - ProcessContactDeletionNotificationStep
    
    final class ProcessContactDeletionNotificationStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: ConcreteProtocolInitialState
        let receivedMessage: ContactDeletionNotificationMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: ObliviousChannelManagementProtocol.ContactDeletionNotificationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: IdentityDetailsPublicationProtocol.logCategory)
            os_log("ObliviousChannelManagementProtocol: starting ProcessContactDeletionNotificationStep", log: log, type: .debug)
            defer { os_log("ObliviousChannelManagementProtocol: ending ProcessContactDeletionNotificationStep", log: log, type: .debug) }

            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                return CancelledState()
            }
            
            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            // Determine the origin of the message
            
            guard let contactIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determine the remote identity (ProcessNewMembersStep)", log: log, type: .error)
                return CancelledState()
            }
            
            // Leave any group where the contact is a group owner. Instead of doing so by sending a LeaveGroupJoinedMessage in order to start the appropriate protocol step, we make a direct call to the identity delegate. This ensures that we can indeed delete the contact later in this step.

            do {
                
                let allGroupStructures = try identityDelegate.getAllGroupStructures(ownedIdentity: ownedIdentity, within: obvContext)
                let groupStructuresOwnedByContactToDelete = allGroupStructures.filter { $0.groupOwner == contactIdentity }

                for groupStructure in groupStructuresOwnedByContactToDelete {
                    
                    let groupInformationWithPhoto: GroupInformationWithPhoto
                    do {
                        groupInformationWithPhoto = try identityDelegate.getGroupJoinedInformationAndPublishedPhoto(ownedIdentity: ownedIdentity,
                                                                                          groupUid: groupStructure.groupUid,
                                                                                          groupOwner: contactIdentity,
                                                                                          within: obvContext)
                    } catch let error {
                        os_log("Could not get owned group information", log: log, type: .fault)
                        throw error
                    }
                    
                    assert(groupInformationWithPhoto.groupOwnerIdentity == contactIdentity)
                    
                    do {
                        try identityDelegate.leaveContactGroupJoined(ownedIdentity: ownedIdentity, groupUid: groupInformationWithPhoto.groupUid, groupOwner: groupInformationWithPhoto.groupOwnerIdentity, within: obvContext)
                    } catch let error {
                        os_log("The call to leaveContactGroupJoined of the identity manager failed", log: log, type: .error)
                        throw error
                    }

                }
                
            } catch {
                os_log("We could not deal with the groups owned by the user we are deleating. Proceeding anyway", log: log, type: .error)
            }
                        
            // Delete all channels
            
            do {
                try channelDelegate.deleteAllObliviousChannelsBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andTheDevicesOfContactIdentity: contactIdentity, within: obvContext)
            } catch {
                os_log("Could not delete the oblivious channels we have with the remove devices of our contact to delete", log: log, type: .error)
                return CancelledState()
            }

            // Delete contact, fails if there are still some groups, but catch Exception to still delete channels (destroyed on sender side).
            
            do {
                
                try identityDelegate.deleteContactIdentity(contactIdentity, forOwnedIdentity: ownedIdentity, failIfContactIsPartOfAGroupJoined: true, within: obvContext)
                
                // If the contact was indeed deleted (no exception thrown) remove contact from all owned groups where it is pending
                
                let allOwnedGroupStructuresWhereContactIsPending: Set<GroupStructure>
                do {
                    let allGroupStructures = try identityDelegate.getAllGroupStructures(ownedIdentity: ownedIdentity, within: obvContext)
                    let allOwnedGroupStructures = allGroupStructures.filter { $0.groupType == .owned }
                    allOwnedGroupStructuresWhereContactIsPending = allOwnedGroupStructures.filter {
                        let cryptoIdentityOfPendingMembers = $0.pendingGroupMembers.map { $0.cryptoIdentity }
                        return cryptoIdentityOfPendingMembers.contains(contactIdentity)
                    }
                } catch {
                    os_log("Could not get all group structures", log: log, type: .fault)
                    return CancelledState()
                }
                
                for groupStructure in allOwnedGroupStructuresWhereContactIsPending {
                    
                    let groupInformationWithPhoto: GroupInformationWithPhoto
                    do {
                        groupInformationWithPhoto = try identityDelegate.getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: ownedIdentity,
                                                                                         groupUid: groupStructure.groupUid,
                                                                                         within: obvContext)
                    } catch {
                        os_log("Could not get owned group information", log: log, type: .fault)
                        return CancelledState()
                    }
                    
                    let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                                          cryptoProtocolId: .GroupManagement,
                                                          protocolInstanceUid: groupInformationWithPhoto.associatedProtocolUid)
                    let concreteProtocolMessage = GroupManagementProtocol.RemoveGroupMembersMessage(coreProtocolMessage: coreMessage,
                                                                                                    groupInformation: groupInformationWithPhoto.groupInformation,
                                                                                                    removedGroupMembers: Set([contactIdentity]))
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        return CancelledState()
                    }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                    
                }
                
            } catch {
                // We failed to delete the contact but we do not propagate this error since we still want to delete all channels
            }
            
            return FinalState()

        }
        
    }

    
    // MARK: - ProcessPropagatedContactDeletionStep
    
    final class ProcessPropagatedContactDeletionStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PropagateContactDeletionMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: ObliviousChannelManagementProtocol.PropagateContactDeletionMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: IdentityDetailsPublicationProtocol.logCategory)
            os_log("ObliviousChannelManagementProtocol: starting ProcessContactDeletionNotificationStep", log: log, type: .debug)
            defer { os_log("ObliviousChannelManagementProtocol: ending ProcessContactDeletionNotificationStep", log: log, type: .debug) }
            
            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                return CancelledState()
            }
            
            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return CancelledState()
            }
            
            let contactIdentity = receivedMessage.contactIdentity
            
            // Delete all channels
            
            do {
                try channelDelegate.deleteAllObliviousChannelsBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andTheDevicesOfContactIdentity: contactIdentity, within: obvContext)
            } catch {
                os_log("Could not delete the oblivious channels we have with the remove devices of our contact to delete", log: log, type: .error)
                return CancelledState()
            }
            
            // We do not do anything about own group pending members: the GroupManagementProtocol will propagate the information itself
            
            // Delete the contact (even if still in some groups, this is only temporary)
            
            try identityDelegate.deleteContactIdentity(contactIdentity, forOwnedIdentity: ownedIdentity, failIfContactIsPartOfAGroupJoined: false, within: obvContext)
            
            return FinalState()
            
        }
        
    }

}
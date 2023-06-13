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
import OlvidUtils
import ObvCrypto
import ObvTypes
import ObvMetaManager


/// This delegate serves two purposes. It exposes an API allowing the manager to start a protocol and it reacts to various notifications in order to start the appropriate protocols automatically.
final class ProtocolStarterCoordinator: ProtocolStarterDelegate {
    
    // MARK: Instance variables
    
    fileprivate static let logCategory = "ProtocolStarterCoordinator"
    
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { ProtocolStarterCoordinator.makeError(message: message) }

    // Thanks to the manager initializer, we know that this delegate won't be `nil`. So we force unwrap.
    weak var delegateManager: ObvProtocolDelegateManager!
    
    let prng: PRNGService
    
    private var notificationCenterTokens = [NSObjectProtocol]()
    
    private static let errorDomain = "ProtocolStarterCoordinator"
    
    // MARK: - Initializer and deinitializer
    
    init(prng: PRNGService) {
        self.prng = prng
    }
    
    deinit {
        notificationCenterTokens.forEach { delegateManager?.notificationDelegate?.removeObserver($0) }
    }

    
    // MARK: - Observer notifications
    
    func tryToObserveIdentityNotifications() {
        if let delegateManager = delegateManager,
            delegateManager.contextCreator != nil,
            let notificationDelegate = delegateManager.notificationDelegate,
            delegateManager.identityDelegate != nil,
            delegateManager.channelDelegate != nil,
            delegateManager.solveChallengeDelegate != nil {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
            
            // Listening to `NewContactDevice` notifications
            notificationCenterTokens.append(ObvIdentityNotificationNew.observeNewContactDevice(within: notificationDelegate) { [weak self] (ownedIdentity, contactIdentity, contactDeviceUid, flowId) in
                os_log("We received a New Contact Device notification", log: log, type: .debug)
                do {
                    try self?.processNewContactDeviceNotification(ownedIdentity: ownedIdentity,
                                                                  contactIdentity: contactIdentity,
                                                                  contactDeviceUid: contactDeviceUid,
                                                                  within: flowId)
                } catch {
                    os_log("Could not process a New Contact Device notification", log: log, type: .fault)
                }
            })
            
            do {
                let token = ObvIdentityNotificationNew.observeContactIdentityIsNowTrusted(within: notificationDelegate) { [weak self] (contactIdentity, ownedIdentity, flowId) in
                    do {
                        try self?.startDeviceDiscoveryProtocolOfContactIdentity(contactIdentity, forOwnedIdentity: ownedIdentity, within: flowId)
                    } catch {
                        os_log("Could not process a ContactIdentityIsNowTrusted notification", log: log, type: .fault)
                    }
                }
                notificationCenterTokens.append(token)
            }
            
        }
    }
    
    // MARK: - Process notifications
    
    private func processNewContactDeviceNotification(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, within flowId: FlowIdentifier) throws {

        try startChannelCreationWithContactDeviceProtocolBetweenTheCurrentDeviceOf(ownedIdentity,
                                                                                   andTheDeviceUid: contactDeviceUid,
                                                                                   ofTheContactIdentity: contactIdentity,
                                                                                   within: flowId)
        
    }
    
}


// MARK: - Implementing ProtocolStarterDelegate
extension ProtocolStarterCoordinator {
    
    func startDeviceDiscoveryProtocolOfContactIdentity(_ contactIdentity: ObvCryptoIdentity, forOwnedIdentity ownedIdentity: ObvCryptoIdentity, within flowId: FlowIdentifier) throws {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            assertionFailure()
            os_log("The context creator is not set", log: log, type: .fault)
            throw Self.makeError(message: "The context creator is not set")
        }
        
        guard let channelDelegate = delegateManager.channelDelegate else {
            assertionFailure()
            os_log("The channel delegate is not set", log: log, type: .fault)
            throw Self.makeError(message: "The channel delegate is not set")
        }
        
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .DeviceDiscoveryForContactIdentity,
                                              protocolInstanceUid: protocolInstanceUid)
        guard let messageToSend = DeviceDiscoveryForContactIdentityProtocol.InitialMessage(coreProtocolMessage: coreMessage, contactIdentity: contactIdentity).generateObvChannelProtocolMessageToSend(with: prng) else {
            assertionFailure()
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw Self.makeError(message: "Could create generic protocol message to send")
        }

        let prng = self.prng
        
        var error: Error? = nil
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            // Create the initial message to send to this new protocol instance and "send" it
            do {
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }
        
    }
    
    
    func getInitialMessageForTrustEstablishmentProtocol(of contactIdentity: ObvCryptoIdentity, withFullDisplayName contactFullDisplayName: String, forOwnedIdentity ownedIdentity: ObvCryptoIdentity, withOwnedIdentityCoreDetails ownIdentityCoreDetails: ObvIdentityCoreDetails, usingProtocolInstanceUid protocolInstanceUid: UID) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        // Start the updated version of the TrustEstablishmentProtocol
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .TrustEstablishmentWithSAS,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = TrustEstablishmentWithSASProtocol.InitialMessage(coreProtocolMessage: coreMessage,
                                                                              contactIdentity: contactIdentity,
                                                                              contactIdentityFullDisplayName: contactFullDisplayName,
                                                                              ownIdentityCoreDetails: ownIdentityCoreDetails)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            assertionFailure()
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
        }
        return initialMessageToSend
        
    }


    func getInitialMessageForContactMutualIntroductionProtocol(of identity1: ObvCryptoIdentity, withIdentityCoreDetails details1: ObvIdentityCoreDetails, with identity2: ObvCryptoIdentity, withOtherIdentityCoreDetails details2: ObvIdentityCoreDetails, byOwnedIdentity ownedIdentity: ObvCryptoIdentity, usingProtocolInstanceUid protocolInstanceUid: UID) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .ContactMutualIntroduction,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = ContactMutualIntroductionProtocol.InitialMessage(coreProtocolMessage: coreMessage,
                                                                              contactIdentityA: identity1,
                                                                              contactIdentityCoreDetailsA: details1,
                                                                              contactIdentityB: identity2,
                                                                              contactIdentityCoreDetailsB: details2)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            assertionFailure()
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
        }
        return initialMessageToSend

    }

    
    func startChannelCreationWithContactDeviceProtocolBetweenTheCurrentDeviceOf(_ ownedIdentity: ObvCryptoIdentity, andTheDeviceUid contactDeviceUid: UID, ofTheContactIdentity contactIdentity: ObvCryptoIdentity, within flowId: FlowIdentifier) throws {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)

        os_log("Call to startChannelCreationWithContactDeviceProtocolBetweenTheCurrentDeviceOf", log: log, type: .debug)
        
        guard let contextCreator = delegateManager.contextCreator else {
            assertionFailure()
            os_log("The context creator is not set", log: log, type: .fault)
            throw Self.makeError(message: "The context creator is not set")
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            assertionFailure()
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw Self.makeError(message: "The identity delegate is not set")
        }

        guard let channelDelegate = delegateManager.channelDelegate else {
            assertionFailure()
            os_log("The channel delegate is not set", log: log, type: .fault)
            throw Self.makeError(message: "The channel delegate is not set")
        }

        var error: Error? = nil
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            // We only start a channel creation if the contact is trusted by the owned identity (i.e. is part of the ContactIdentity database for the owned identity), if the contactDeviceUid indeed correspond to a device of the contact, and if a confirmed channel does not already exist
            
            guard (try? identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true else {
                os_log("The contact is not trusted yet, we do not trigger an Oblivious Channel Creation", log: log, type: .error)
                return
            }
            
            guard (try? identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext)) == true else {
                os_log("The contact is inactive, we do not trigger an Oblivious Channel Creation", log: log, type: .error)
                return
            }
            
            do {
                let contactDeviceUids = try identityDelegate.getDeviceUidsOfContactIdentity(contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
                guard contactDeviceUids.contains(contactDeviceUid) else {
                    os_log("The device uid is not part the contact's device uids", log: log, type: .error)
                    return
                }
                
                guard try channelDelegate.aConfirmedObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andRemoteIdentity: contactIdentity, withRemoteDeviceUid: contactDeviceUid, within: obvContext) == false else {
                    os_log("A confirmed Oblivious Channel already exist, we do not trigger an Oblivious Channel Creation", log: log, type: .debug)
                    return
                }
                
                // Start a Create the initial message to send to this new protocol instance and "send" it
                
                let initialMessageToSend = try getInitialMessageForChannelCreationWithContactDeviceProtocol(betweenTheCurrentDeviceOfOwnedIdentity: ownedIdentity, andTheDeviceUid: contactDeviceUid, ofTheContactIdentity: contactIdentity)
                _ = try channelDelegate.post(initialMessageToSend, randomizedWith: prng, within: obvContext)
                
                try obvContext.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else {
            throw error!
        }
        
    }
    
    
    func getInitialMessageForChannelCreationWithContactDeviceProtocol(betweenTheCurrentDeviceOfOwnedIdentity ownedIdentity: ObvCryptoIdentity, andTheDeviceUid contactDeviceUid: UID, ofTheContactIdentity contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .ChannelCreationWithContactDevice,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = ChannelCreationWithContactDeviceProtocol.InitialMessage(coreProtocolMessage: coreMessage, contactIdentity: contactIdentity, contactDeviceUid: contactDeviceUid)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            assertionFailure()
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
        }
        return initialMessageToSend
    }
    
    
    func getOwnedGroupMembersChangedTriggerMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            assertionFailure()
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw Self.makeError(message: "The identity delegate is not set")
        }
        
        let groupInformationWithPhoto = try identityDelegate.getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: ownedIdentity,
                                                                                                       groupUid: groupUid,
                                                                                                       within: obvContext)
        
        let protocolInstanceUid = groupInformationWithPhoto.associatedProtocolUid
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .GroupManagement,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = GroupManagementProtocol.GroupMembersChangedTriggerMessage(coreProtocolMessage: coreMessage,
                                                                                       groupInformation: groupInformationWithPhoto.groupInformation)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            assertionFailure()
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
        }
        return initialMessageToSend
        
    }
    

    
    func getInitiateGroupCreationMessageForGroupManagementProtocol(groupCoreDetails: ObvGroupCoreDetails, photoURL: URL?, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, ownedIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else { throw makeError(message: "The context creator is not set") }
        guard let identityDelegate = delegateManager.identityDelegate else { throw makeError(message: "The identity delegate is not set") }

        let randomFlowId = FlowIdentifier()
        try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: randomFlowId) { (obvContext) in
            for member in pendingGroupMembers {
                guard try identityDelegate.isIdentity(member.cryptoIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext) else {
                    os_log("The identity %@ is not a contact of the owned identity", log: log, type: .error, member.coreDetails.getFullDisplayName())
                    throw makeError(message: "Trying to create a group that includes an identity that is not a contact of the owned identity")
                }
                guard try identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: member.cryptoIdentity, within: obvContext) else {
                    os_log("The identity %@ is not active", log: log, type: .error, member.coreDetails.getFullDisplayName())
                    throw makeError(message: "Trying to create a group that includes an identity that is not active")
                }
            }
        }

        let groupDetailsElements = GroupDetailsElements(version: 0, coreDetails: groupCoreDetails, photoServerKeyAndLabel: nil)
        let groupUid = UID.gen(with: prng)
        let groupInformationWithPhoto = try GroupInformationWithPhoto(groupOwnerIdentity: ownedIdentity, groupUid: groupUid, groupDetailsElements: groupDetailsElements, photoURL: photoURL)
        
        let protocolInstanceUid = groupInformationWithPhoto.associatedProtocolUid
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .GroupManagement,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = GroupManagementProtocol.InitiateGroupCreationMessage(coreProtocolMessage: coreMessage,
                                                                                  groupInformationWithPhoto: groupInformationWithPhoto,
                                                                                  pendingGroupMembers: pendingGroupMembers)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
    }
    
    
    func getAddGroupMembersMessageForAddingMembersToContactGroupOwnedUsingGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, newGroupMembers: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)

        guard let identityDelegate = delegateManager.identityDelegate else {
            assertionFailure()
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw Self.makeError(message: "The identity delegate is not set")
        }

        guard let groupStructure = try identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, within: obvContext) else {
            throw Self.makeError(message: "Could not get group owned structure")
        }

        guard groupStructure.groupType == .owned else {
            throw Self.makeError(message: "The group type is not owned")
        }

        let groupInformationWithPhoto = try identityDelegate.getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: ownedIdentity, groupUid: groupUid, within: obvContext)

        let protocolInstanceUid = groupInformationWithPhoto.associatedProtocolUid
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .GroupManagement,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = GroupManagementProtocol.AddGroupMembersMessage(coreProtocolMessage: coreMessage,
                                                                            groupInformation: groupInformationWithPhoto.groupInformation,
                                                                            newGroupMembers: newGroupMembers)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            assertionFailure()
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw Self.makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
        
    }
    
    
    func getRemoveGroupMembersMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, removedGroupMembers: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)

        let initialMessage = try getRemoveGroupMembersMessageForStartingGroupManagementProtocol(
            groupUid: groupUid,
            ownedIdentity: ownedIdentity,
            removedGroupMembers: removedGroupMembers,
            simulateReceivedMessage: false,
            within: obvContext)
        
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw Self.makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend

    }
    
    
    func getRemoveGroupMembersMessageForStartingGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, removedGroupMembers: Set<ObvCryptoIdentity>, simulateReceivedMessage: Bool, within obvContext: ObvContext) throws -> GroupManagementProtocol.RemoveGroupMembersMessage {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw Self.makeError(message: "The identity delegate is not set")
        }
        
        guard let groupStructure = try identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, within: obvContext) else {
            throw Self.makeError(message: "Could not get group owned structure")
        }
        
        guard groupStructure.groupType == .owned else {
            throw Self.makeError(message: "The group type is not '.owned'")
        }
        
        let groupInformationWithPhoto = try identityDelegate.getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: ownedIdentity, groupUid: groupUid, within: obvContext)
        
        let protocolInstanceUid = groupInformationWithPhoto.associatedProtocolUid
        let coreMessage: CoreProtocolMessage
        if simulateReceivedMessage {
            coreMessage = CoreProtocolMessage.getLocalCoreProtocolMessageForSimulatingReceivedMessage(
                ownedIdentity: ownedIdentity,
                cryptoProtocolId: .GroupManagement,
                protocolInstanceUid: protocolInstanceUid)
        } else {
            coreMessage = CoreProtocolMessage(
                channelType: .Local(ownedIdentity: ownedIdentity),
                cryptoProtocolId: .GroupManagement,
                protocolInstanceUid: protocolInstanceUid)
        }
        let initialMessage = GroupManagementProtocol.RemoveGroupMembersMessage(coreProtocolMessage: coreMessage,
                                                                               groupInformation: groupInformationWithPhoto.groupInformation,
                                                                               removedGroupMembers: removedGroupMembers)

        return initialMessage
        
    }
    
    
    func getInitialMessageForIdentityDetailsPublicationProtocol(ownedIdentity: ObvCryptoIdentity, publishedIdentityDetailsVersion: Int) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .IdentityDetailsPublication,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = IdentityDetailsPublicationProtocol.InitialMessage(coreProtocolMessage: coreMessage, version: publishedIdentityDetailsVersion)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send for starting an IdentityDetailsPublicationProtocol")
        }
        return initialMessageToSend

    }
    

    func getLeaveGroupJoinedMessageForGroupManagementProtocol(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)

        let initialMessage = try getLeaveGroupJoinedMessageForStartingGroupManagementProtocol(ownedIdentity: ownedIdentity, groupUid: groupUid, groupOwner: groupOwner, simulateReceivedMessage: false, within: obvContext)

        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw Self.makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend

    }
    
    
    /// Returns a `LeaveGroupJoinedMessage` instance suitable to start the `GroupManagement` step allowing to leave a joined group v1.
    ///
    /// The `simulateReceivedMessage` shall generally be set to `false`, except when using the message to manually executing the `GroupManagement` step,  like we do in the `OwnedIdentityDeletion` protocol.
    func getLeaveGroupJoinedMessageForStartingGroupManagementProtocol(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, simulateReceivedMessage: Bool, within obvContext: ObvContext) throws -> GroupManagementProtocol.LeaveGroupJoinedMessage {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw Self.makeError(message: "The identity delegate is not set")
        }
        
        guard let groupStructure = try identityDelegate.getGroupJoinedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, groupOwner: groupOwner, within: obvContext) else {
            throw Self.makeError(message: "Could not find group structure")
        }
        
        guard groupStructure.groupType == .joined else {
            throw Self.makeError(message: "The group type is not 'joined'")
        }
        
        let groupInformationWithPhoto = try identityDelegate.getGroupJoinedInformationAndPublishedPhoto(ownedIdentity: ownedIdentity, groupUid: groupUid, groupOwner: groupOwner, within: obvContext)
        
        let protocolInstanceUid = groupInformationWithPhoto.associatedProtocolUid
        let coreMessage: CoreProtocolMessage
        if simulateReceivedMessage {
            coreMessage = CoreProtocolMessage.getLocalCoreProtocolMessageForSimulatingReceivedMessage(
                ownedIdentity: ownedIdentity,
                cryptoProtocolId: .GroupManagement,
                protocolInstanceUid: protocolInstanceUid)
        } else {
            coreMessage = CoreProtocolMessage(
                channelType: .Local(ownedIdentity: ownedIdentity),
                cryptoProtocolId: .GroupManagement,
                protocolInstanceUid: protocolInstanceUid)
        }
        let initialMessage = GroupManagementProtocol.LeaveGroupJoinedMessage(coreProtocolMessage: coreMessage,
                                                                             groupInformation: groupInformationWithPhoto.groupInformation)
        
        return initialMessage

    }
    
    
    func getInitiateContactDeletionMessageForContactManagementProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentityToDelete: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .ContactManagement,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = ContactManagementProtocol.InitiateContactDeletionMessage(coreProtocolMessage: coreMessage, contactIdentity: contactIdentityToDelete)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw Self.makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend

    }

    func getInitiateAddKeycloakContactMessageForKeycloakContactAdditionProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentityToAdd: ObvCryptoIdentity, signedContactDetails: String) throws -> ObvChannelProtocolMessageToSend {

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)

        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .KeycloakContactAddition,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = KeycloakContactAdditionProtocol.InitialMessage(coreProtocolMessage: coreMessage, contactIdentity: contactIdentityToAdd, signedContactDetails: signedContactDetails)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw Self.makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend

    }

    
    func getInitiateGroupMembersQueryMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            assertionFailure()
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw Self.makeError(message: "The identity delegate is not set")
        }
        
        let groupInformationWithPhoto = try identityDelegate.getGroupJoinedInformationAndPublishedPhoto(ownedIdentity: ownedIdentity, groupUid: groupUid, groupOwner: groupOwner, within: obvContext)
        
        let protocolInstanceUid = groupInformationWithPhoto.associatedProtocolUid
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .GroupManagement,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = GroupManagementProtocol.InitiateGroupMembersQueryMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformationWithPhoto.groupInformation)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw Self.makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
        
    }
    
    
    func getTriggerReinviteMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, memberIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw ProtocolStarterCoordinator.makeError(message: "The identity delegate is not set")
        }

        let groupInformationWithPhoto = try identityDelegate.getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: ownedIdentity, groupUid: groupUid, within: obvContext)

        let protocolInstanceUid = groupInformationWithPhoto.associatedProtocolUid
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .GroupManagement,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = GroupManagementProtocol.TriggerReinviteMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformationWithPhoto.groupInformation, memberIdentity: memberIdentity)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw ProtocolStarterCoordinator.makeError(message: "Could not generate ObvChannelProtocolMessageToSend instance for a TriggerReinviteAndUpdateMembersMessage")
        }
        return initialMessageToSend

    }
    
    func getInitialMessageForDeviceDiscoveryForContactIdentityProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .DeviceDiscoveryForContactIdentity,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = DeviceDiscoveryForContactIdentityProtocol.InitialMessage(coreProtocolMessage: coreMessage, contactIdentity: contactIdentity)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw ProtocolStarterCoordinator.makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend

    }

    func getInitialMessageForDownloadIdentityPhotoChildProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactIdentityDetailsElements: IdentityDetailsElements) throws -> ObvChannelProtocolMessageToSend {

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)

        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                               cryptoProtocolId: .DownloadIdentityPhoto,
                                               protocolInstanceUid: protocolInstanceUid)
        let initialMessage = DownloadIdentityPhotoChildProtocol.InitialMessage(
            coreProtocolMessage: coreMessage,
            contactIdentity: contactIdentity,
            contactIdentityDetailsElements: contactIdentityDetailsElements)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw ProtocolStarterCoordinator.makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
    }

    func getInitialMessageForDownloadGroupPhotoChildProtocol(ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation) throws -> ObvChannelProtocolMessageToSend {

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)

        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .DownloadGroupPhoto,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = DownloadGroupPhotoChildProtocol.InitialMessage.init(coreProtocolMessage: coreMessage, groupInformation: groupInformation)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw ProtocolStarterCoordinator.makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
    }
    
    func getInitialMessageForTrustEstablishmentWithMutualScanProtocol(ownedIdentity: ObvCryptoIdentity, remoteIdentity: ObvCryptoIdentity, signature: Data) throws -> ObvChannelProtocolMessageToSend {
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)

        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .TrustEstablishmentWithMutualScan,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = TrustEstablishmentWithMutualScanProtocol.InitialMessage(coreProtocolMessage: coreMessage, contactIdentity: remoteIdentity, signature: signature)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw ProtocolStarterCoordinator.makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
    }
    
    
    func getInitialMessageForAddingOwnCapabilities(ownedIdentity: ObvCryptoIdentity, newOwnCapabilities: Set<ObvCapability>) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)

        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .ContactCapabilitiesDiscovery,
                                              protocolInstanceUid: protocolInstanceUid)
        let message = DeviceCapabilitiesDiscoveryProtocol.InitialForAddingOwnCapabilitiesMessage(
            coreProtocolMessage: coreMessage,
            newOwnCapabilities: newOwnCapabilities)
        guard let initialMessageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw ProtocolStarterCoordinator.makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
        
    }
    
    
    func getInitialMessageForOneToOneContactInvitationProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)

        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .OneToOneContactInvitation,
                                              protocolInstanceUid: protocolInstanceUid)
        let message = OneToOneContactInvitationProtocol.InitialMessage(coreProtocolMessage: coreMessage, contactIdentity: contactIdentity)
        guard let initialMessageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            assertionFailure()
            throw ProtocolStarterCoordinator.makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
    
    }
    
    
    func getInitialMessageForDowngradingOneToOneContact(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)

        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .ContactManagement,
                                              protocolInstanceUid: protocolInstanceUid)
        let message = ContactManagementProtocol.InitiateContactDowngradeMessage(coreProtocolMessage: coreMessage, contactIdentity: contactIdentity)
        guard let initialMessageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            assertionFailure()
            throw ProtocolStarterCoordinator.makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
    
    }

    
    func getInitialMessageForOneStatusSyncRequest(ownedIdentity: ObvCryptoIdentity, contactsToSync: Set<ObvCryptoIdentity>) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)

        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .OneToOneContactInvitation,
                                              protocolInstanceUid: protocolInstanceUid)
        let message = OneToOneContactInvitationProtocol.InitialOneToOneStatusSyncRequestMessage(coreProtocolMessage: coreMessage, contactsToSync: contactsToSync)
        guard let initialMessageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            assertionFailure()
            throw ProtocolStarterCoordinator.makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend

    }
    
    // MARK: - Groups V2
    
    func getInitiateGroupCreationMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, ownRawPermissions: Set<String>, otherGroupMembers: Set<GroupV2.IdentityAndPermissions>, serializedGroupCoreDetails: Data, photoURL: URL?, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .GroupV2,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = GroupV2Protocol.InitiateGroupCreationMessage(coreProtocolMessage: coreMessage,
                                                                          ownRawPermissions: ownRawPermissions,
                                                                          otherGroupMembers: otherGroupMembers,
                                                                          serializedGroupCoreDetails: serializedGroupCoreDetails,
                                                                          photoURL: photoURL)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
    }

    
    func getInitiateGroupUpdateMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, changeset: ObvGroupV2.Changeset, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = try groupIdentifier.computeProtocolInstanceUid()
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .GroupV2,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = GroupV2Protocol.InitiateGroupUpdateMessage(coreProtocolMessage: coreMessage,
                                                                        groupIdentifier: groupIdentifier,
                                                                        changeset: changeset)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
    }

    
    func getInitiateGroupLeaveMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let initialMessage = try getInitiateGroupLeaveMessageForStartingGroupV2Protocol(
            ownedIdentity: ownedIdentity,
            groupIdentifier: groupIdentifier,
            simulateReceivedMessage: false,
            flowId: flowId)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
        
    }
    
    
    func getInitiateGroupLeaveMessageForStartingGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, simulateReceivedMessage: Bool, flowId: FlowIdentifier) throws -> GroupV2Protocol.InitiateGroupLeaveMessage {
        
        let protocolInstanceUid = try groupIdentifier.computeProtocolInstanceUid()
        
        let coreMessage: CoreProtocolMessage
        if simulateReceivedMessage {
            coreMessage = CoreProtocolMessage.getLocalCoreProtocolMessageForSimulatingReceivedMessage(
                ownedIdentity: ownedIdentity,
                cryptoProtocolId: .GroupV2,
                protocolInstanceUid: protocolInstanceUid)
        } else {
            coreMessage = CoreProtocolMessage(
                channelType: .Local(ownedIdentity: ownedIdentity),
                cryptoProtocolId: .GroupV2,
                protocolInstanceUid: protocolInstanceUid)
        }
        
        let initialMessage = GroupV2Protocol.InitiateGroupLeaveMessage(coreProtocolMessage: coreMessage,
                                                                       groupIdentifier: groupIdentifier)

        return initialMessage
        
    }
    
    
    func getInitiateGroupReDownloadMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = try groupIdentifier.computeProtocolInstanceUid()
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .GroupV2,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = GroupV2Protocol.InitiateGroupReDownloadMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend

    }

    
    func getInitiateInitiateGroupDisbandMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)

        let initialMessage = try getInitiateInitiateGroupDisbandMessageForStartingGroupV2Protocol(
            ownedIdentity: ownedIdentity,
            groupIdentifier: groupIdentifier,
            simulateReceivedMessage: false,
            flowId: flowId)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend

    }

    
    func getInitiateInitiateGroupDisbandMessageForStartingGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, simulateReceivedMessage: Bool, flowId: FlowIdentifier) throws -> GroupV2Protocol.InitiateGroupDisbandMessage {
        
        let protocolInstanceUid = try groupIdentifier.computeProtocolInstanceUid()
        let coreMessage: CoreProtocolMessage
        if simulateReceivedMessage {
            coreMessage = CoreProtocolMessage.getLocalCoreProtocolMessageForSimulatingReceivedMessage(
                ownedIdentity: ownedIdentity,
                cryptoProtocolId: .GroupV2,
                protocolInstanceUid: protocolInstanceUid)
        } else {
            coreMessage = CoreProtocolMessage(
                channelType: .Local(ownedIdentity: ownedIdentity),
                cryptoProtocolId: .GroupV2,
                protocolInstanceUid: protocolInstanceUid)
        }
        let initialMessage = GroupV2Protocol.InitiateGroupDisbandMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier)

        return initialMessage
        
    }

    
    func getInitiateBatchKeysResendMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactDeviceUID: UID, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        // Even if we are dealing with a step of the GroupV2 protocol, we do not need a specific protocol instance UID (since this would make no sense in that specific case)
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .GroupV2,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = GroupV2Protocol.InitiateBatchKeysResendMessage(coreProtocolMessage: coreMessage, contactIdentity: contactIdentity, contactDeviceUID: contactDeviceUID)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend

    }
    

    // MARK: - Keycloak pushed groups

    func getInitiateUpdateKeycloakGroupsMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, signedGroupBlobs: Set<String>, signedGroupDeletions: Set<String>, signedGroupKicks: Set<String>, keycloakCurrentTimestamp: Date, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)

        // Even if we are dealing with a step of the GroupV2 protocol, we do not need a specific protocol instance UID (since this would make no sense in that specific case)
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .GroupV2,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = GroupV2Protocol.InitiateUpdateKeycloakGroupsMessage(coreProtocolMessage: coreMessage,
                                                                                 signedGroupBlobs: signedGroupBlobs,
                                                                                 signedGroupDeletions: signedGroupDeletions,
                                                                                 signedGroupKicks: signedGroupKicks,
                                                                                 keycloakCurrentTimestamp: keycloakCurrentTimestamp)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            assertionFailure()
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend

    }

    
    func getInitiateTargetedPingMessageForKeycloakGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, pendingMemberIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)

        let protocolInstanceUid = try groupIdentifier.computeProtocolInstanceUid()
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .GroupV2,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = GroupV2Protocol.InitiateTargetedPingMessage(
            coreProtocolMessage: coreMessage,
            groupIdentifier: groupIdentifier,
            pendingMemberIdentity: pendingMemberIdentity)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend

    }
    
    // MARK: - OwnedIdentity Deletion Protocol
    
    func getInitiateOwnedIdentityDeletionMessage(ownedCryptoIdentityToDelete: ObvCryptoIdentity, notifyContacts: Bool, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)

        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedCryptoIdentityToDelete),
                                              cryptoProtocolId: .ownedIdentityDeletionProtocol,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = OwnedIdentityDeletionProtocol.InitiateOwnedIdentityDeletionMessage(coreProtocolMessage: coreMessage, ownedCryptoIdentityToDelete: ownedCryptoIdentityToDelete, notifyContacts: notifyContacts)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend

    }
    
        
}

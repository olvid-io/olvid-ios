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
    
    
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) {
        observeNotifications()
    }
    
    deinit {
        notificationCenterTokens.forEach { delegateManager?.notificationDelegate?.removeObserver($0) }
    }
    
    private func observeNotifications() {
        guard let notificationDelegate = delegateManager?.notificationDelegate else { assertionFailure(); return }
        notificationCenterTokens.append(contentsOf: [
            notificationDelegate.addObserverOfOwnedIdentityTransferProtocolNotification(.ownedIdentityTransferProtocolFailed { [weak self] payload in
                self?.postAbortMessageForOwnedIdentityTransferProtocol(ownedCryptoIdentity: payload.ownedCryptoIdentity, protocolInstanceUID: payload.protocolInstanceUID)
                ObvProtocolNotification.anOwnedIdentityTransferProtocolFailed(ownedCryptoIdentity: payload.ownedCryptoIdentity, protocolInstanceUID: payload.protocolInstanceUID, error: payload.error)
                    .postOnBackgroundQueue(within: notificationDelegate)
            })
        ])
    }
    
}


// MARK: - Implementing ProtocolStarterDelegate

extension ProtocolStarterCoordinator {
    
    func getInitialMessageForTrustEstablishmentProtocol(of contactIdentity: ObvCryptoIdentity, withFullDisplayName contactFullDisplayName: String, forOwnedIdentity ownedIdentity: ObvCryptoIdentity, withOwnedIdentityCoreDetails ownIdentityCoreDetails: ObvIdentityCoreDetails, usingProtocolInstanceUid protocolInstanceUid: UID) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        // Start the updated version of the TrustEstablishmentProtocol
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .trustEstablishmentWithSAS,
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
    
    
    func getInitialMessageForContactMutualIntroductionProtocol(of identity1: ObvCryptoIdentity, with identity2: ObvCryptoIdentity, byOwnedIdentity ownedIdentity: ObvCryptoIdentity, usingProtocolInstanceUid protocolInstanceUid: UID) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .ContactMutualIntroduction,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = ContactMutualIntroductionProtocol.InitialMessage(coreProtocolMessage: coreMessage,
                                                                              contactIdentityA: identity1,
                                                                              contactIdentityB: identity2)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            assertionFailure()
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
        }
        return initialMessageToSend
        
    }
    
    
    func getInitialMessageForChannelCreationWithContactDeviceProtocol(betweenTheCurrentDeviceOfOwnedIdentity ownedIdentity: ObvCryptoIdentity, andTheDeviceUid contactDeviceUid: UID, ofTheContactIdentity contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        os_log("🛟 [%{public}@] Call to getInitialMessageForChannelCreationWithContactDeviceProtocol with contact", log: log, type: .info, contactIdentity.debugDescription)

        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .channelCreationWithContactDevice,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = ChannelCreationWithContactDeviceProtocol.InitialMessage(coreProtocolMessage: coreMessage, contactIdentity: contactIdentity, contactDeviceUid: contactDeviceUid)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            assertionFailure()
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
        }
        return initialMessageToSend
    }
    
    
    func getInitialMessageForChannelCreationWithOwnedDeviceProtocol(ownedIdentity: ObvCryptoIdentity, remoteDeviceUid: UID) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .channelCreationWithOwnedDevice,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = ChannelCreationWithOwnedDeviceProtocol.InitialMessage(coreProtocolMessage: coreMessage, remoteDeviceUid: remoteDeviceUid)
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
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .groupManagement,
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
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .groupManagement,
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
    
    
    func getDisbandGroupMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        
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
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .groupManagement,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = GroupManagementProtocol.DisbandGroupMessage(coreProtocolMessage: coreMessage,
                                                                         groupInformation: groupInformationWithPhoto.groupInformation)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            assertionFailure()
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw Self.makeError(message: "Could create generic protocol message to send")
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
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .groupManagement,
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
                cryptoProtocolId: .groupManagement,
                protocolInstanceUid: protocolInstanceUid)
        } else {
            coreMessage = CoreProtocolMessage(
                channelType: .local(ownedIdentity: ownedIdentity),
                cryptoProtocolId: .groupManagement,
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
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .identityDetailsPublication,
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
                cryptoProtocolId: .groupManagement,
                protocolInstanceUid: protocolInstanceUid)
        } else {
            coreMessage = CoreProtocolMessage(
                channelType: .local(ownedIdentity: ownedIdentity),
                cryptoProtocolId: .groupManagement,
                protocolInstanceUid: protocolInstanceUid)
        }
        let initialMessage = GroupManagementProtocol.LeaveGroupJoinedMessage(coreProtocolMessage: coreMessage,
                                                                             groupInformation: groupInformationWithPhoto.groupInformation)
        
        return initialMessage
        
    }
    
        
    func getInitiateAddKeycloakContactMessageForKeycloakContactAdditionProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentityToAdd: ObvCryptoIdentity, signedContactDetails: String) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .keycloakContactAddition,
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
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .groupManagement,
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
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .groupManagement,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = GroupManagementProtocol.TriggerReinviteMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformationWithPhoto.groupInformation, memberIdentity: memberIdentity)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw ProtocolStarterCoordinator.makeError(message: "Could not generate ObvChannelProtocolMessageToSend instance for a TriggerReinviteAndUpdateMembersMessage")
        }
        return initialMessageToSend
        
    }
    
    func getInitialMessageForContactDeviceDiscoveryProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .contactDeviceDiscovery,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = ContactDeviceDiscoveryProtocol.InitialMessage(coreProtocolMessage: coreMessage, contactIdentity: contactIdentity)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw ProtocolStarterCoordinator.makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
        
    }
    
    func getInitialMessageForDownloadIdentityPhotoChildProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactIdentityDetailsElements: IdentityDetailsElements) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .downloadIdentityPhoto,
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
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .downloadGroupPhoto,
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
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .trustEstablishmentWithMutualScan,
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
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .contactCapabilitiesDiscovery,
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
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .oneToOneContactInvitation,
                                              protocolInstanceUid: protocolInstanceUid)
        let message = OneToOneContactInvitationProtocol.InitialMessage(coreProtocolMessage: coreMessage, contactIdentity: contactIdentity)
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
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .oneToOneContactInvitation,
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
    
    func getInitiateGroupCreationMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, ownRawPermissions: Set<String>, otherGroupMembers: Set<GroupV2.IdentityAndPermissions>, serializedGroupCoreDetails: Data, photoURL: URL?, serializedGroupType: Data, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .groupV2,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = GroupV2Protocol.InitiateGroupCreationMessage(coreProtocolMessage: coreMessage,
                                                                          ownRawPermissions: ownRawPermissions,
                                                                          otherGroupMembers: otherGroupMembers,
                                                                          serializedGroupCoreDetails: serializedGroupCoreDetails,
                                                                          photoURL: photoURL,
                                                                          serializedGroupType: serializedGroupType)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
    }
    
    
    func getInitiateGroupUpdateMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, changeset: ObvGroupV2.Changeset, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = try groupIdentifier.computeProtocolInstanceUid()
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .groupV2,
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
    
    
    func getInitialMessageForDownloadGroupV2PhotoProtocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, serverPhotoInfo: GroupV2.ServerPhotoInfo) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .downloadGroupV2Photo,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = DownloadGroupV2PhotoProtocol.InitialMessage(
            coreProtocolMessage: coreMessage,
            groupIdentifier: groupIdentifier,
            serverPhotoInfo: serverPhotoInfo)
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
                cryptoProtocolId: .groupV2,
                protocolInstanceUid: protocolInstanceUid)
        } else {
            coreMessage = CoreProtocolMessage(
                channelType: .local(ownedIdentity: ownedIdentity),
                cryptoProtocolId: .groupV2,
                protocolInstanceUid: protocolInstanceUid)
        }
        
        let initialMessage = GroupV2Protocol.InitiateGroupLeaveMessage(coreProtocolMessage: coreMessage,
                                                                       groupIdentifier: groupIdentifier)
        
        return initialMessage
        
    }
    
    
    func getInitiateGroupReDownloadMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = try groupIdentifier.computeProtocolInstanceUid()
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .groupV2,
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
                cryptoProtocolId: .groupV2,
                protocolInstanceUid: protocolInstanceUid)
        } else {
            coreMessage = CoreProtocolMessage(
                channelType: .local(ownedIdentity: ownedIdentity),
                cryptoProtocolId: .groupV2,
                protocolInstanceUid: protocolInstanceUid)
        }
        let initialMessage = GroupV2Protocol.InitiateGroupDisbandMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier)
        
        return initialMessage
        
    }
    
    
    func getInitiateBatchKeysResendMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, remoteIdentity: ObvCryptoIdentity, remoteDeviceUID: UID, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        // Even if we are dealing with a step of the GroupV2 protocol, we do not need a specific protocol instance UID (since this would make no sense in that specific case)
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .groupV2,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = GroupV2Protocol.InitiateBatchKeysResendMessage(coreProtocolMessage: coreMessage, remoteIdentity: remoteIdentity, remoteDeviceUID: remoteDeviceUID)
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
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .groupV2,
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
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .groupV2,
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
    
    func getInitiateOwnedIdentityDeletionMessage(ownedCryptoIdentityToDelete: ObvCryptoIdentity, globalOwnedIdentityDeletion: Bool) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedCryptoIdentityToDelete),
                                              cryptoProtocolId: .ownedIdentityDeletionProtocol,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = OwnedIdentityDeletionProtocol.InitiateOwnedIdentityDeletionMessage(coreProtocolMessage: coreMessage, globalOwnedIdentityDeletion: globalOwnedIdentityDeletion)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
        
    }
    
    
    // MARK: Contact Device Management protocol
    
    func getInitiateContactDeletionMessageForContactManagementProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentityToDelete: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .contactManagement,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = ContactManagementProtocol.InitiateContactDeletionMessage(coreProtocolMessage: coreMessage, contactIdentity: contactIdentityToDelete)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw Self.makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
        
    }

    
    func getInitialMessageForDowngradingOneToOneContact(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                              cryptoProtocolId: .contactManagement,
                                              protocolInstanceUid: protocolInstanceUid)
        let message = ContactManagementProtocol.InitiateContactDowngradeMessage(coreProtocolMessage: coreMessage, contactIdentity: contactIdentity)
        guard let initialMessageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            assertionFailure()
            throw ProtocolStarterCoordinator.makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
        
    }
    
    

    // MARK: - Owned device protocols
    
    func getInitiateOwnedDeviceDiscoveryMessage(ownedCryptoIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedCryptoIdentity),
                                              cryptoProtocolId: .ownedDeviceDiscovery,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = OwnedDeviceDiscoveryProtocol.InitiateOwnedDeviceDiscoveryMessage(coreProtocolMessage: coreMessage)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
    }
    
    
    func getInitiateOwnedDeviceManagementMessage(ownedCryptoIdentity: ObvCryptoIdentity, request: ObvOwnedDeviceManagementRequest) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedCryptoIdentity),
                                              cryptoProtocolId: .ownedDeviceManagement,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = OwnedDeviceManagementProtocol.InitiateOwnedDeviceManagementMessage(
            coreProtocolMessage: coreMessage,
            request: request)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend

    }
    
    
    
    // MARK: - Owned identity transfer protocol
    
    private func postAbortMessageForOwnedIdentityTransferProtocol(ownedCryptoIdentity: ObvCryptoIdentity, protocolInstanceUID: UID) {
        Task {
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
            let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedCryptoIdentity),
                                                  cryptoProtocolId: .ownedIdentityTransfer,
                                                  protocolInstanceUid: protocolInstanceUID)
            let initialMessage = OwnedIdentityTransferProtocol.AbortProtocolMessage(coreProtocolMessage: coreMessage)
            guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                assertionFailure()
                os_log("Could create generic protocol message to send", log: log, type: .fault)
                return
            }
            try? await postChannelMessage(initialMessageToSend, flowId: FlowIdentifier())
        }
    }

    
    func cancelAllOwnedIdentityTransferProtocols(flowId: FlowIdentifier) async throws {
        guard let contextCreator = delegateManager.contextCreator else { throw ObvError.theContextCreatorIsNil }
        let identitiesAndUIDs = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[(ownedCryptoIdentity: ObvCryptoIdentity, protocolInstanceUID: UID)], Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let infos = try ProtocolInstance.getAllPrimaryKeysOfOwnedIdentityTransferProtocolInstances(within: obvContext)
                    continuation.resume(returning: infos)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        identitiesAndUIDs.forEach { (ownedCryptoIdentity, protocolInstanceUID) in
            postAbortMessageForOwnedIdentityTransferProtocol(ownedCryptoIdentity: ownedCryptoIdentity, protocolInstanceUID: protocolInstanceUID)
        }
    }
    
    
    func initiateOwnedIdentityTransferProtocolOnSourceDevice(ownedCryptoIdentity: ObvCryptoIdentity, onAvailableSessionNumber: @escaping (ObvOwnedIdentityTransferSessionNumber) -> Void, onAvailableSASExpectedOnInput: @escaping (ObvOwnedIdentityTransferSas, String, UID) -> Void, flowId: FlowIdentifier) async throws {
        
        guard let notificationDelegate = delegateManager.notificationDelegate else { throw ObvError.theNotificationDelegateIsNil }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        
        // Create the InitiateTransferOnSourceDeviceMessage that will allow to start the ownedIdentityTransfer protocol
        
        let protocolInstanceUID = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedCryptoIdentity),
                                              cryptoProtocolId: .ownedIdentityTransfer,
                                              protocolInstanceUid: protocolInstanceUID)
        let message = OwnedIdentityTransferProtocol.InitiateTransferOnSourceDeviceMessage(coreProtocolMessage: coreMessage)
        guard let initialMessageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        
        
        var localTokens = [NSObjectProtocol]()
        
        // Before starting the protocol: observe the notification sent by this protocol when the session number is available.
        // This typically takes longer than the "cancel block", since getting this session number requires a network call to the transfer server.
        // Uppon receiving this notification, we pass the session number back to the app using the `onAvailableSessionNumber` callback.
        
        do {
            var token: NSObjectProtocol?
            token = notificationDelegate.addObserverOfOwnedIdentityTransferProtocolNotification(.sourceDisplaySessionNumber { payload in
                // Make sure the received notification concerns the protocol we launched here.
                guard payload.protocolInstanceUID == protocolInstanceUID else { return }
                let sessionNumber = payload.sessionNumber
                // Remove the observer, since we do not expect to be notified again
                notificationDelegate.removeObserver(token!)
                // Transfer the session number back to the app
                onAvailableSessionNumber(sessionNumber)
            })
            localTokens.append(token!)
        }
        
        // Before starting the protocol: observe the notification sent by this protocol when the SAS that we expect the user to enter on
        // this source device is available.
        
        do {
            var token: NSObjectProtocol?
            token = notificationDelegate.addObserverOfOwnedIdentityTransferProtocolNotification(.waitingForSASOnSourceDevice { payload in
                // Make sure the received notification concerns the protocol we launched here.
                guard payload.protocolInstanceUID == protocolInstanceUID else { return }
                // Remove the observer, since we do not expect to be notified again
                notificationDelegate.removeObserver(token!)
                // Transfer the sas to the app
                onAvailableSASExpectedOnInput(payload.sasExpectedOnInput, payload.targetDeviceName, payload.protocolInstanceUID)
            })
            localTokens.append(token!)
        }

        
        // Now that we observe the two important notifications allowing to call the two callbacks that we received in parameters,
        // we can post the protocol message that will start the ownedIdentityTransfer protocol in this source device.
        
        do {
            try await postChannelMessage(initialMessageToSend, flowId: flowId)
            notificationCenterTokens.append(contentsOf: localTokens)
        } catch {
            localTokens.forEach { token in
                notificationDelegate.removeObserver(token)
            }
            throw error
        }
        
    }

    
    func initiateOwnedIdentityTransferProtocolOnTargetDevice(currentDeviceName: String, transferSessionNumber: ObvOwnedIdentityTransferSessionNumber, onIncorrectTransferSessionNumber: @escaping () -> Void, onAvailableSas: @escaping (UID, ObvOwnedIdentityTransferSas) -> Void, flowId: FlowIdentifier) async throws {
        
        guard let notificationDelegate = delegateManager.notificationDelegate else { throw ObvError.theNotificationDelegateIsNil }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)

        // We generate an ephemeral identity valid during the owned identity transfer protocol only
        
        let authEmplemByteId = ObvCryptoSuite.sharedInstance.getDefaultAuthenticationImplementationByteId()
        let pkEncryptionImplemByteId = ObvCryptoSuite.sharedInstance.getDefaultPublicKeyEncryptionImplementationByteId()

        let ephemeralOwnedIdentity = ObvOwnedCryptoIdentity.gen(withServerURL: ObvConstants.ephemeralIdentityServerURL,
                                                                forAuthenticationImplementationId: authEmplemByteId,
                                                                andPublicKeyEncryptionImplementationByteId: pkEncryptionImplemByteId,
                                                                using: prng)
        
        // Create the InitiateTransferOnTargetDeviceMessage that will allow to start the ownedIdentityTransfer protocol
        
        let protocolInstanceUID = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ephemeralOwnedIdentity.getObvCryptoIdentity()),
                                              cryptoProtocolId: .ownedIdentityTransfer,
                                              protocolInstanceUid: protocolInstanceUID)
        // Note we don't need the ephemeral identity's privateKeyForAuthentication
        let message = OwnedIdentityTransferProtocol.InitiateTransferOnTargetDeviceMessage(
            coreProtocolMessage: coreMessage,
            currentDeviceName: currentDeviceName,
            transferSessionNumber: transferSessionNumber,
            encryptionPrivateKey: ephemeralOwnedIdentity.privateKeyForPublicKeyEncryption,
            macKey: ephemeralOwnedIdentity.secretMACKey)
        guard let initialMessageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }

        var localTokens = [NSObjectProtocol]()

        // Before starting the protocol: observe the notification sent by this protocol when the transfer session number entered by the user is incorrect.
        
        do {
            var token: NSObjectProtocol?
            token = notificationDelegate.addObserverOfOwnedIdentityTransferProtocolNotification(.userEnteredIncorrectTransferSessionNumber(payload: { payload in
                // Make sure the received notification concerns the protocol we launched here.
                guard payload.protocolInstanceUID == protocolInstanceUID else { return }
                // Remove all the observers added here, since we do not expect to be notified again
                localTokens.forEach { notificationDelegate.removeObserver($0) }
                // Transfer the information to the app
                onIncorrectTransferSessionNumber()
            }))
            localTokens.append(token!)
        }

        // Before starting the protocol: observe the notification sent by this protocol when the SAS is available and can be shown on this target device
        
        do {
            var token: NSObjectProtocol?
            token = notificationDelegate.addObserverOfOwnedIdentityTransferProtocolNotification(.sasIsAvailable(payload: { payload in
                // Make sure the received notification concerns the protocol we launched here.
                guard payload.protocolInstanceUID == protocolInstanceUID else { return }
                // Remove all the observers added here, since we do not expect to be notified again
                localTokens.forEach { notificationDelegate.removeObserver($0) }
                // Transfer the information to the app
                onAvailableSas(protocolInstanceUID, payload.sas)
            }))
            localTokens.append(token!)
        }
        
        // Post the protocol message
        
        do {
            try await postChannelMessage(initialMessageToSend, flowId: flowId)
            notificationCenterTokens.append(contentsOf: localTokens)
        } catch {
            localTokens.forEach { token in
                notificationDelegate.removeObserver(token)
            }
            throw error
        }

    }
    
    
    /// Called by the app during an owned identity transfer protocol on the target device, when the SAS is shown. The app calls this method to get notified of the various events occuring during the protocol finalisation,
    /// like when the snapshot sent by the source device is received on this target device, or when the processing of this snapshot did end.
    /// - Parameters:
    ///   - protocolInstanceUID: The identifier of the currently running owned identity transfer protocol.
    ///   - onSyncSnapshotReception: The block to call when the snapshot sent by the source device is received on this target device.
    func appIsShowingSasAndExpectingEndOfProtocol(protocolInstanceUID: UID, onSyncSnapshotReception: @escaping () -> Void, onSuccessfulTransfer: @escaping (ObvCryptoId, Error?) -> Void) async {
     
        guard let notificationDelegate = delegateManager.notificationDelegate else { assertionFailure(); return }

        var localTokens = [NSObjectProtocol]()

        do {
            var token: NSObjectProtocol?
            token = notificationDelegate.addObserverOfOwnedIdentityTransferProtocolNotification(.processingReceivedSnapshotOntargetDevice { payload in
                // Make sure the received notification concerns the protocol we launched here.
                guard payload.protocolInstanceUID == protocolInstanceUID else { return }
                // Transfer the information to the app
                onSyncSnapshotReception()
            })
            localTokens.append(token!)
        }

        do {
            var token: NSObjectProtocol?
            token = notificationDelegate.addObserverOfOwnedIdentityTransferProtocolNotification(.successfulTransferOnTargetDevice { payload in
                // Make sure the received notification concerns the protocol we launched here.
                guard payload.protocolInstanceUID == protocolInstanceUID else { return }
                // Remove all the observers added here, since we do not expect to be notified again
                localTokens.forEach { notificationDelegate.removeObserver($0) }
                // Transfer the information to the app
                onSuccessfulTransfer(payload.transferredOwnedCryptoId, payload.postTransferError)
            })
            localTokens.append(token!)
        }

        notificationCenterTokens.append(contentsOf: localTokens)

    }
    
    
    func continueOwnedIdentityTransferProtocolOnUserEnteredSASOnSourceDevice(enteredSAS: ObvOwnedIdentityTransferSas, deviceToKeepActive: UID?, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID, snapshotSentToTargetDevice: @escaping () -> Void) async throws {
  
        guard let notificationDelegate = delegateManager.notificationDelegate else { assertionFailure(); return }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedCryptoId.cryptoIdentity),
                                              cryptoProtocolId: .ownedIdentityTransfer,
                                              protocolInstanceUid: protocolInstanceUID)
        let message = OwnedIdentityTransferProtocol.SourceSASInputMessage(coreProtocolMessage: coreMessage, enteredSAS: enteredSAS, deviceUIDToKeepActive: deviceToKeepActive)
        guard let initialMessageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }

        var localTokens = [NSObjectProtocol]()

        // Before starting the protocol: observe the notification sent by this protocol when the snapshot is sent (indicating the end of the protocol for the source device).
        // Uppon receiving this notification, we pass the success information back to the app using the `snapshotSentToTargetDevice` callback.
        
        var token1: NSObjectProtocol?
        do {
            token1 = notificationDelegate.addObserverOfOwnedIdentityTransferProtocolNotification(.protocolFinishedSuccessfullyOnSourceDeviceAsSnapshotSentWasSent { payload in
                guard let token1 else { return }
                // Make sure the received notification concerns the protocol we launched here.
                guard payload.protocolInstanceUID == protocolInstanceUID else { return }
                // Remove the observer, since we do not expect to be notified again
                notificationDelegate.removeObserver(token1)
                // Notify the app, with no error
                snapshotSentToTargetDevice()
            })
            localTokens.append(token1!)
        }
        
        // Before starting the protocol: observe the notification sent by this protocol when the snapshot sending failed (indicating the end of the protocol for the source device).
        // We do not notify the app (the generic listener on the ownedIdentityTransferProtocolFailed notification does this already).
        // We simply unsubcribe.

        do {
            var token: NSObjectProtocol?
            token = notificationDelegate.addObserverOfOwnedIdentityTransferProtocolNotification(.ownedIdentityTransferProtocolFailed { payload in
                // Make sure the received notification concerns the protocol we launched here.
                guard payload.protocolInstanceUID == protocolInstanceUID else { return }
                // Remove the observer, since we do not expect to be notified again
                if let token1 {
                    notificationDelegate.removeObserver(token1)
                }
                notificationDelegate.removeObserver(token!)
            })
            localTokens.append(token!)
        }

        notificationCenterTokens.append(contentsOf: localTokens)

        try await postChannelMessage(initialMessageToSend, flowId: FlowIdentifier())
        
    }
    


    // MARK: - Keycloak binding and unbinding
    
    func getOwnedIdentityKeycloakBindingMessage(ownedCryptoIdentity: ObvCryptoIdentity, keycloakState: ObvKeycloakState, keycloakUserId: String) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedCryptoIdentity),
                                              cryptoProtocolId: .keycloakBindingAndUnbinding,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = KeycloakBindingAndUnbindingProtocol.OwnedIdentityKeycloakBindingMessage(
            coreProtocolMessage: coreMessage,
            keycloakState: keycloakState,
            keycloakUserId: keycloakUserId)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
        
    }

    
    func getOwnedIdentityKeycloakUnbindingMessage(ownedCryptoIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedCryptoIdentity),
                                              cryptoProtocolId: .keycloakBindingAndUnbinding,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = KeycloakBindingAndUnbindingProtocol.OwnedIdentityKeycloakUnbindingMessage(coreProtocolMessage: coreMessage)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend
        
    }
    
    
    // MARK: - SynchronizationProtocol
    
    func getInitiateSyncAtomMessageForSynchronizationProtocol(ownedCryptoIdentity: ObvCryptoIdentity, syncAtom: ObvSyncAtom) throws -> ObvChannelProtocolMessageToSend {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        let protocolInstanceUid = UID.gen(with: prng)
        let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedCryptoIdentity),
                                              cryptoProtocolId: .synchronization,
                                              protocolInstanceUid: protocolInstanceUid)
        let initialMessage = SynchronizationProtocol.InitiateSyncAtomMessage(coreProtocolMessage: coreMessage, syncAtom: syncAtom)
        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
            os_log("Could create generic protocol message to send", log: log, type: .fault)
            throw makeError(message: "Could create generic protocol message to send")
        }
        return initialMessageToSend

    }
    
    
//    func getTriggerSyncSnapshotMessageForSynchronizationProtocol(ownedCryptoIdentity: ObvCryptoIdentity, currentDeviceUid: UID, otherOwnedDeviceUid: UID, forceSendSnapshot: Bool) throws -> ObvChannelProtocolMessageToSend {
//
//        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
//        let protocolInstanceUid = try SynchronizationProtocol.computeOngoingProtocolInstanceUid(ownedCryptoId: ownedCryptoIdentity, currentDeviceUid: currentDeviceUid, otherOwnedDeviceUid: otherOwnedDeviceUid)
//        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedCryptoIdentity),
//                                              cryptoProtocolId: .synchronization,
//                                              protocolInstanceUid: protocolInstanceUid)
//        let initialMessage = SynchronizationProtocol.TriggerSyncSnapshotMessage(coreProtocolMessage: coreMessage, forceSendSnapshot: forceSendSnapshot)
//        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
//            os_log("Could create generic protocol message to send", log: log, type: .fault)
//            throw makeError(message: "Could create generic protocol message to send")
//        }
//        return initialMessageToSend
//
//    }
    
    
//    func getInitiateSyncSnapshotMessageForSynchronizationProtocol(ownedCryptoIdentity: ObvCryptoIdentity, currentDeviceUid: UID, otherOwnedDeviceUid: UID) throws -> ObvChannelProtocolMessageToSend {
//        
//        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
//        let protocolInstanceUid = try SynchronizationProtocol.computeOngoingProtocolInstanceUid(ownedCryptoId: ownedCryptoIdentity, currentDeviceUid: currentDeviceUid, otherOwnedDeviceUid: otherOwnedDeviceUid)
//        let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedCryptoIdentity),
//                                              cryptoProtocolId: .synchronization,
//                                              protocolInstanceUid: protocolInstanceUid)
//        let initialMessage = SynchronizationProtocol.InitiateSyncSnapshotMessage(coreProtocolMessage: coreMessage, otherOwnedDeviceUID: otherOwnedDeviceUid)
//        guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
//            os_log("Could create generic protocol message to send", log: log, type: .fault)
//            throw makeError(message: "Could create generic protocol message to send")
//        }
//        return initialMessageToSend
//        
//    }

    // MARK: - Helpers
    
    private func postChannelMessage(_ message: ObvChannelProtocolMessageToSend, flowId: FlowIdentifier) async throws {
        
        guard let contextCreator = delegateManager.contextCreator else { throw ObvError.theContextCreatorIsNil }
        guard let channelDelegate = delegateManager.channelDelegate else { throw ObvError.theChannelDelegateIsNil }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ProtocolStarterCoordinator.logCategory)
        let prng = self.prng
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                    try obvContext.save(logOnFailure: log)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
    }

    
    
    // MARK: - Errors
    
    enum ObvError: Error {
        case theNotificationDelegateIsNil
        case theContextCreatorIsNil
        case theChannelDelegateIsNil
        case theDelegateManagerIsNil
    }
    
}

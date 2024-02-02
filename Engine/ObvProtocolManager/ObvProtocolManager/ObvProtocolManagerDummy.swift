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
import os.log
import CoreData
import ObvMetaManager
import ObvCrypto
import ObvTypes
import OlvidUtils


public final class ObvProtocolManagerDummy: ObvProtocolDelegate, ObvFullRatchetProtocolStarterDelegate {
        
    static let defaultLogSubsystem = "io.olvid.protocol"
    lazy public var logSubsystem: String = {
        return ObvProtocolManagerDummy.defaultLogSubsystem
    }()
    
    public func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
        self.log = OSLog(subsystem: logSubsystem, category: "ObvProtocolManagerDummy")
    }
    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {}
    
    private static let errorDomain = "ObvProtocolManagerDummy"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }
    
    // MARK: Instance variables
    
    private var log: OSLog
    
    // MARK: Initialiser
    
    public init() {
        self.log = OSLog(subsystem: ObvProtocolManagerDummy.defaultLogSubsystem, category: "ObvProtocolManagerDummy")
    }
    
    
    public func deleteProtocolMetadataRelatingToContact(contactIdentity: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        os_log("deleteProtocolMetadataRelatingToContact does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "deleteProtocolMetadataRelatingToContact does nothing in this dummy implementation")
    }
    
    public func processProtocolReceivedMessage(_: ObvProtocolReceivedMessage, within: ObvContext) throws {
        os_log("processProtocolReceivedMessage(_: ObvProtocolReceivedMessage, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "processProtocolReceivedMessage(_: ObvProtocolReceivedMessage, within: ObvContext) does nothing in this dummy implementation")
    }
    
    public func process(_: ObvProtocolReceivedDialogResponse, within: ObvContext) throws {
        os_log("process(_: ObvProtocolReceivedDialogResponse, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "process(_: ObvProtocolReceivedDialogResponse, within: ObvContext) does nothing in this dummy implementation")
    }
    
    public func process(_: ObvProtocolReceivedServerResponse, within: ObvContext) throws {
        os_log("process(_: ObvProtocolReceivedServerResponse, within: ObvContext) does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "process(_: ObvProtocolReceivedServerResponse, within: ObvContext) does nothing in this dummy implementation")
    }
    
    public func abortProtocol(withProtocolInstanceUid: UID, forOwnedIdentity: ObvCryptoIdentity) throws {
        os_log("abortProtocol(withProtocolInstanceUid: UID, forOwnedIdentity: ObvCryptoIdentity) does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "abortProtocol(withProtocolInstanceUid: UID, forOwnedIdentity: ObvCryptoIdentity) does nothing in this dummy implementation")
    }
    
    public func getInitialMessageForTrustEstablishmentProtocol(of: ObvCryptoIdentity, withFullDisplayName: String, forOwnedIdentity: ObvCryptoIdentity, withOwnedIdentityCoreDetails: ObvIdentityCoreDetails, usingProtocolInstanceUid: UID) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForTrustEstablishmentProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitialMessageForTrustEstablishmentProtocol does nothing in this dummy implementation")
    }
    
    public func getInitialMessageForContactMutualIntroductionProtocol(of identity1: ObvCryptoIdentity, with identity2: ObvCryptoIdentity, byOwnedIdentity ownedIdentity: ObvCryptoIdentity, usingProtocolInstanceUid protocolInstanceUid: UID) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForContactMutualIntroductionProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitialMessageForContactMutualIntroductionProtocol does nothing in this dummy implementation")
    }
    
    public func getInitiateGroupCreationMessageForGroupManagementProtocol(groupCoreDetails: ObvGroupCoreDetails, photoURL: URL?, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, ownedIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateGroupCreationMessageForGroupManagementProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitiateGroupCreationMessageForGroupManagementProtocol does nothing in this dummy implementation")
    }
    
    public func getDisbandGroupMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        os_log("getDisbandGroupMessageForGroupManagementProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getDisbandGroupMessageForGroupManagementProtocol does nothing in this dummy implementation")
    }
    
    public func getInitialMessageForChannelCreationWithContactDeviceProtocol(betweenTheCurrentDeviceOfOwnedIdentity: ObvCryptoIdentity, andTheDeviceUid: UID, ofTheContactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForChannelCreationWithContactDeviceProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitialMessageForChannelCreationWithContactDeviceProtocol does nothing in this dummy implementation")
    }
    
    public func getInitialMessageForChannelCreationWithOwnedDeviceProtocol(ownedIdentity: ObvCryptoIdentity, remoteDeviceUid: UID) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForChannelCreationWithOwnedDeviceProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitialMessageForChannelCreationWithOwnedDeviceProtocol does nothing in this dummy implementation")
    }
    
    public func startFullRatchetProtocolForObliviousChannelBetween(currentDeviceUid: UID, andRemoteDeviceUid remoteDeviceUid: UID, ofRemoteIdentity remoteIdentity: ObvCryptoIdentity) throws {
        os_log("startFullRatchetProtocolForObliviousChannelBetween does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func getInitialMessageForIdentityDetailsPublicationProtocol(ownedIdentity: ObvCryptoIdentity, publishedIdentityDetailsVersion: Int) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForIdentityDetailsPublicationProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitialMessageForIdentityDetailsPublicationProtocol does nothing in this dummy implementation")
    }
    
    public func getOwnedGroupMembersChangedTriggerMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        os_log("getOwnedGroupMembersChangedTriggerMessageForGroupManagementProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getOwnedGroupMembersChangedTriggerMessageForGroupManagementProtocol does nothing in this dummy implementation")
    }
    
    public func getAddGroupMembersMessageForAddingMembersToContactGroupOwned(groupUid: UID, ownedIdentity: ObvCryptoIdentity, newGroupMembers: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        os_log("getAddGroupMembersMessageForAddingMembersToContactGroupOwned does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getAddGroupMembersMessageForAddingMembersToContactGroupOwned does nothing in this dummy implementation")
    }
    
    public func getRemoveGroupMembersMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, removedGroupMembers: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        os_log("getRemoveGroupMembersMessageForGroupManagementProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getRemoveGroupMembersMessageForGroupManagementProtocol does nothing in this dummy implementation")
    }
    
    public func getLeaveGroupJoinedMessageForGroupManagementProtocol(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        os_log("getLeaveGroupJoinedMessageForGroupManagementProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getLeaveGroupJoinedMessageForGroupManagementProtocol does nothing in this dummy implementation")
    }
    
    public func getInitiateContactDeletionMessageForContactManagementProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentityToDelete contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateContactDeletionMessageForContactManagementProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitiateContactDeletionMessageForContactManagementProtocol does nothing in this dummy implementation")
    }
    
    public func getInitiateAddKeycloakContactMessageForKeycloakContactAdditionProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentityToAdd contactIdentity: ObvCryptoIdentity, signedContactDetails: String) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateAddKeycloakContactMessageForKeycloakContactAdditionProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitiateAddKeycloakContactMessageForKeycloakContactAdditionProtocol does nothing in this dummy implementation")
    }
    
    public func getInitiateGroupMembersQueryMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateGroupMembersQueryMessageForGroupManagementProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitiateGroupMembersQueryMessageForGroupManagementProtocol does nothing in this dummy implementation")
    }
    
    public func getTriggerReinviteMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, memberIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        os_log("getTriggerReinviteMessageForGroupManagementProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getTriggerReinviteMessageForGroupManagementProtocol does nothing in this dummy implementation")
    }
    
    public func getInitialMessageForContactDeviceDiscoveryProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForContactDeviceDiscoveryProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitialMessageForContactDeviceDiscoveryProtocol does nothing in this dummy implementation")
    }
    
    public func getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithContactDeviceProtocolInstances(within obvContext: ObvContext) throws -> Set<ObliviousChannelIdentifierAlt> {
        os_log("getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithContactDeviceProtocolInstances does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithContactDeviceProtocolInstances does nothing in this dummy implementation")
    }
    
    public func getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithOwnedDeviceProtocolInstances(within obvContext: ObvContext) throws -> Set<ObliviousChannelIdentifierAlt> {
        os_log("getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithOwnedDeviceProtocolInstances does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithOwnedDeviceProtocolInstances does nothing in this dummy implementation")
    }
    
    public func getInitialMessageForDownloadIdentityPhotoChildProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactIdentityDetailsElements: IdentityDetailsElements) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForDownloadIdentityPhotoChildProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitialMessageForDownloadIdentityPhotoChildProtocol does nothing in this dummy implementation")
    }
    
    public func getInitialMessageForDownloadGroupPhotoChildProtocol(ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForDownloadGroupPhotoChildProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitialMessageForDownloadGroupPhotoChildProtocol does nothing in this dummy implementation")
    }
    
    public func getInitialMessageForTrustEstablishmentWithMutualScanProtocol(ownedIdentity: ObvCryptoIdentity, remoteIdentity: ObvCryptoIdentity, signature: Data) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForTrustEstablishmentWithMutualScanProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitialMessageForTrustEstablishmentWithMutualScanProtocol does nothing in this dummy implementation")
    }
    
    public func getInitialMessageForAddingOwnCapabilities(ownedIdentity: ObvCryptoIdentity, newOwnCapabilities: Set<ObvCapability>) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForAddingOwnCapabilities does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitialMessageForAddingOwnCapabilities does nothing in this dummy implementation")
    }
    
    public func getInitialMessageForOneToOneContactInvitationProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForOneToOneContactInvitationProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitialMessageForAddingOwnCapabilities does nothing in this dummy implementation")
    }
    
    public func getInitialMessageForDowngradingOneToOneContact(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForDowngradingOneToOneContact does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitialMessageForDowngradingOneToOneContact does nothing in this dummy implementation")
    }
    
    public func getInitialMessageForOneStatusSyncRequest(ownedIdentity: ObvCryptoIdentity, contactsToSync: Set<ObvCryptoIdentity>) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForOneStatusSyncRequest does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitialMessageForOneStatusSyncRequest does nothing in this dummy implementation")
    }
    
    public func getInitiateGroupCreationMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, ownRawPermissions: Set<String>, otherGroupMembers: Set<GroupV2.IdentityAndPermissions>, serializedGroupCoreDetails: Data, photoURL: URL?, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateGroupCreationMessageForGroupV2Protocol does nothing in this dummy implementation", log: log, type: .error)
        throw ObvProtocolManagerDummy.makeError(message: "getInitiateGroupCreationMessageForGroupV2Protocol does nothing in this dummy implementation")
    }
    
    public func getInitiateGroupUpdateMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, changeset: ObvGroupV2.Changeset, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateGroupUpdateMessageForGroupV2Protocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitiateGroupUpdateMessageForGroupV2Protocol does nothing in this dummy implementation")
    }
    
    public func getInitiateGroupLeaveMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateGroupLeaveMessageForGroupV2Protocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitiateGroupLeaveMessageForGroupV2Protocol does nothing in this dummy implementation")
    }
    
    public func getInitiateGroupReDownloadMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateGroupReDownloadMessageForGroupV2Protocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitiateGroupReDownloadMessageForGroupV2Protocol does nothing in this dummy implementation")
    }
    
    public func getInitiateInitiateGroupDisbandMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateInitiateGroupDisbandMessageForGroupV2Protocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitiateInitiateGroupDisbandMessageForGroupV2Protocol does nothing in this dummy implementation")
    }
    
    public func getInitiateBatchKeysResendMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, remoteIdentity: ObvCryptoIdentity, remoteDeviceUID: UID, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateBatchKeysResendMessageForGroupV2Protocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitiateBatchKeysResendMessageForGroupV2Protocol does nothing in this dummy implementation")
    }
    
    public func getInitiateOwnedIdentityDeletionMessage(ownedCryptoIdentityToDelete: ObvCryptoIdentity, globalOwnedIdentityDeletion: Bool) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateOwnedIdentityDeletionMessage does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitiateOwnedIdentityDeletionMessage does nothing in this dummy implementation")
    }
    
    public func prepareForOwnedIdentityDeletion(_ ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) throws {
        os_log("prepareForOwnedIdentityDeletion does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "prepareForOwnedIdentityDeletion does nothing in this dummy implementation")
    }
    
    public func prepareForOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        os_log("prepareForOwnedIdentityDeletion does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "prepareForOwnedIdentityDeletion does nothing in this dummy implementation")
    }
    
    public func getInitiateUpdateKeycloakGroupsMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, signedGroupBlobs: Set<String>, signedGroupDeletions: Set<String>, signedGroupKicks: Set<String>, keycloakCurrentTimestamp: Date, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateUpdateKeycloakGroupsMessageForGroupV2Protocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitiateUpdateKeycloakGroupsMessageForGroupV2Protocol does nothing in this dummy implementation")
    }
    
    public func getInitiateTargetedPingMessageForKeycloakGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, pendingMemberIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateTargetedPingMessageForKeycloakGroupV2Protocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitiateTargetedPingMessageForKeycloakGroupV2Protocol does nothing in this dummy implementation")
    }
    
    public func getInitiateOwnedDeviceDiscoveryMessage(ownedCryptoIdentity: ObvCrypto.ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateOwnedDeviceDiscoveryMessage does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitiateOwnedDeviceDiscoveryMessage does nothing in this dummy implementation")
    }
    
    public func executeOnQueueForProtocolOperations<ReasonForCancelType>(operation: OperationWithSpecificReasonForCancel<ReasonForCancelType>) async throws where ReasonForCancelType : LocalizedErrorWithLogType {
        os_log("executeOnQueueForProtocolOperations does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "executeOnQueueForProtocolOperations does nothing in this dummy implementation")
    }
    
    public func getOwnedIdentityKeycloakBindingMessage(ownedCryptoIdentity: ObvCryptoIdentity, keycloakState: ObvKeycloakState, keycloakUserId: String) throws -> ObvChannelProtocolMessageToSend {
        os_log("getOwnedIdentityKeycloakBindingMessage does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getOwnedIdentityKeycloakBindingMessage does nothing in this dummy implementation")
    }
    
    public func getOwnedIdentityKeycloakUnbindingMessage(ownedCryptoIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        os_log("getOwnedIdentityKeycloakUnbindingMessage does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getOwnedIdentityKeycloakUnbindingMessage does nothing in this dummy implementation")
    }
    
    public func getInitiateOwnedDeviceManagementMessage(ownedCryptoIdentity: ObvCryptoIdentity, request: ObvOwnedDeviceManagementRequest) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateOwnedDeviceManagementMessage does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitiateOwnedDeviceManagementMessage does nothing in this dummy implementation")
    }
    
    public func initiateOwnedIdentityTransferProtocolOnSourceDevice(ownedCryptoIdentity: ObvCryptoIdentity, onAvailableSessionNumber: @escaping (ObvOwnedIdentityTransferSessionNumber) -> Void, onAvailableSASExpectedOnInput: @escaping (ObvOwnedIdentityTransferSas, String, UID) -> Void, flowId: FlowIdentifier) async throws {
        os_log("initiateOwnedIdentityTransferProtocolOnSourceDevice does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "initiateOwnedIdentityTransferProtocolOnSourceDevice does nothing in this dummy implementation")
    }
    
    public func cancelAllOwnedIdentityTransferProtocols(flowId: FlowIdentifier) async throws {
        os_log("cancelAllOwnedIdentityTransferProtocols does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "cancelAllOwnedIdentityTransferProtocols does nothing in this dummy implementation")
    }
    
    public func initiateOwnedIdentityTransferProtocolOnTargetDevice(currentDeviceName: String, transferSessionNumber: ObvOwnedIdentityTransferSessionNumber, onIncorrectTransferSessionNumber: @escaping () -> Void, onAvailableSas: @escaping (UID, ObvOwnedIdentityTransferSas) -> Void, flowId: FlowIdentifier) async throws {
        os_log("initiateOwnedIdentityTransferProtocolOnTargetDevice does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "initiateOwnedIdentityTransferProtocolOnTargetDevice does nothing in this dummy implementation")
    }
    
    public func continueOwnedIdentityTransferProtocolOnUserEnteredSASOnSourceDevice(enteredSAS: ObvOwnedIdentityTransferSas, deviceToKeepActive: UID?, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID) async throws {
        os_log("continueOwnedIdentityTransferProtocolOnUserEnteredSASOnSourceDevice does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "continueOwnedIdentityTransferProtocolOnUserEnteredSASOnSourceDevice does nothing in this dummy implementation")
    }

    public func getInitiateSyncAtomMessageForSynchronizationProtocol(ownedCryptoIdentity: ObvCryptoIdentity, syncAtom: ObvSyncAtom) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateSyncAtomMessageForSynchronizationProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitiateSyncAtomMessageForSynchronizationProtocol does nothing in this dummy implementation")
    }
    
    public func sendTriggerSyncSnapshotMessageToAllExistingSynchronizationProtocolInstances(within obvContext: OlvidUtils.ObvContext) throws {
        os_log("sendTriggerSyncSnapshotMessageToAllExistingSynchronizationProtocolInstances does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "sendTriggerSyncSnapshotMessageToAllExistingSynchronizationProtocolInstances does nothing in this dummy implementation")
    }

    public func getInitiateSyncSnapshotMessageForSynchronizationProtocol(ownedCryptoIdentity: ObvCryptoIdentity, currentDeviceUid: UID, otherOwnedDeviceUid: UID) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitiateSyncSnapshotMessageForSynchronizationProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitiateSyncSnapshotMessageForSynchronizationProtocol does nothing in this dummy implementation")
    }
    
    public func getTriggerSyncSnapshotMessageForSynchronizationProtocol(ownedCryptoIdentity: ObvCryptoIdentity, currentDeviceUid: UID, otherOwnedDeviceUid: UID, forceSendSnapshot: Bool) throws -> ObvChannelProtocolMessageToSend {
        os_log("getTriggerSyncSnapshotMessageForSynchronizationProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getTriggerSyncSnapshotMessageForSynchronizationProtocol does nothing in this dummy implementation")
    }
    
    public func getInitialMessageForDownloadGroupV2PhotoProtocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, serverPhotoInfo: GroupV2.ServerPhotoInfo) throws -> ObvChannelProtocolMessageToSend {
        os_log("getInitialMessageForDownloadGroupV2PhotoProtocol does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "getInitialMessageForDownloadGroupV2PhotoProtocol does nothing in this dummy implementation")
    }

    public func appIsShowingSasAndExpectingEndOfProtocol(protocolInstanceUID: UID, onSyncSnapshotReception: @escaping () -> Void, onSuccessfulTransfer: @escaping (ObvCryptoId, Error?) -> Void) async {
        os_log("appIsShowingSasAndExpectingEndOfProtocol does nothing in this dummy implementation", log: log, type: .error)
    }
    
    
    
    
    // MARK: - Implementing ObvManager
    
    public let requiredDelegates = [ObvEngineDelegateType]()
    
    public func fulfill(requiredDelegate: AnyObject, forDelegateType: ObvEngineDelegateType) throws {}
    
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {}

}

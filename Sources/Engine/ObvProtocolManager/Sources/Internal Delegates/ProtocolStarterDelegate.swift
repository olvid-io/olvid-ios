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
import OlvidUtils
import ObvMetaManager
import ObvCrypto
import ObvTypes

protocol ProtocolStarterDelegate {
    
    func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError)
    
    func getInitialMessageForTrustEstablishmentProtocol(of: ObvCryptoIdentity, withFullDisplayName: String, forOwnedIdentity: ObvCryptoIdentity, withOwnedIdentityCoreDetails: ObvIdentityCoreDetails) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForContactMutualIntroductionProtocol(of identity1: ObvCryptoIdentity, with identity2: ObvCryptoIdentity, byOwnedIdentity ownedIdentity: ObvCryptoIdentity, usingProtocolInstanceUid protocolInstanceUid: UID) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForChannelCreationWithContactDeviceProtocol(betweenTheCurrentDeviceOfOwnedIdentity: ObvCryptoIdentity, andTheDeviceUid: UID, ofTheContactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForChannelCreationWithOwnedDeviceProtocol(ownedIdentity: ObvCryptoIdentity, remoteDeviceUid: UID) throws -> ObvChannelProtocolMessageToSend

    func getInitiateGroupCreationMessageForGroupManagementProtocol(groupCoreDetails: ObvGroupCoreDetails, photoURL: URL?, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, ownedIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend

    func getDisbandGroupMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend

    func getAddGroupMembersMessageForAddingMembersToContactGroupOwnedUsingGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, newGroupMembers: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForIdentityDetailsPublicationProtocol(ownedIdentity: ObvCryptoIdentity, publishedIdentityDetailsVersion: Int) throws -> ObvChannelProtocolMessageToSend
    
    func getRemoveGroupMembersMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, removedGroupMembers: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend

    func getRemoveGroupMembersMessageForStartingGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, removedGroupMembers: Set<ObvCryptoIdentity>, simulateReceivedMessage: Bool, within obvContext: ObvContext) throws -> GroupManagementProtocol.RemoveGroupMembersMessage
    
    func getOwnedGroupMembersChangedTriggerMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend

    func getLeaveGroupJoinedMessageForGroupManagementProtocol(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend
    
    func getLeaveGroupJoinedMessageForStartingGroupManagementProtocol(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, simulateReceivedMessage: Bool, within obvContext: ObvContext) throws -> GroupManagementProtocol.LeaveGroupJoinedMessage

    func getInitiateAddKeycloakContactMessageForKeycloakContactAdditionProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentityToAdd: ObvCryptoIdentity, signedContactDetails: String) throws -> ObvChannelProtocolMessageToSend

    func getInitiateGroupMembersQueryMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend

    func getTriggerReinviteMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, memberIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForContactDeviceDiscoveryProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForDownloadIdentityPhotoChildProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactIdentityDetailsElements: IdentityDetailsElements) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForDownloadGroupPhotoChildProtocol(ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation) throws -> ObvChannelProtocolMessageToSend
    
    func getInitialMessageForTrustEstablishmentWithMutualScanProtocol(ownedIdentity: ObvCryptoIdentity, remoteIdentity: ObvCryptoIdentity, signature: Data) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForAddingOwnCapabilities(ownedIdentity: ObvCryptoIdentity, newOwnCapabilities: Set<ObvCapability>) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForOneToOneContactInvitationProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend
    
    func getInitialMessageForOneStatusSyncRequest(ownedIdentity: ObvCryptoIdentity, contactsToSync: Set<ObvCryptoIdentity>) throws -> ObvChannelProtocolMessageToSend

    // MARK: - Groups V2

    func getInitiateGroupCreationMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, ownRawPermissions: Set<String>, otherGroupMembers: Set<GroupV2.IdentityAndPermissions>, serializedGroupCoreDetails: Data, photoURL: URL?, serializedGroupType: Data) throws -> ObvChannelProtocolMessageToSend

    func getInitiateGroupUpdateMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, changeset: ObvGroupV2.Changeset) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForDownloadGroupV2PhotoProtocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, serverPhotoInfo: GroupV2.ServerPhotoInfo) throws -> ObvChannelProtocolMessageToSend

    func getInitiateGroupLeaveMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier) throws -> ObvChannelProtocolMessageToSend
    
    func getInitiateGroupLeaveMessageForStartingGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, simulateReceivedMessage: Bool) throws -> GroupV2Protocol.InitiateGroupLeaveMessage
    
    func getInitiateGroupReDownloadMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier) throws -> ObvChannelProtocolMessageToSend

    func getInitiateInitiateGroupDisbandMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier) throws -> ObvChannelProtocolMessageToSend
    
    func getInitiateInitiateGroupDisbandMessageForStartingGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, simulateReceivedMessage: Bool) throws -> GroupV2Protocol.InitiateGroupDisbandMessage

    func getInitiateBatchKeysResendMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, remoteIdentity: ObvCryptoIdentity, remoteDeviceUID: UID, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend

    // MARK: - Keycloak pushed groups
    
    func getInitiateUpdateKeycloakGroupsMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, signedGroupBlobs: Set<String>, signedGroupDeletions: Set<String>, signedGroupKicks: Set<String>, keycloakCurrentTimestamp: Date) throws -> ObvChannelProtocolMessageToSend
    
    func getInitiateTargetedPingMessageForKeycloakGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, pendingMemberIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend

    // MARK: - Owned identities
    
    func getInitiateOwnedIdentityDeletionMessage(ownedCryptoIdentityToDelete: ObvCryptoIdentity, globalOwnedIdentityDeletion: Bool) throws -> ObvChannelProtocolMessageToSend
    
    func getInitiateOwnedDeviceDiscoveryMessage(ownedCryptoIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend
    
    func getInitiateOwnedDeviceManagementMessage(ownedCryptoIdentity: ObvCryptoIdentity, request: ObvOwnedDeviceManagementRequest) throws -> ObvChannelProtocolMessageToSend
    
    // func getInitiateTransferOnSourceDeviceMessageForOwnedIdentityTransferProtocol(ownedCryptoIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend
    
    // MARK: - Contact Device Management protocol
    
    func getInitiateContactDeletionMessageForContactManagementProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentityToDelete: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForDowngradingOneToOneContact(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend
    
    // MARK: - Keycloak binding and unbinding
    
    func getOwnedIdentityKeycloakBindingMessage(ownedCryptoIdentity: ObvCryptoIdentity, keycloakState: ObvKeycloakState, keycloakUserId: String) throws -> ObvChannelProtocolMessageToSend

    func getOwnedIdentityKeycloakUnbindingMessage(ownedCryptoIdentity: ObvCryptoIdentity, isUnbindRequestByUser: Bool) throws -> ObvChannelProtocolMessageToSend

    // MARK: - SynchronizationProtocol
    
    func getInitiateSyncAtomMessageForSynchronizationProtocol(ownedCryptoIdentity: ObvCryptoIdentity, syncAtom: ObvSyncAtom) throws -> ObvChannelProtocolMessageToSend

    // func getTriggerSyncSnapshotMessageForSynchronizationProtocol(ownedCryptoIdentity: ObvCryptoIdentity, currentDeviceUid: UID, otherOwnedDeviceUid: UID, forceSendSnapshot: Bool) throws -> ObvChannelProtocolMessageToSend

    // func getInitiateSyncSnapshotMessageForSynchronizationProtocol(ownedCryptoIdentity: ObvCryptoIdentity, currentDeviceUid: UID, otherOwnedDeviceUid: UID) throws -> ObvChannelProtocolMessageToSend

    // MARK: - Owned identity transfer protocol

    /// Called by the engine in order to start an owned identity transfer protocol on the source device.
    /// - Parameters:
    ///   - ownedCryptoIdentity: The crypto identity of the owned identity.
    ///   - onAvailableSessionNumber: This block will be called by the protocol manager as soon as the session number is available, passing it as a parameter. Since getting this session number requires a network interaction with the transfer server, this block may take a "long" time before being called.
    ///   - flowId: The flow identifier.
    func initiateOwnedIdentityTransferProtocolOnSourceDevice(ownedCryptoIdentity: ObvCryptoIdentity, onAvailableSessionNumber: @MainActor @escaping (ObvOwnedIdentityTransferSessionNumber) -> Void, onAvailableSASExpectedOnInput: @MainActor @escaping (ObvOwnedIdentityTransferSas, String, UID) -> Void, flowId: FlowIdentifier) async throws

    func initiateOwnedIdentityTransferProtocolOnTargetDevice(currentDeviceName: String, transferSessionNumber: ObvOwnedIdentityTransferSessionNumber, onIncorrectTransferSessionNumber: @escaping () -> Void, onAvailableSas: @escaping (UID, ObvOwnedIdentityTransferSas) -> Void, flowId: FlowIdentifier) async throws

    
    func appIsShowingSasAndExpectingEndOfProtocol(protocolInstanceUID: UID, onSyncSnapshotReception: @escaping () -> Void, onSuccessfulTransfer: @escaping (ObvCryptoId, Error?) -> Void, onKeycloakAuthenticationNeeded: @escaping (ObvCryptoId, ObvKeycloakConfiguration, ObvKeycloakTransferProofElements) -> Void) async

    
    func continueOwnedIdentityTransferProtocolOnUserEnteredSASOnSourceDevice(enteredSAS: ObvOwnedIdentityTransferSas, isTransferRestricted: Bool, deviceToKeepActive: UID?, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID, snapshotSentToTargetDevice: @escaping () -> Void) async throws

    func cancelAllOwnedIdentityTransferProtocols(flowId: FlowIdentifier) async throws

    func continueOwnedIdentityTransferProtocolOnUserProvidesProofOfAuthenticationOnKeycloakServer(ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID, proof: ObvKeycloakTransferProofAndAuthState) async throws
    
}

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
import OlvidUtils
import ObvMetaManager
import ObvCrypto
import ObvTypes

protocol ProtocolStarterDelegate {
    
    func startDeviceDiscoveryProtocolOfContactIdentity(_: ObvCryptoIdentity, forOwnedIdentity: ObvCryptoIdentity, within: FlowIdentifier) throws

    func getInitialMessageForTrustEstablishmentProtocol(of: ObvCryptoIdentity, withFullDisplayName: String, forOwnedIdentity: ObvCryptoIdentity, withOwnedIdentityCoreDetails: ObvIdentityCoreDetails, usingProtocolInstanceUid: UID) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForContactMutualIntroductionProtocol(of: ObvCryptoIdentity, withIdentityCoreDetails: ObvIdentityCoreDetails, with: ObvCryptoIdentity, withOtherIdentityCoreDetails: ObvIdentityCoreDetails, byOwnedIdentity: ObvCryptoIdentity, usingProtocolInstanceUid: UID) throws -> ObvChannelProtocolMessageToSend

    func startChannelCreationWithContactDeviceProtocolBetweenTheCurrentDeviceOf(_: ObvCryptoIdentity, andTheDeviceUid: UID, ofTheContactIdentity: ObvCryptoIdentity, within: FlowIdentifier) throws
    
    func getInitialMessageForChannelCreationWithContactDeviceProtocol(betweenTheCurrentDeviceOfOwnedIdentity: ObvCryptoIdentity, andTheDeviceUid: UID, ofTheContactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend

    func tryToObserveIdentityNotifications()

    func getInitiateGroupCreationMessageForGroupManagementProtocol(groupCoreDetails: ObvGroupCoreDetails, photoURL: URL?, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, ownedIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend

    func getAddGroupMembersMessageForAddingMembersToContactGroupOwnedUsingGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, newGroupMembers: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForIdentityDetailsPublicationProtocol(ownedIdentity: ObvCryptoIdentity, publishedIdentityDetailsVersion: Int) throws -> ObvChannelProtocolMessageToSend
    
    func getRemoveGroupMembersMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, removedGroupMembers: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend

    func getRemoveGroupMembersMessageForStartingGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, removedGroupMembers: Set<ObvCryptoIdentity>, simulateReceivedMessage: Bool, within obvContext: ObvContext) throws -> GroupManagementProtocol.RemoveGroupMembersMessage
    
    func getOwnedGroupMembersChangedTriggerMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend

    func getLeaveGroupJoinedMessageForGroupManagementProtocol(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend
    
    func getLeaveGroupJoinedMessageForStartingGroupManagementProtocol(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, simulateReceivedMessage: Bool, within obvContext: ObvContext) throws -> GroupManagementProtocol.LeaveGroupJoinedMessage

    func getInitiateContactDeletionMessageForContactManagementProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentityToDelete: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend

    func getInitiateAddKeycloakContactMessageForKeycloakContactAdditionProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentityToAdd: ObvCryptoIdentity, signedContactDetails: String) throws -> ObvChannelProtocolMessageToSend

    func getInitiateGroupMembersQueryMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend

    func getTriggerReinviteMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, memberIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForDeviceDiscoveryForContactIdentityProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForDownloadIdentityPhotoChildProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactIdentityDetailsElements: IdentityDetailsElements) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForDownloadGroupPhotoChildProtocol(ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation) throws -> ObvChannelProtocolMessageToSend
    
    func getInitialMessageForTrustEstablishmentWithMutualScanProtocol(ownedIdentity: ObvCryptoIdentity, remoteIdentity: ObvCryptoIdentity, signature: Data) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForAddingOwnCapabilities(ownedIdentity: ObvCryptoIdentity, newOwnCapabilities: Set<ObvCapability>) throws -> ObvChannelProtocolMessageToSend

    func getInitialMessageForOneToOneContactInvitationProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend
    
    func getInitialMessageForDowngradingOneToOneContact(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend
    
    func getInitialMessageForOneStatusSyncRequest(ownedIdentity: ObvCryptoIdentity, contactsToSync: Set<ObvCryptoIdentity>) throws -> ObvChannelProtocolMessageToSend

    // MARK: - Groups V2

    func getInitiateGroupCreationMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, ownRawPermissions: Set<String>, otherGroupMembers: Set<GroupV2.IdentityAndPermissions>, serializedGroupCoreDetails: Data, photoURL: URL?, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend

    func getInitiateGroupUpdateMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, changeset: ObvGroupV2.Changeset, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend

    func getInitiateGroupLeaveMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend
    
    func getInitiateGroupLeaveMessageForStartingGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, simulateReceivedMessage: Bool, flowId: FlowIdentifier) throws -> GroupV2Protocol.InitiateGroupLeaveMessage
    
    func getInitiateGroupReDownloadMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend

    func getInitiateInitiateGroupDisbandMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend
    
    func getInitiateInitiateGroupDisbandMessageForStartingGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, simulateReceivedMessage: Bool, flowId: FlowIdentifier) throws -> GroupV2Protocol.InitiateGroupDisbandMessage

    func getInitiateBatchKeysResendMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactDeviceUID: UID, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend

    // MARK: - Keycloak pushed groups
    
    func getInitiateUpdateKeycloakGroupsMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, signedGroupBlobs: Set<String>, signedGroupDeletions: Set<String>, signedGroupKicks: Set<String>, keycloakCurrentTimestamp: Date, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend
    
    func getInitiateTargetedPingMessageForKeycloakGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, pendingMemberIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend

    // MARK: - Owned identities
    
    func getInitiateOwnedIdentityDeletionMessage(ownedCryptoIdentityToDelete: ObvCryptoIdentity, notifyContacts: Bool, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend
    
}

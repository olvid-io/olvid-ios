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
import CoreData
import ObvEngine
import ObvCrypto
import ObvTypes
import UI_CircledInitialsView_CircledInitialsConfiguration

fileprivate struct OptionalWrapper<T> {
	let value: T?
	public init() {
		self.value = nil
	}
	public init(_ value: T?) {
		self.value = value
	}
}

public enum ObvMessengerCoreDataNotification {
	case newDraftToSend(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>)
	case draftWasSent(persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>)
	case persistedMessageHasNewMetadata(persistedMessageObjectID: NSManagedObjectID)
	case newOrUpdatedPersistedInvitation(concernedOwnedIdentityIsHidden: Bool, obvDialog: ObvDialog, persistedInvitationUUID: UUID)
	case persistedContactWasInserted(contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>)
	case persistedContactWasDeleted(objectID: NSManagedObjectID, identity: Data)
	case persistedContactHasNewCustomDisplayName(contactCryptoId: ObvCryptoId)
	case persistedContactHasNewStatus(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case persistedContactIsActiveChanged(contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>)
	case newMessageExpiration(expirationDate: Date)
	case persistedMessageReactionReceivedWasDeletedOnSentMessage(messagePermanentID: ObvManagedObjectPermanentID<PersistedMessageSent>, contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>)
	case persistedMessageReactionReceivedWasInsertedOrUpdated(objectID: TypeSafeManagedObjectID<PersistedMessageReactionReceived>)
	case persistedContactGroupHasUpdatedContactIdentities(persistedContactGroupObjectID: NSManagedObjectID, insertedContacts: Set<PersistedObvContactIdentity>, removedContacts: Set<PersistedObvContactIdentity>)
	case aReadOncePersistedMessageSentWasSent(persistedMessageSentPermanentID: ObvManagedObjectPermanentID<PersistedMessageSent>, persistedDiscussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>)
	case newPersistedObvContactDevice(contactDeviceObjectID: NSManagedObjectID, contactCryptoId: ObvCryptoId)
	case deletedPersistedObvContactDevice(contactCryptoId: ObvCryptoId)
	case persistedDiscussionHasNewTitle(objectID: TypeSafeManagedObjectID<PersistedDiscussion>, title: String)
	case persistedDiscussionWasDeleted(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, objectIDOfDeletedDiscussion: TypeSafeManagedObjectID<PersistedDiscussion>)
	case persistedDiscussionWasInserted(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, objectID: TypeSafeManagedObjectID<PersistedDiscussion>)
	case newPersistedObvOwnedIdentity(ownedCryptoId: ObvCryptoId, isActive: Bool)
	case ownedIdentityWasReactivated(ownedIdentityObjectID: NSManagedObjectID)
	case ownedIdentityWasDeactivated(ownedIdentityObjectID: NSManagedObjectID)
	case anOldDiscussionSharedConfigurationWasReceived(persistedDiscussionObjectID: NSManagedObjectID)
	case persistedMessageSystemWasDeleted(objectID: NSManagedObjectID, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
	case persistedMessagesWereDeleted(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>)
	case persistedMessagesWereWiped(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>)
	case persistedDiscussionStatusChanged(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, newStatus: PersistedDiscussion.Status)
	case persistedGroupV2UpdateIsFinished(objectID: TypeSafeManagedObjectID<PersistedGroupV2>)
	case persistedGroupV2WasDeleted(objectID: TypeSafeManagedObjectID<PersistedGroupV2>)
	case aPersistedGroupV2MemberChangedFromPendingToNonPending(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>)
	case ownedCircledInitialsConfigurationDidChange(ownedIdentityPermanentID: ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>, ownedCryptoId: ObvCryptoId, newOwnedCircledInitialsConfiguration: CircledInitialsConfiguration)
	case persistedObvOwnedIdentityWasDeleted
	case ownedIdentityHiddenStatusChanged(ownedCryptoId: ObvCryptoId, isHidden: Bool)
	case badgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity(ownedCryptoId: ObvCryptoId)
	case displayedContactGroupWasJustCreated(permanentID: ObvManagedObjectPermanentID<DisplayedContactGroup>)
	case groupV2TrustedDetailsShouldBeReplacedByPublishedDetails(ownCryptoId: ObvCryptoId, groupIdentifier: Data)
	case receivedFyleJoinHasBeenMarkAsOpened(receivedFyleJoinID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>)
	case aDeliveredReturnReceiptShouldBeSentForAReceivedFyleMessageJoinWithStatus(returnReceipt: ReturnReceiptJSON, contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int)
	case persistedMessageReceivedWasDeleted(objectID: NSManagedObjectID, messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, sortIndex: Double, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
	case persistedMessageReceivedWasRead(persistedMessageReceivedObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>)
	case aDeliveredReturnReceiptShouldBeSentForPersistedMessageReceived(returnReceipt: ReturnReceiptJSON, contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data)
	case theBodyOfPersistedMessageReceivedDidChange(persistedMessageReceivedObjectID: NSManagedObjectID)
	case persistedDiscussionWasArchived(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>)
	case persistedContactWasUpdated(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>)
	case fyleMessageJoinWithStatusWasInserted(fyleMessageJoinObjectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>)
	case fyleMessageJoinWithStatusWasUpdated(fyleMessageJoinObjectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>)
	case discussionLocalConfigurationHasBeenUpdated(newValue: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>)

	private enum Name {
		case newDraftToSend
		case draftWasSent
		case persistedMessageHasNewMetadata
		case newOrUpdatedPersistedInvitation
		case persistedContactWasInserted
		case persistedContactWasDeleted
		case persistedContactHasNewCustomDisplayName
		case persistedContactHasNewStatus
		case persistedContactIsActiveChanged
		case newMessageExpiration
		case persistedMessageReactionReceivedWasDeletedOnSentMessage
		case persistedMessageReactionReceivedWasInsertedOrUpdated
		case persistedContactGroupHasUpdatedContactIdentities
		case aReadOncePersistedMessageSentWasSent
		case newPersistedObvContactDevice
		case deletedPersistedObvContactDevice
		case persistedDiscussionHasNewTitle
		case persistedDiscussionWasDeleted
		case persistedDiscussionWasInserted
		case newPersistedObvOwnedIdentity
		case ownedIdentityWasReactivated
		case ownedIdentityWasDeactivated
		case anOldDiscussionSharedConfigurationWasReceived
		case persistedMessageSystemWasDeleted
		case persistedMessagesWereDeleted
		case persistedMessagesWereWiped
		case persistedDiscussionStatusChanged
		case persistedGroupV2UpdateIsFinished
		case persistedGroupV2WasDeleted
		case aPersistedGroupV2MemberChangedFromPendingToNonPending
		case ownedCircledInitialsConfigurationDidChange
		case persistedObvOwnedIdentityWasDeleted
		case ownedIdentityHiddenStatusChanged
		case badgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity
		case displayedContactGroupWasJustCreated
		case groupV2TrustedDetailsShouldBeReplacedByPublishedDetails
		case receivedFyleJoinHasBeenMarkAsOpened
		case aDeliveredReturnReceiptShouldBeSentForAReceivedFyleMessageJoinWithStatus
		case persistedMessageReceivedWasDeleted
		case persistedMessageReceivedWasRead
		case aDeliveredReturnReceiptShouldBeSentForPersistedMessageReceived
		case theBodyOfPersistedMessageReceivedDidChange
		case persistedDiscussionWasArchived
		case persistedContactWasUpdated
		case fyleMessageJoinWithStatusWasInserted
		case fyleMessageJoinWithStatusWasUpdated
		case discussionLocalConfigurationHasBeenUpdated

		private var namePrefix: String { String(describing: ObvMessengerCoreDataNotification.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ObvMessengerCoreDataNotification) -> NSNotification.Name {
			switch notification {
			case .newDraftToSend: return Name.newDraftToSend.name
			case .draftWasSent: return Name.draftWasSent.name
			case .persistedMessageHasNewMetadata: return Name.persistedMessageHasNewMetadata.name
			case .newOrUpdatedPersistedInvitation: return Name.newOrUpdatedPersistedInvitation.name
			case .persistedContactWasInserted: return Name.persistedContactWasInserted.name
			case .persistedContactWasDeleted: return Name.persistedContactWasDeleted.name
			case .persistedContactHasNewCustomDisplayName: return Name.persistedContactHasNewCustomDisplayName.name
			case .persistedContactHasNewStatus: return Name.persistedContactHasNewStatus.name
			case .persistedContactIsActiveChanged: return Name.persistedContactIsActiveChanged.name
			case .newMessageExpiration: return Name.newMessageExpiration.name
			case .persistedMessageReactionReceivedWasDeletedOnSentMessage: return Name.persistedMessageReactionReceivedWasDeletedOnSentMessage.name
			case .persistedMessageReactionReceivedWasInsertedOrUpdated: return Name.persistedMessageReactionReceivedWasInsertedOrUpdated.name
			case .persistedContactGroupHasUpdatedContactIdentities: return Name.persistedContactGroupHasUpdatedContactIdentities.name
			case .aReadOncePersistedMessageSentWasSent: return Name.aReadOncePersistedMessageSentWasSent.name
			case .newPersistedObvContactDevice: return Name.newPersistedObvContactDevice.name
			case .deletedPersistedObvContactDevice: return Name.deletedPersistedObvContactDevice.name
			case .persistedDiscussionHasNewTitle: return Name.persistedDiscussionHasNewTitle.name
			case .persistedDiscussionWasDeleted: return Name.persistedDiscussionWasDeleted.name
			case .persistedDiscussionWasInserted: return Name.persistedDiscussionWasInserted.name
			case .newPersistedObvOwnedIdentity: return Name.newPersistedObvOwnedIdentity.name
			case .ownedIdentityWasReactivated: return Name.ownedIdentityWasReactivated.name
			case .ownedIdentityWasDeactivated: return Name.ownedIdentityWasDeactivated.name
			case .anOldDiscussionSharedConfigurationWasReceived: return Name.anOldDiscussionSharedConfigurationWasReceived.name
			case .persistedMessageSystemWasDeleted: return Name.persistedMessageSystemWasDeleted.name
			case .persistedMessagesWereDeleted: return Name.persistedMessagesWereDeleted.name
			case .persistedMessagesWereWiped: return Name.persistedMessagesWereWiped.name
			case .persistedDiscussionStatusChanged: return Name.persistedDiscussionStatusChanged.name
			case .persistedGroupV2UpdateIsFinished: return Name.persistedGroupV2UpdateIsFinished.name
			case .persistedGroupV2WasDeleted: return Name.persistedGroupV2WasDeleted.name
			case .aPersistedGroupV2MemberChangedFromPendingToNonPending: return Name.aPersistedGroupV2MemberChangedFromPendingToNonPending.name
			case .ownedCircledInitialsConfigurationDidChange: return Name.ownedCircledInitialsConfigurationDidChange.name
			case .persistedObvOwnedIdentityWasDeleted: return Name.persistedObvOwnedIdentityWasDeleted.name
			case .ownedIdentityHiddenStatusChanged: return Name.ownedIdentityHiddenStatusChanged.name
			case .badgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity: return Name.badgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity.name
			case .displayedContactGroupWasJustCreated: return Name.displayedContactGroupWasJustCreated.name
			case .groupV2TrustedDetailsShouldBeReplacedByPublishedDetails: return Name.groupV2TrustedDetailsShouldBeReplacedByPublishedDetails.name
			case .receivedFyleJoinHasBeenMarkAsOpened: return Name.receivedFyleJoinHasBeenMarkAsOpened.name
			case .aDeliveredReturnReceiptShouldBeSentForAReceivedFyleMessageJoinWithStatus: return Name.aDeliveredReturnReceiptShouldBeSentForAReceivedFyleMessageJoinWithStatus.name
			case .persistedMessageReceivedWasDeleted: return Name.persistedMessageReceivedWasDeleted.name
			case .persistedMessageReceivedWasRead: return Name.persistedMessageReceivedWasRead.name
			case .aDeliveredReturnReceiptShouldBeSentForPersistedMessageReceived: return Name.aDeliveredReturnReceiptShouldBeSentForPersistedMessageReceived.name
			case .theBodyOfPersistedMessageReceivedDidChange: return Name.theBodyOfPersistedMessageReceivedDidChange.name
			case .persistedDiscussionWasArchived: return Name.persistedDiscussionWasArchived.name
			case .persistedContactWasUpdated: return Name.persistedContactWasUpdated.name
			case .fyleMessageJoinWithStatusWasInserted: return Name.fyleMessageJoinWithStatusWasInserted.name
			case .fyleMessageJoinWithStatusWasUpdated: return Name.fyleMessageJoinWithStatusWasUpdated.name
			case .discussionLocalConfigurationHasBeenUpdated: return Name.discussionLocalConfigurationHasBeenUpdated.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .newDraftToSend(draftPermanentID: let draftPermanentID):
			info = [
				"draftPermanentID": draftPermanentID,
			]
		case .draftWasSent(persistedDraftObjectID: let persistedDraftObjectID):
			info = [
				"persistedDraftObjectID": persistedDraftObjectID,
			]
		case .persistedMessageHasNewMetadata(persistedMessageObjectID: let persistedMessageObjectID):
			info = [
				"persistedMessageObjectID": persistedMessageObjectID,
			]
		case .newOrUpdatedPersistedInvitation(concernedOwnedIdentityIsHidden: let concernedOwnedIdentityIsHidden, obvDialog: let obvDialog, persistedInvitationUUID: let persistedInvitationUUID):
			info = [
				"concernedOwnedIdentityIsHidden": concernedOwnedIdentityIsHidden,
				"obvDialog": obvDialog,
				"persistedInvitationUUID": persistedInvitationUUID,
			]
		case .persistedContactWasInserted(contactPermanentID: let contactPermanentID):
			info = [
				"contactPermanentID": contactPermanentID,
			]
		case .persistedContactWasDeleted(objectID: let objectID, identity: let identity):
			info = [
				"objectID": objectID,
				"identity": identity,
			]
		case .persistedContactHasNewCustomDisplayName(contactCryptoId: let contactCryptoId):
			info = [
				"contactCryptoId": contactCryptoId,
			]
		case .persistedContactHasNewStatus(contactCryptoId: let contactCryptoId, ownedCryptoId: let ownedCryptoId):
			info = [
				"contactCryptoId": contactCryptoId,
				"ownedCryptoId": ownedCryptoId,
			]
		case .persistedContactIsActiveChanged(contactID: let contactID):
			info = [
				"contactID": contactID,
			]
		case .newMessageExpiration(expirationDate: let expirationDate):
			info = [
				"expirationDate": expirationDate,
			]
		case .persistedMessageReactionReceivedWasDeletedOnSentMessage(messagePermanentID: let messagePermanentID, contactPermanentID: let contactPermanentID):
			info = [
				"messagePermanentID": messagePermanentID,
				"contactPermanentID": contactPermanentID,
			]
		case .persistedMessageReactionReceivedWasInsertedOrUpdated(objectID: let objectID):
			info = [
				"objectID": objectID,
			]
		case .persistedContactGroupHasUpdatedContactIdentities(persistedContactGroupObjectID: let persistedContactGroupObjectID, insertedContacts: let insertedContacts, removedContacts: let removedContacts):
			info = [
				"persistedContactGroupObjectID": persistedContactGroupObjectID,
				"insertedContacts": insertedContacts,
				"removedContacts": removedContacts,
			]
		case .aReadOncePersistedMessageSentWasSent(persistedMessageSentPermanentID: let persistedMessageSentPermanentID, persistedDiscussionPermanentID: let persistedDiscussionPermanentID):
			info = [
				"persistedMessageSentPermanentID": persistedMessageSentPermanentID,
				"persistedDiscussionPermanentID": persistedDiscussionPermanentID,
			]
		case .newPersistedObvContactDevice(contactDeviceObjectID: let contactDeviceObjectID, contactCryptoId: let contactCryptoId):
			info = [
				"contactDeviceObjectID": contactDeviceObjectID,
				"contactCryptoId": contactCryptoId,
			]
		case .deletedPersistedObvContactDevice(contactCryptoId: let contactCryptoId):
			info = [
				"contactCryptoId": contactCryptoId,
			]
		case .persistedDiscussionHasNewTitle(objectID: let objectID, title: let title):
			info = [
				"objectID": objectID,
				"title": title,
			]
		case .persistedDiscussionWasDeleted(discussionPermanentID: let discussionPermanentID, objectIDOfDeletedDiscussion: let objectIDOfDeletedDiscussion):
			info = [
				"discussionPermanentID": discussionPermanentID,
				"objectIDOfDeletedDiscussion": objectIDOfDeletedDiscussion,
			]
		case .persistedDiscussionWasInserted(discussionPermanentID: let discussionPermanentID, objectID: let objectID):
			info = [
				"discussionPermanentID": discussionPermanentID,
				"objectID": objectID,
			]
		case .newPersistedObvOwnedIdentity(ownedCryptoId: let ownedCryptoId, isActive: let isActive):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"isActive": isActive,
			]
		case .ownedIdentityWasReactivated(ownedIdentityObjectID: let ownedIdentityObjectID):
			info = [
				"ownedIdentityObjectID": ownedIdentityObjectID,
			]
		case .ownedIdentityWasDeactivated(ownedIdentityObjectID: let ownedIdentityObjectID):
			info = [
				"ownedIdentityObjectID": ownedIdentityObjectID,
			]
		case .anOldDiscussionSharedConfigurationWasReceived(persistedDiscussionObjectID: let persistedDiscussionObjectID):
			info = [
				"persistedDiscussionObjectID": persistedDiscussionObjectID,
			]
		case .persistedMessageSystemWasDeleted(objectID: let objectID, discussionObjectID: let discussionObjectID):
			info = [
				"objectID": objectID,
				"discussionObjectID": discussionObjectID,
			]
		case .persistedMessagesWereDeleted(discussionPermanentID: let discussionPermanentID, messagePermanentIDs: let messagePermanentIDs):
			info = [
				"discussionPermanentID": discussionPermanentID,
				"messagePermanentIDs": messagePermanentIDs,
			]
		case .persistedMessagesWereWiped(discussionPermanentID: let discussionPermanentID, messagePermanentIDs: let messagePermanentIDs):
			info = [
				"discussionPermanentID": discussionPermanentID,
				"messagePermanentIDs": messagePermanentIDs,
			]
		case .persistedDiscussionStatusChanged(discussionPermanentID: let discussionPermanentID, newStatus: let newStatus):
			info = [
				"discussionPermanentID": discussionPermanentID,
				"newStatus": newStatus,
			]
		case .persistedGroupV2UpdateIsFinished(objectID: let objectID):
			info = [
				"objectID": objectID,
			]
		case .persistedGroupV2WasDeleted(objectID: let objectID):
			info = [
				"objectID": objectID,
			]
		case .aPersistedGroupV2MemberChangedFromPendingToNonPending(contactObjectID: let contactObjectID):
			info = [
				"contactObjectID": contactObjectID,
			]
		case .ownedCircledInitialsConfigurationDidChange(ownedIdentityPermanentID: let ownedIdentityPermanentID, ownedCryptoId: let ownedCryptoId, newOwnedCircledInitialsConfiguration: let newOwnedCircledInitialsConfiguration):
			info = [
				"ownedIdentityPermanentID": ownedIdentityPermanentID,
				"ownedCryptoId": ownedCryptoId,
				"newOwnedCircledInitialsConfiguration": newOwnedCircledInitialsConfiguration,
			]
		case .persistedObvOwnedIdentityWasDeleted:
			info = nil
		case .ownedIdentityHiddenStatusChanged(ownedCryptoId: let ownedCryptoId, isHidden: let isHidden):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"isHidden": isHidden,
			]
		case .badgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .displayedContactGroupWasJustCreated(permanentID: let permanentID):
			info = [
				"permanentID": permanentID,
			]
		case .groupV2TrustedDetailsShouldBeReplacedByPublishedDetails(ownCryptoId: let ownCryptoId, groupIdentifier: let groupIdentifier):
			info = [
				"ownCryptoId": ownCryptoId,
				"groupIdentifier": groupIdentifier,
			]
		case .receivedFyleJoinHasBeenMarkAsOpened(receivedFyleJoinID: let receivedFyleJoinID):
			info = [
				"receivedFyleJoinID": receivedFyleJoinID,
			]
		case .aDeliveredReturnReceiptShouldBeSentForAReceivedFyleMessageJoinWithStatus(returnReceipt: let returnReceipt, contactCryptoId: let contactCryptoId, ownedCryptoId: let ownedCryptoId, messageIdentifierFromEngine: let messageIdentifierFromEngine, attachmentNumber: let attachmentNumber):
			info = [
				"returnReceipt": returnReceipt,
				"contactCryptoId": contactCryptoId,
				"ownedCryptoId": ownedCryptoId,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"attachmentNumber": attachmentNumber,
			]
		case .persistedMessageReceivedWasDeleted(objectID: let objectID, messageIdentifierFromEngine: let messageIdentifierFromEngine, ownedCryptoId: let ownedCryptoId, sortIndex: let sortIndex, discussionObjectID: let discussionObjectID):
			info = [
				"objectID": objectID,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"ownedCryptoId": ownedCryptoId,
				"sortIndex": sortIndex,
				"discussionObjectID": discussionObjectID,
			]
		case .persistedMessageReceivedWasRead(persistedMessageReceivedObjectID: let persistedMessageReceivedObjectID):
			info = [
				"persistedMessageReceivedObjectID": persistedMessageReceivedObjectID,
			]
		case .aDeliveredReturnReceiptShouldBeSentForPersistedMessageReceived(returnReceipt: let returnReceipt, contactCryptoId: let contactCryptoId, ownedCryptoId: let ownedCryptoId, messageIdentifierFromEngine: let messageIdentifierFromEngine):
			info = [
				"returnReceipt": returnReceipt,
				"contactCryptoId": contactCryptoId,
				"ownedCryptoId": ownedCryptoId,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
			]
		case .theBodyOfPersistedMessageReceivedDidChange(persistedMessageReceivedObjectID: let persistedMessageReceivedObjectID):
			info = [
				"persistedMessageReceivedObjectID": persistedMessageReceivedObjectID,
			]
		case .persistedDiscussionWasArchived(discussionPermanentID: let discussionPermanentID):
			info = [
				"discussionPermanentID": discussionPermanentID,
			]
		case .persistedContactWasUpdated(contactObjectID: let contactObjectID):
			info = [
				"contactObjectID": contactObjectID,
			]
		case .fyleMessageJoinWithStatusWasInserted(fyleMessageJoinObjectID: let fyleMessageJoinObjectID):
			info = [
				"fyleMessageJoinObjectID": fyleMessageJoinObjectID,
			]
		case .fyleMessageJoinWithStatusWasUpdated(fyleMessageJoinObjectID: let fyleMessageJoinObjectID):
			info = [
				"fyleMessageJoinObjectID": fyleMessageJoinObjectID,
			]
		case .discussionLocalConfigurationHasBeenUpdated(newValue: let newValue, localConfigurationObjectID: let localConfigurationObjectID):
			info = [
				"newValue": newValue,
				"localConfigurationObjectID": localConfigurationObjectID,
			]
		}
		return info
	}

	func post(object anObject: Any? = nil) {
		let name = Name.forInternalNotification(self)
		NotificationCenter.default.post(name: name, object: anObject, userInfo: userInfo)
	}

	func postOnDispatchQueue(object anObject: Any? = nil) {
		let name = Name.forInternalNotification(self)
		postOnDispatchQueue(withLabel: "Queue for posting \(name.rawValue) notification", object: anObject)
	}

	func postOnDispatchQueue(_ queue: DispatchQueue) {
		let name = Name.forInternalNotification(self)
		queue.async {
			NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
		}
	}

	private func postOnDispatchQueue(withLabel label: String, object anObject: Any? = nil) {
		let name = Name.forInternalNotification(self)
		let userInfo = self.userInfo
		DispatchQueue(label: label).async {
			NotificationCenter.default.post(name: name, object: anObject, userInfo: userInfo)
		}
	}

	public static func observeNewDraftToSend(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDraft>) -> Void) -> NSObjectProtocol {
		let name = Name.newDraftToSend.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let draftPermanentID = notification.userInfo!["draftPermanentID"] as! ObvManagedObjectPermanentID<PersistedDraft>
			block(draftPermanentID)
		}
	}

	public static func observeDraftWasSent(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDraft>) -> Void) -> NSObjectProtocol {
		let name = Name.draftWasSent.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedDraftObjectID = notification.userInfo!["persistedDraftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			block(persistedDraftObjectID)
		}
	}

	public static func observePersistedMessageHasNewMetadata(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageHasNewMetadata.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageObjectID = notification.userInfo!["persistedMessageObjectID"] as! NSManagedObjectID
			block(persistedMessageObjectID)
		}
	}

	public static func observeNewOrUpdatedPersistedInvitation(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Bool, ObvDialog, UUID) -> Void) -> NSObjectProtocol {
		let name = Name.newOrUpdatedPersistedInvitation.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let concernedOwnedIdentityIsHidden = notification.userInfo!["concernedOwnedIdentityIsHidden"] as! Bool
			let obvDialog = notification.userInfo!["obvDialog"] as! ObvDialog
			let persistedInvitationUUID = notification.userInfo!["persistedInvitationUUID"] as! UUID
			block(concernedOwnedIdentityIsHidden, obvDialog, persistedInvitationUUID)
		}
	}

	public static func observePersistedContactWasInserted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedObvContactIdentity>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactWasInserted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactPermanentID = notification.userInfo!["contactPermanentID"] as! ObvManagedObjectPermanentID<PersistedObvContactIdentity>
			block(contactPermanentID)
		}
	}

	public static func observePersistedContactWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, Data) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! NSManagedObjectID
			let identity = notification.userInfo!["identity"] as! Data
			block(objectID, identity)
		}
	}

	public static func observePersistedContactHasNewCustomDisplayName(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactHasNewCustomDisplayName.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			block(contactCryptoId)
		}
	}

	public static func observePersistedContactHasNewStatus(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactHasNewStatus.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(contactCryptoId, ownedCryptoId)
		}
	}

	public static func observePersistedContactIsActiveChanged(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedObvContactIdentity>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactIsActiveChanged.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactID = notification.userInfo!["contactID"] as! TypeSafeManagedObjectID<PersistedObvContactIdentity>
			block(contactID)
		}
	}

	public static func observeNewMessageExpiration(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Date) -> Void) -> NSObjectProtocol {
		let name = Name.newMessageExpiration.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let expirationDate = notification.userInfo!["expirationDate"] as! Date
			block(expirationDate)
		}
	}

	public static func observePersistedMessageReactionReceivedWasDeletedOnSentMessage(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedMessageSent>, ObvManagedObjectPermanentID<PersistedObvContactIdentity>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageReactionReceivedWasDeletedOnSentMessage.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let messagePermanentID = notification.userInfo!["messagePermanentID"] as! ObvManagedObjectPermanentID<PersistedMessageSent>
			let contactPermanentID = notification.userInfo!["contactPermanentID"] as! ObvManagedObjectPermanentID<PersistedObvContactIdentity>
			block(messagePermanentID, contactPermanentID)
		}
	}

	public static func observePersistedMessageReactionReceivedWasInsertedOrUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedMessageReactionReceived>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageReactionReceivedWasInsertedOrUpdated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! TypeSafeManagedObjectID<PersistedMessageReactionReceived>
			block(objectID)
		}
	}

	public static func observePersistedContactGroupHasUpdatedContactIdentities(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, Set<PersistedObvContactIdentity>, Set<PersistedObvContactIdentity>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactGroupHasUpdatedContactIdentities.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedContactGroupObjectID = notification.userInfo!["persistedContactGroupObjectID"] as! NSManagedObjectID
			let insertedContacts = notification.userInfo!["insertedContacts"] as! Set<PersistedObvContactIdentity>
			let removedContacts = notification.userInfo!["removedContacts"] as! Set<PersistedObvContactIdentity>
			block(persistedContactGroupObjectID, insertedContacts, removedContacts)
		}
	}

	public static func observeAReadOncePersistedMessageSentWasSent(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedMessageSent>, ObvManagedObjectPermanentID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.aReadOncePersistedMessageSentWasSent.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageSentPermanentID = notification.userInfo!["persistedMessageSentPermanentID"] as! ObvManagedObjectPermanentID<PersistedMessageSent>
			let persistedDiscussionPermanentID = notification.userInfo!["persistedDiscussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			block(persistedMessageSentPermanentID, persistedDiscussionPermanentID)
		}
	}

	public static func observeNewPersistedObvContactDevice(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.newPersistedObvContactDevice.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactDeviceObjectID = notification.userInfo!["contactDeviceObjectID"] as! NSManagedObjectID
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			block(contactDeviceObjectID, contactCryptoId)
		}
	}

	public static func observeDeletedPersistedObvContactDevice(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.deletedPersistedObvContactDevice.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			block(contactCryptoId)
		}
	}

	public static func observePersistedDiscussionHasNewTitle(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDiscussion>, String) -> Void) -> NSObjectProtocol {
		let name = Name.persistedDiscussionHasNewTitle.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			let title = notification.userInfo!["title"] as! String
			block(objectID, title)
		}
	}

	public static func observePersistedDiscussionWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, TypeSafeManagedObjectID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedDiscussionWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let objectIDOfDeletedDiscussion = notification.userInfo!["objectIDOfDeletedDiscussion"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			block(discussionPermanentID, objectIDOfDeletedDiscussion)
		}
	}

	public static func observePersistedDiscussionWasInserted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, TypeSafeManagedObjectID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedDiscussionWasInserted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let objectID = notification.userInfo!["objectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			block(discussionPermanentID, objectID)
		}
	}

	public static func observeNewPersistedObvOwnedIdentity(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Bool) -> Void) -> NSObjectProtocol {
		let name = Name.newPersistedObvOwnedIdentity.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let isActive = notification.userInfo!["isActive"] as! Bool
			block(ownedCryptoId, isActive)
		}
	}

	public static func observeOwnedIdentityWasReactivated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityWasReactivated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentityObjectID = notification.userInfo!["ownedIdentityObjectID"] as! NSManagedObjectID
			block(ownedIdentityObjectID)
		}
	}

	public static func observeOwnedIdentityWasDeactivated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityWasDeactivated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentityObjectID = notification.userInfo!["ownedIdentityObjectID"] as! NSManagedObjectID
			block(ownedIdentityObjectID)
		}
	}

	public static func observeAnOldDiscussionSharedConfigurationWasReceived(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.anOldDiscussionSharedConfigurationWasReceived.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedDiscussionObjectID = notification.userInfo!["persistedDiscussionObjectID"] as! NSManagedObjectID
			block(persistedDiscussionObjectID)
		}
	}

	public static func observePersistedMessageSystemWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, TypeSafeManagedObjectID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageSystemWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! NSManagedObjectID
			let discussionObjectID = notification.userInfo!["discussionObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			block(objectID, discussionObjectID)
		}
	}

	public static func observePersistedMessagesWereDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, Set<ObvManagedObjectPermanentID<PersistedMessage>>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessagesWereDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let messagePermanentIDs = notification.userInfo!["messagePermanentIDs"] as! Set<ObvManagedObjectPermanentID<PersistedMessage>>
			block(discussionPermanentID, messagePermanentIDs)
		}
	}

	public static func observePersistedMessagesWereWiped(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, Set<ObvManagedObjectPermanentID<PersistedMessage>>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessagesWereWiped.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let messagePermanentIDs = notification.userInfo!["messagePermanentIDs"] as! Set<ObvManagedObjectPermanentID<PersistedMessage>>
			block(discussionPermanentID, messagePermanentIDs)
		}
	}

	public static func observePersistedDiscussionStatusChanged(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, PersistedDiscussion.Status) -> Void) -> NSObjectProtocol {
		let name = Name.persistedDiscussionStatusChanged.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let newStatus = notification.userInfo!["newStatus"] as! PersistedDiscussion.Status
			block(discussionPermanentID, newStatus)
		}
	}

	public static func observePersistedGroupV2UpdateIsFinished(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedGroupV2>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedGroupV2UpdateIsFinished.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! TypeSafeManagedObjectID<PersistedGroupV2>
			block(objectID)
		}
	}

	public static func observePersistedGroupV2WasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedGroupV2>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedGroupV2WasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! TypeSafeManagedObjectID<PersistedGroupV2>
			block(objectID)
		}
	}

	public static func observeAPersistedGroupV2MemberChangedFromPendingToNonPending(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedObvContactIdentity>) -> Void) -> NSObjectProtocol {
		let name = Name.aPersistedGroupV2MemberChangedFromPendingToNonPending.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactObjectID = notification.userInfo!["contactObjectID"] as! TypeSafeManagedObjectID<PersistedObvContactIdentity>
			block(contactObjectID)
		}
	}

	public static func observeOwnedCircledInitialsConfigurationDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>, ObvCryptoId, CircledInitialsConfiguration) -> Void) -> NSObjectProtocol {
		let name = Name.ownedCircledInitialsConfigurationDidChange.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentityPermanentID = notification.userInfo!["ownedIdentityPermanentID"] as! ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let newOwnedCircledInitialsConfiguration = notification.userInfo!["newOwnedCircledInitialsConfiguration"] as! CircledInitialsConfiguration
			block(ownedIdentityPermanentID, ownedCryptoId, newOwnedCircledInitialsConfiguration)
		}
	}

	public static func observePersistedObvOwnedIdentityWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.persistedObvOwnedIdentityWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	public static func observeOwnedIdentityHiddenStatusChanged(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Bool) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityHiddenStatusChanged.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let isHidden = notification.userInfo!["isHidden"] as! Bool
			block(ownedCryptoId, isHidden)
		}
	}

	public static func observeBadgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.badgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(ownedCryptoId)
		}
	}

	public static func observeDisplayedContactGroupWasJustCreated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<DisplayedContactGroup>) -> Void) -> NSObjectProtocol {
		let name = Name.displayedContactGroupWasJustCreated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let permanentID = notification.userInfo!["permanentID"] as! ObvManagedObjectPermanentID<DisplayedContactGroup>
			block(permanentID)
		}
	}

	public static func observeGroupV2TrustedDetailsShouldBeReplacedByPublishedDetails(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Data) -> Void) -> NSObjectProtocol {
		let name = Name.groupV2TrustedDetailsShouldBeReplacedByPublishedDetails.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownCryptoId = notification.userInfo!["ownCryptoId"] as! ObvCryptoId
			let groupIdentifier = notification.userInfo!["groupIdentifier"] as! Data
			block(ownCryptoId, groupIdentifier)
		}
	}

	public static func observeReceivedFyleJoinHasBeenMarkAsOpened(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) -> Void) -> NSObjectProtocol {
		let name = Name.receivedFyleJoinHasBeenMarkAsOpened.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let receivedFyleJoinID = notification.userInfo!["receivedFyleJoinID"] as! TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>
			block(receivedFyleJoinID)
		}
	}

	public static func observeADeliveredReturnReceiptShouldBeSentForAReceivedFyleMessageJoinWithStatus(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ReturnReceiptJSON, ObvCryptoId, ObvCryptoId, Data, Int) -> Void) -> NSObjectProtocol {
		let name = Name.aDeliveredReturnReceiptShouldBeSentForAReceivedFyleMessageJoinWithStatus.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let returnReceipt = notification.userInfo!["returnReceipt"] as! ReturnReceiptJSON
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let attachmentNumber = notification.userInfo!["attachmentNumber"] as! Int
			block(returnReceipt, contactCryptoId, ownedCryptoId, messageIdentifierFromEngine, attachmentNumber)
		}
	}

	public static func observePersistedMessageReceivedWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, Data, ObvCryptoId, Double, TypeSafeManagedObjectID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageReceivedWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! NSManagedObjectID
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let sortIndex = notification.userInfo!["sortIndex"] as! Double
			let discussionObjectID = notification.userInfo!["discussionObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			block(objectID, messageIdentifierFromEngine, ownedCryptoId, sortIndex, discussionObjectID)
		}
	}

	public static func observePersistedMessageReceivedWasRead(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedMessageReceived>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageReceivedWasRead.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageReceivedObjectID = notification.userInfo!["persistedMessageReceivedObjectID"] as! TypeSafeManagedObjectID<PersistedMessageReceived>
			block(persistedMessageReceivedObjectID)
		}
	}

	public static func observeADeliveredReturnReceiptShouldBeSentForPersistedMessageReceived(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ReturnReceiptJSON, ObvCryptoId, ObvCryptoId, Data) -> Void) -> NSObjectProtocol {
		let name = Name.aDeliveredReturnReceiptShouldBeSentForPersistedMessageReceived.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let returnReceipt = notification.userInfo!["returnReceipt"] as! ReturnReceiptJSON
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			block(returnReceipt, contactCryptoId, ownedCryptoId, messageIdentifierFromEngine)
		}
	}

	public static func observeTheBodyOfPersistedMessageReceivedDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.theBodyOfPersistedMessageReceivedDidChange.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageReceivedObjectID = notification.userInfo!["persistedMessageReceivedObjectID"] as! NSManagedObjectID
			block(persistedMessageReceivedObjectID)
		}
	}

	public static func observePersistedDiscussionWasArchived(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedDiscussionWasArchived.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			block(discussionPermanentID)
		}
	}

	public static func observePersistedContactWasUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedObvContactIdentity>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactWasUpdated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactObjectID = notification.userInfo!["contactObjectID"] as! TypeSafeManagedObjectID<PersistedObvContactIdentity>
			block(contactObjectID)
		}
	}

	public static func observeFyleMessageJoinWithStatusWasInserted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) -> Void) -> NSObjectProtocol {
		let name = Name.fyleMessageJoinWithStatusWasInserted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let fyleMessageJoinObjectID = notification.userInfo!["fyleMessageJoinObjectID"] as! TypeSafeManagedObjectID<FyleMessageJoinWithStatus>
			block(fyleMessageJoinObjectID)
		}
	}

	public static func observeFyleMessageJoinWithStatusWasUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) -> Void) -> NSObjectProtocol {
		let name = Name.fyleMessageJoinWithStatusWasUpdated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let fyleMessageJoinObjectID = notification.userInfo!["fyleMessageJoinObjectID"] as! TypeSafeManagedObjectID<FyleMessageJoinWithStatus>
			block(fyleMessageJoinObjectID)
		}
	}

	public static func observeDiscussionLocalConfigurationHasBeenUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (PersistedDiscussionLocalConfigurationValue, TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) -> Void) -> NSObjectProtocol {
		let name = Name.discussionLocalConfigurationHasBeenUpdated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let newValue = notification.userInfo!["newValue"] as! PersistedDiscussionLocalConfigurationValue
			let localConfigurationObjectID = notification.userInfo!["localConfigurationObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>
			block(newValue, localConfigurationObjectID)
		}
	}

}

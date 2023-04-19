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
import CoreData
import ObvEngine
import ObvCrypto
import ObvTypes

fileprivate struct OptionalWrapper<T> {
	let value: T?
	public init() {
		self.value = nil
	}
	public init(_ value: T?) {
		self.value = value
	}
}

enum ObvMessengerCoreDataNotification {
	case newDraftToSend(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>)
	case draftWasSent(persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>)
	case persistedMessageHasNewMetadata(persistedMessageObjectID: NSManagedObjectID)
	case newOrUpdatedPersistedInvitation(obvDialog: ObvDialog, persistedInvitationUUID: UUID)
	case persistedContactWasInserted(contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>)
	case persistedContactWasDeleted(objectID: NSManagedObjectID, identity: Data)
	case persistedContactHasNewCustomDisplayName(contactCryptoId: ObvCryptoId)
	case persistedContactHasNewStatus(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case persistedContactIsActiveChanged(contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>)
	case newMessageExpiration(expirationDate: Date)
	case persistedMessageReactionReceivedWasDeletedOnSentMessage(messagePermanentID: ObvManagedObjectPermanentID<PersistedMessageSent>, contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>)
	case persistedMessageReactionReceivedWasInsertedOrUpdated(objectID: TypeSafeManagedObjectID<PersistedMessageReactionReceived>)
	case userWantsToUpdateDiscussionLocalConfiguration(value: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>)
	case persistedContactGroupHasUpdatedContactIdentities(persistedContactGroupObjectID: NSManagedObjectID, insertedContacts: Set<PersistedObvContactIdentity>, removedContacts: Set<PersistedObvContactIdentity>)
	case aReadOncePersistedMessageSentWasSent(persistedMessageSentPermanentID: ObvManagedObjectPermanentID<PersistedMessageSent>, persistedDiscussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>)
	case newPersistedObvContactDevice(contactDeviceObjectID: NSManagedObjectID, contactCryptoId: ObvCryptoId)
	case deletedPersistedObvContactDevice(contactCryptoId: ObvCryptoId)
	case persistedDiscussionHasNewTitle(objectID: TypeSafeManagedObjectID<PersistedDiscussion>, title: String)
	case persistedDiscussionWasDeleted(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>)
	case newPersistedObvOwnedIdentity(ownedCryptoId: ObvCryptoId)
	case ownedIdentityWasReactivated(ownedIdentityObjectID: NSManagedObjectID)
	case ownedIdentityWasDeactivated(ownedIdentityObjectID: NSManagedObjectID)
	case anOldDiscussionSharedConfigurationWasReceived(persistedDiscussionObjectID: NSManagedObjectID)
	case persistedMessageSystemWasDeleted(objectID: NSManagedObjectID, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
	case persistedMessagesWereDeleted(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>)
	case persistedMessagesWereWiped(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>)
	case draftToSendWasReset(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>)
	case draftFyleJoinWasDeleted(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, draftFyleJoinPermanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin>)
	case fyleMessageJoinWasWiped(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, fyleMessageJoinPermanentID: ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>)
	case persistedDiscussionStatusChanged(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, newStatus: PersistedDiscussion.Status)
	case persistedGroupV2UpdateIsFinished(objectID: TypeSafeManagedObjectID<PersistedGroupV2>)
	case persistedGroupV2WasDeleted(objectID: TypeSafeManagedObjectID<PersistedGroupV2>)
	case aPersistedGroupV2MemberChangedFromPendingToNonPending(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>)

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
		case userWantsToUpdateDiscussionLocalConfiguration
		case persistedContactGroupHasUpdatedContactIdentities
		case aReadOncePersistedMessageSentWasSent
		case newPersistedObvContactDevice
		case deletedPersistedObvContactDevice
		case persistedDiscussionHasNewTitle
		case persistedDiscussionWasDeleted
		case newPersistedObvOwnedIdentity
		case ownedIdentityWasReactivated
		case ownedIdentityWasDeactivated
		case anOldDiscussionSharedConfigurationWasReceived
		case persistedMessageSystemWasDeleted
		case persistedMessagesWereDeleted
		case persistedMessagesWereWiped
		case draftToSendWasReset
		case draftFyleJoinWasDeleted
		case fyleMessageJoinWasWiped
		case persistedDiscussionStatusChanged
		case persistedGroupV2UpdateIsFinished
		case persistedGroupV2WasDeleted
		case aPersistedGroupV2MemberChangedFromPendingToNonPending

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
			case .userWantsToUpdateDiscussionLocalConfiguration: return Name.userWantsToUpdateDiscussionLocalConfiguration.name
			case .persistedContactGroupHasUpdatedContactIdentities: return Name.persistedContactGroupHasUpdatedContactIdentities.name
			case .aReadOncePersistedMessageSentWasSent: return Name.aReadOncePersistedMessageSentWasSent.name
			case .newPersistedObvContactDevice: return Name.newPersistedObvContactDevice.name
			case .deletedPersistedObvContactDevice: return Name.deletedPersistedObvContactDevice.name
			case .persistedDiscussionHasNewTitle: return Name.persistedDiscussionHasNewTitle.name
			case .persistedDiscussionWasDeleted: return Name.persistedDiscussionWasDeleted.name
			case .newPersistedObvOwnedIdentity: return Name.newPersistedObvOwnedIdentity.name
			case .ownedIdentityWasReactivated: return Name.ownedIdentityWasReactivated.name
			case .ownedIdentityWasDeactivated: return Name.ownedIdentityWasDeactivated.name
			case .anOldDiscussionSharedConfigurationWasReceived: return Name.anOldDiscussionSharedConfigurationWasReceived.name
			case .persistedMessageSystemWasDeleted: return Name.persistedMessageSystemWasDeleted.name
			case .persistedMessagesWereDeleted: return Name.persistedMessagesWereDeleted.name
			case .persistedMessagesWereWiped: return Name.persistedMessagesWereWiped.name
			case .draftToSendWasReset: return Name.draftToSendWasReset.name
			case .draftFyleJoinWasDeleted: return Name.draftFyleJoinWasDeleted.name
			case .fyleMessageJoinWasWiped: return Name.fyleMessageJoinWasWiped.name
			case .persistedDiscussionStatusChanged: return Name.persistedDiscussionStatusChanged.name
			case .persistedGroupV2UpdateIsFinished: return Name.persistedGroupV2UpdateIsFinished.name
			case .persistedGroupV2WasDeleted: return Name.persistedGroupV2WasDeleted.name
			case .aPersistedGroupV2MemberChangedFromPendingToNonPending: return Name.aPersistedGroupV2MemberChangedFromPendingToNonPending.name
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
		case .newOrUpdatedPersistedInvitation(obvDialog: let obvDialog, persistedInvitationUUID: let persistedInvitationUUID):
			info = [
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
		case .userWantsToUpdateDiscussionLocalConfiguration(value: let value, localConfigurationObjectID: let localConfigurationObjectID):
			info = [
				"value": value,
				"localConfigurationObjectID": localConfigurationObjectID,
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
		case .persistedDiscussionWasDeleted(discussionPermanentID: let discussionPermanentID):
			info = [
				"discussionPermanentID": discussionPermanentID,
			]
		case .newPersistedObvOwnedIdentity(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
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
		case .draftToSendWasReset(discussionPermanentID: let discussionPermanentID, draftPermanentID: let draftPermanentID):
			info = [
				"discussionPermanentID": discussionPermanentID,
				"draftPermanentID": draftPermanentID,
			]
		case .draftFyleJoinWasDeleted(discussionPermanentID: let discussionPermanentID, draftPermanentID: let draftPermanentID, draftFyleJoinPermanentID: let draftFyleJoinPermanentID):
			info = [
				"discussionPermanentID": discussionPermanentID,
				"draftPermanentID": draftPermanentID,
				"draftFyleJoinPermanentID": draftFyleJoinPermanentID,
			]
		case .fyleMessageJoinWasWiped(discussionPermanentID: let discussionPermanentID, messagePermanentID: let messagePermanentID, fyleMessageJoinPermanentID: let fyleMessageJoinPermanentID):
			info = [
				"discussionPermanentID": discussionPermanentID,
				"messagePermanentID": messagePermanentID,
				"fyleMessageJoinPermanentID": fyleMessageJoinPermanentID,
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

	static func observeNewDraftToSend(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDraft>) -> Void) -> NSObjectProtocol {
		let name = Name.newDraftToSend.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let draftPermanentID = notification.userInfo!["draftPermanentID"] as! ObvManagedObjectPermanentID<PersistedDraft>
			block(draftPermanentID)
		}
	}

	static func observeDraftWasSent(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDraft>) -> Void) -> NSObjectProtocol {
		let name = Name.draftWasSent.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedDraftObjectID = notification.userInfo!["persistedDraftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			block(persistedDraftObjectID)
		}
	}

	static func observePersistedMessageHasNewMetadata(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageHasNewMetadata.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageObjectID = notification.userInfo!["persistedMessageObjectID"] as! NSManagedObjectID
			block(persistedMessageObjectID)
		}
	}

	static func observeNewOrUpdatedPersistedInvitation(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvDialog, UUID) -> Void) -> NSObjectProtocol {
		let name = Name.newOrUpdatedPersistedInvitation.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let obvDialog = notification.userInfo!["obvDialog"] as! ObvDialog
			let persistedInvitationUUID = notification.userInfo!["persistedInvitationUUID"] as! UUID
			block(obvDialog, persistedInvitationUUID)
		}
	}

	static func observePersistedContactWasInserted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedObvContactIdentity>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactWasInserted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactPermanentID = notification.userInfo!["contactPermanentID"] as! ObvManagedObjectPermanentID<PersistedObvContactIdentity>
			block(contactPermanentID)
		}
	}

	static func observePersistedContactWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, Data) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! NSManagedObjectID
			let identity = notification.userInfo!["identity"] as! Data
			block(objectID, identity)
		}
	}

	static func observePersistedContactHasNewCustomDisplayName(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactHasNewCustomDisplayName.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			block(contactCryptoId)
		}
	}

	static func observePersistedContactHasNewStatus(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactHasNewStatus.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(contactCryptoId, ownedCryptoId)
		}
	}

	static func observePersistedContactIsActiveChanged(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedObvContactIdentity>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactIsActiveChanged.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactID = notification.userInfo!["contactID"] as! TypeSafeManagedObjectID<PersistedObvContactIdentity>
			block(contactID)
		}
	}

	static func observeNewMessageExpiration(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Date) -> Void) -> NSObjectProtocol {
		let name = Name.newMessageExpiration.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let expirationDate = notification.userInfo!["expirationDate"] as! Date
			block(expirationDate)
		}
	}

	static func observePersistedMessageReactionReceivedWasDeletedOnSentMessage(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedMessageSent>, ObvManagedObjectPermanentID<PersistedObvContactIdentity>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageReactionReceivedWasDeletedOnSentMessage.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let messagePermanentID = notification.userInfo!["messagePermanentID"] as! ObvManagedObjectPermanentID<PersistedMessageSent>
			let contactPermanentID = notification.userInfo!["contactPermanentID"] as! ObvManagedObjectPermanentID<PersistedObvContactIdentity>
			block(messagePermanentID, contactPermanentID)
		}
	}

	static func observePersistedMessageReactionReceivedWasInsertedOrUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedMessageReactionReceived>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageReactionReceivedWasInsertedOrUpdated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! TypeSafeManagedObjectID<PersistedMessageReactionReceived>
			block(objectID)
		}
	}

	static func observeUserWantsToUpdateDiscussionLocalConfiguration(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (PersistedDiscussionLocalConfigurationValue, TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUpdateDiscussionLocalConfiguration.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let value = notification.userInfo!["value"] as! PersistedDiscussionLocalConfigurationValue
			let localConfigurationObjectID = notification.userInfo!["localConfigurationObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>
			block(value, localConfigurationObjectID)
		}
	}

	static func observePersistedContactGroupHasUpdatedContactIdentities(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, Set<PersistedObvContactIdentity>, Set<PersistedObvContactIdentity>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactGroupHasUpdatedContactIdentities.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedContactGroupObjectID = notification.userInfo!["persistedContactGroupObjectID"] as! NSManagedObjectID
			let insertedContacts = notification.userInfo!["insertedContacts"] as! Set<PersistedObvContactIdentity>
			let removedContacts = notification.userInfo!["removedContacts"] as! Set<PersistedObvContactIdentity>
			block(persistedContactGroupObjectID, insertedContacts, removedContacts)
		}
	}

	static func observeAReadOncePersistedMessageSentWasSent(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedMessageSent>, ObvManagedObjectPermanentID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.aReadOncePersistedMessageSentWasSent.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageSentPermanentID = notification.userInfo!["persistedMessageSentPermanentID"] as! ObvManagedObjectPermanentID<PersistedMessageSent>
			let persistedDiscussionPermanentID = notification.userInfo!["persistedDiscussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			block(persistedMessageSentPermanentID, persistedDiscussionPermanentID)
		}
	}

	static func observeNewPersistedObvContactDevice(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.newPersistedObvContactDevice.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactDeviceObjectID = notification.userInfo!["contactDeviceObjectID"] as! NSManagedObjectID
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			block(contactDeviceObjectID, contactCryptoId)
		}
	}

	static func observeDeletedPersistedObvContactDevice(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.deletedPersistedObvContactDevice.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			block(contactCryptoId)
		}
	}

	static func observePersistedDiscussionHasNewTitle(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDiscussion>, String) -> Void) -> NSObjectProtocol {
		let name = Name.persistedDiscussionHasNewTitle.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			let title = notification.userInfo!["title"] as! String
			block(objectID, title)
		}
	}

	static func observePersistedDiscussionWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedDiscussionWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			block(discussionPermanentID)
		}
	}

	static func observeNewPersistedObvOwnedIdentity(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.newPersistedObvOwnedIdentity.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(ownedCryptoId)
		}
	}

	static func observeOwnedIdentityWasReactivated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityWasReactivated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentityObjectID = notification.userInfo!["ownedIdentityObjectID"] as! NSManagedObjectID
			block(ownedIdentityObjectID)
		}
	}

	static func observeOwnedIdentityWasDeactivated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityWasDeactivated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentityObjectID = notification.userInfo!["ownedIdentityObjectID"] as! NSManagedObjectID
			block(ownedIdentityObjectID)
		}
	}

	static func observeAnOldDiscussionSharedConfigurationWasReceived(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.anOldDiscussionSharedConfigurationWasReceived.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedDiscussionObjectID = notification.userInfo!["persistedDiscussionObjectID"] as! NSManagedObjectID
			block(persistedDiscussionObjectID)
		}
	}

	static func observePersistedMessageSystemWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, TypeSafeManagedObjectID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageSystemWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! NSManagedObjectID
			let discussionObjectID = notification.userInfo!["discussionObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			block(objectID, discussionObjectID)
		}
	}

	static func observePersistedMessagesWereDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, Set<ObvManagedObjectPermanentID<PersistedMessage>>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessagesWereDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let messagePermanentIDs = notification.userInfo!["messagePermanentIDs"] as! Set<ObvManagedObjectPermanentID<PersistedMessage>>
			block(discussionPermanentID, messagePermanentIDs)
		}
	}

	static func observePersistedMessagesWereWiped(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, Set<ObvManagedObjectPermanentID<PersistedMessage>>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessagesWereWiped.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let messagePermanentIDs = notification.userInfo!["messagePermanentIDs"] as! Set<ObvManagedObjectPermanentID<PersistedMessage>>
			block(discussionPermanentID, messagePermanentIDs)
		}
	}

	static func observeDraftToSendWasReset(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, ObvManagedObjectPermanentID<PersistedDraft>) -> Void) -> NSObjectProtocol {
		let name = Name.draftToSendWasReset.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let draftPermanentID = notification.userInfo!["draftPermanentID"] as! ObvManagedObjectPermanentID<PersistedDraft>
			block(discussionPermanentID, draftPermanentID)
		}
	}

	static func observeDraftFyleJoinWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, ObvManagedObjectPermanentID<PersistedDraft>, ObvManagedObjectPermanentID<PersistedDraftFyleJoin>) -> Void) -> NSObjectProtocol {
		let name = Name.draftFyleJoinWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let draftPermanentID = notification.userInfo!["draftPermanentID"] as! ObvManagedObjectPermanentID<PersistedDraft>
			let draftFyleJoinPermanentID = notification.userInfo!["draftFyleJoinPermanentID"] as! ObvManagedObjectPermanentID<PersistedDraftFyleJoin>
			block(discussionPermanentID, draftPermanentID, draftFyleJoinPermanentID)
		}
	}

	static func observeFyleMessageJoinWasWiped(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, ObvManagedObjectPermanentID<PersistedMessage>, ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>) -> Void) -> NSObjectProtocol {
		let name = Name.fyleMessageJoinWasWiped.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let messagePermanentID = notification.userInfo!["messagePermanentID"] as! ObvManagedObjectPermanentID<PersistedMessage>
			let fyleMessageJoinPermanentID = notification.userInfo!["fyleMessageJoinPermanentID"] as! ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>
			block(discussionPermanentID, messagePermanentID, fyleMessageJoinPermanentID)
		}
	}

	static func observePersistedDiscussionStatusChanged(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, PersistedDiscussion.Status) -> Void) -> NSObjectProtocol {
		let name = Name.persistedDiscussionStatusChanged.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let newStatus = notification.userInfo!["newStatus"] as! PersistedDiscussion.Status
			block(discussionPermanentID, newStatus)
		}
	}

	static func observePersistedGroupV2UpdateIsFinished(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedGroupV2>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedGroupV2UpdateIsFinished.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! TypeSafeManagedObjectID<PersistedGroupV2>
			block(objectID)
		}
	}

	static func observePersistedGroupV2WasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedGroupV2>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedGroupV2WasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! TypeSafeManagedObjectID<PersistedGroupV2>
			block(objectID)
		}
	}

	static func observeAPersistedGroupV2MemberChangedFromPendingToNonPending(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedObvContactIdentity>) -> Void) -> NSObjectProtocol {
		let name = Name.aPersistedGroupV2MemberChangedFromPendingToNonPending.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactObjectID = notification.userInfo!["contactObjectID"] as! TypeSafeManagedObjectID<PersistedObvContactIdentity>
			block(contactObjectID)
		}
	}

}

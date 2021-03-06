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
	case newDraftToSend(persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>)
	case draftWasSent(persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>)
	case persistedMessageHasNewMetadata(persistedMessageObjectID: NSManagedObjectID)
	case newOrUpdatedPersistedInvitation(obvDialog: ObvDialog, persistedInvitationUUID: UUID)
	case persistedContactWasInserted(objectID: NSManagedObjectID, contactCryptoId: ObvCryptoId)
	case persistedContactWasDeleted(objectID: NSManagedObjectID, identity: Data)
	case persistedContactHasNewCustomDisplayName(contactCryptoId: ObvCryptoId)
	case persistedContactHasNewStatus(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case persistedContactIsActiveChanged(contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>)
	case aOneToOneDiscussionTitleNeedsToBeReset(ownedIdentityObjectID: TypeSafeManagedObjectID<PersistedObvOwnedIdentity>)
	case newMessageExpiration(expirationDate: Date)
	case persistedMessageReactionReceivedWasDeleted(messageURI: URL, contactURI: URL)
	case persistedMessageReactionReceivedWasInsertedOrUpdated(objectID: TypeSafeManagedObjectID<PersistedMessageReactionReceived>)
	case userWantsToUpdateDiscussionLocalConfiguration(value: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>)
	case persistedContactGroupHasUpdatedContactIdentities(persistedContactGroupObjectID: NSManagedObjectID, insertedContacts: Set<PersistedObvContactIdentity>, removedContacts: Set<PersistedObvContactIdentity>)
	case aReadOncePersistedMessageSentWasSent(persistedMessageSentObjectID: NSManagedObjectID, persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
	case newPersistedObvContactDevice(contactDeviceObjectID: NSManagedObjectID, contactCryptoId: ObvCryptoId)
	case deletedPersistedObvContactDevice(contactCryptoId: ObvCryptoId)
	case persistedDiscussionHasNewTitle(objectID: TypeSafeManagedObjectID<PersistedDiscussion>, title: String)
	case newLockedPersistedDiscussion(previousDiscussionUriRepresentation: TypeSafeURL<PersistedDiscussion>, newLockedDiscussionId: TypeSafeManagedObjectID<PersistedDiscussion>)
	case persistedDiscussionWasDeleted(discussionUriRepresentation: TypeSafeURL<PersistedDiscussion>)
	case newPersistedObvOwnedIdentity(ownedCryptoId: ObvCryptoId)
	case ownedIdentityWasReactivated(ownedIdentityObjectID: NSManagedObjectID)
	case ownedIdentityWasDeactivated(ownedIdentityObjectID: NSManagedObjectID)
	case anOldDiscussionSharedConfigurationWasReceived(persistedDiscussionObjectID: NSManagedObjectID)
	case persistedMessageSystemWasDeleted(objectID: NSManagedObjectID, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
	case persistedMessagesWereDeleted(discussionUriRepresentation: TypeSafeURL<PersistedDiscussion>, messageUriRepresentations: Set<TypeSafeURL<PersistedMessage>>)
	case persistedMessagesWereWiped(discussionUriRepresentation: TypeSafeURL<PersistedDiscussion>, messageUriRepresentations: Set<TypeSafeURL<PersistedMessage>>)
	case draftToSendWasReset(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>)
	case draftFyleJoinWasDeleted(discussionUriRepresentation: TypeSafeURL<PersistedDiscussion>, draftUriRepresentation: TypeSafeURL<PersistedDraft>, draftFyleJoinUriRepresentation: TypeSafeURL<PersistedDraftFyleJoin>)
	case fyleMessageJoinWasWiped(discussionUriRepresentation: TypeSafeURL<PersistedDiscussion>, messageUriRepresentation: TypeSafeURL<PersistedMessage>, fyleMessageJoinUriRepresentation: TypeSafeURL<FyleMessageJoinWithStatus>)

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
		case aOneToOneDiscussionTitleNeedsToBeReset
		case newMessageExpiration
		case persistedMessageReactionReceivedWasDeleted
		case persistedMessageReactionReceivedWasInsertedOrUpdated
		case userWantsToUpdateDiscussionLocalConfiguration
		case persistedContactGroupHasUpdatedContactIdentities
		case aReadOncePersistedMessageSentWasSent
		case newPersistedObvContactDevice
		case deletedPersistedObvContactDevice
		case persistedDiscussionHasNewTitle
		case newLockedPersistedDiscussion
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
			case .aOneToOneDiscussionTitleNeedsToBeReset: return Name.aOneToOneDiscussionTitleNeedsToBeReset.name
			case .newMessageExpiration: return Name.newMessageExpiration.name
			case .persistedMessageReactionReceivedWasDeleted: return Name.persistedMessageReactionReceivedWasDeleted.name
			case .persistedMessageReactionReceivedWasInsertedOrUpdated: return Name.persistedMessageReactionReceivedWasInsertedOrUpdated.name
			case .userWantsToUpdateDiscussionLocalConfiguration: return Name.userWantsToUpdateDiscussionLocalConfiguration.name
			case .persistedContactGroupHasUpdatedContactIdentities: return Name.persistedContactGroupHasUpdatedContactIdentities.name
			case .aReadOncePersistedMessageSentWasSent: return Name.aReadOncePersistedMessageSentWasSent.name
			case .newPersistedObvContactDevice: return Name.newPersistedObvContactDevice.name
			case .deletedPersistedObvContactDevice: return Name.deletedPersistedObvContactDevice.name
			case .persistedDiscussionHasNewTitle: return Name.persistedDiscussionHasNewTitle.name
			case .newLockedPersistedDiscussion: return Name.newLockedPersistedDiscussion.name
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
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .newDraftToSend(persistedDraftObjectID: let persistedDraftObjectID):
			info = [
				"persistedDraftObjectID": persistedDraftObjectID,
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
		case .persistedContactWasInserted(objectID: let objectID, contactCryptoId: let contactCryptoId):
			info = [
				"objectID": objectID,
				"contactCryptoId": contactCryptoId,
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
		case .aOneToOneDiscussionTitleNeedsToBeReset(ownedIdentityObjectID: let ownedIdentityObjectID):
			info = [
				"ownedIdentityObjectID": ownedIdentityObjectID,
			]
		case .newMessageExpiration(expirationDate: let expirationDate):
			info = [
				"expirationDate": expirationDate,
			]
		case .persistedMessageReactionReceivedWasDeleted(messageURI: let messageURI, contactURI: let contactURI):
			info = [
				"messageURI": messageURI,
				"contactURI": contactURI,
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
		case .aReadOncePersistedMessageSentWasSent(persistedMessageSentObjectID: let persistedMessageSentObjectID, persistedDiscussionObjectID: let persistedDiscussionObjectID):
			info = [
				"persistedMessageSentObjectID": persistedMessageSentObjectID,
				"persistedDiscussionObjectID": persistedDiscussionObjectID,
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
		case .newLockedPersistedDiscussion(previousDiscussionUriRepresentation: let previousDiscussionUriRepresentation, newLockedDiscussionId: let newLockedDiscussionId):
			info = [
				"previousDiscussionUriRepresentation": previousDiscussionUriRepresentation,
				"newLockedDiscussionId": newLockedDiscussionId,
			]
		case .persistedDiscussionWasDeleted(discussionUriRepresentation: let discussionUriRepresentation):
			info = [
				"discussionUriRepresentation": discussionUriRepresentation,
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
		case .persistedMessagesWereDeleted(discussionUriRepresentation: let discussionUriRepresentation, messageUriRepresentations: let messageUriRepresentations):
			info = [
				"discussionUriRepresentation": discussionUriRepresentation,
				"messageUriRepresentations": messageUriRepresentations,
			]
		case .persistedMessagesWereWiped(discussionUriRepresentation: let discussionUriRepresentation, messageUriRepresentations: let messageUriRepresentations):
			info = [
				"discussionUriRepresentation": discussionUriRepresentation,
				"messageUriRepresentations": messageUriRepresentations,
			]
		case .draftToSendWasReset(discussionObjectID: let discussionObjectID, draftObjectID: let draftObjectID):
			info = [
				"discussionObjectID": discussionObjectID,
				"draftObjectID": draftObjectID,
			]
		case .draftFyleJoinWasDeleted(discussionUriRepresentation: let discussionUriRepresentation, draftUriRepresentation: let draftUriRepresentation, draftFyleJoinUriRepresentation: let draftFyleJoinUriRepresentation):
			info = [
				"discussionUriRepresentation": discussionUriRepresentation,
				"draftUriRepresentation": draftUriRepresentation,
				"draftFyleJoinUriRepresentation": draftFyleJoinUriRepresentation,
			]
		case .fyleMessageJoinWasWiped(discussionUriRepresentation: let discussionUriRepresentation, messageUriRepresentation: let messageUriRepresentation, fyleMessageJoinUriRepresentation: let fyleMessageJoinUriRepresentation):
			info = [
				"discussionUriRepresentation": discussionUriRepresentation,
				"messageUriRepresentation": messageUriRepresentation,
				"fyleMessageJoinUriRepresentation": fyleMessageJoinUriRepresentation,
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

	static func observeNewDraftToSend(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDraft>) -> Void) -> NSObjectProtocol {
		let name = Name.newDraftToSend.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedDraftObjectID = notification.userInfo!["persistedDraftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			block(persistedDraftObjectID)
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

	static func observePersistedContactWasInserted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactWasInserted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! NSManagedObjectID
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			block(objectID, contactCryptoId)
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

	static func observeAOneToOneDiscussionTitleNeedsToBeReset(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedObvOwnedIdentity>) -> Void) -> NSObjectProtocol {
		let name = Name.aOneToOneDiscussionTitleNeedsToBeReset.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentityObjectID = notification.userInfo!["ownedIdentityObjectID"] as! TypeSafeManagedObjectID<PersistedObvOwnedIdentity>
			block(ownedIdentityObjectID)
		}
	}

	static func observeNewMessageExpiration(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Date) -> Void) -> NSObjectProtocol {
		let name = Name.newMessageExpiration.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let expirationDate = notification.userInfo!["expirationDate"] as! Date
			block(expirationDate)
		}
	}

	static func observePersistedMessageReactionReceivedWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (URL, URL) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageReactionReceivedWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let messageURI = notification.userInfo!["messageURI"] as! URL
			let contactURI = notification.userInfo!["contactURI"] as! URL
			block(messageURI, contactURI)
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

	static func observeAReadOncePersistedMessageSentWasSent(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, TypeSafeManagedObjectID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.aReadOncePersistedMessageSentWasSent.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageSentObjectID = notification.userInfo!["persistedMessageSentObjectID"] as! NSManagedObjectID
			let persistedDiscussionObjectID = notification.userInfo!["persistedDiscussionObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			block(persistedMessageSentObjectID, persistedDiscussionObjectID)
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

	static func observeNewLockedPersistedDiscussion(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeURL<PersistedDiscussion>, TypeSafeManagedObjectID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.newLockedPersistedDiscussion.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let previousDiscussionUriRepresentation = notification.userInfo!["previousDiscussionUriRepresentation"] as! TypeSafeURL<PersistedDiscussion>
			let newLockedDiscussionId = notification.userInfo!["newLockedDiscussionId"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			block(previousDiscussionUriRepresentation, newLockedDiscussionId)
		}
	}

	static func observePersistedDiscussionWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeURL<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedDiscussionWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionUriRepresentation = notification.userInfo!["discussionUriRepresentation"] as! TypeSafeURL<PersistedDiscussion>
			block(discussionUriRepresentation)
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

	static func observePersistedMessagesWereDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeURL<PersistedDiscussion>, Set<TypeSafeURL<PersistedMessage>>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessagesWereDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionUriRepresentation = notification.userInfo!["discussionUriRepresentation"] as! TypeSafeURL<PersistedDiscussion>
			let messageUriRepresentations = notification.userInfo!["messageUriRepresentations"] as! Set<TypeSafeURL<PersistedMessage>>
			block(discussionUriRepresentation, messageUriRepresentations)
		}
	}

	static func observePersistedMessagesWereWiped(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeURL<PersistedDiscussion>, Set<TypeSafeURL<PersistedMessage>>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessagesWereWiped.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionUriRepresentation = notification.userInfo!["discussionUriRepresentation"] as! TypeSafeURL<PersistedDiscussion>
			let messageUriRepresentations = notification.userInfo!["messageUriRepresentations"] as! Set<TypeSafeURL<PersistedMessage>>
			block(discussionUriRepresentation, messageUriRepresentations)
		}
	}

	static func observeDraftToSendWasReset(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDiscussion>, TypeSafeManagedObjectID<PersistedDraft>) -> Void) -> NSObjectProtocol {
		let name = Name.draftToSendWasReset.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionObjectID = notification.userInfo!["discussionObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			let draftObjectID = notification.userInfo!["draftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			block(discussionObjectID, draftObjectID)
		}
	}

	static func observeDraftFyleJoinWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeURL<PersistedDiscussion>, TypeSafeURL<PersistedDraft>, TypeSafeURL<PersistedDraftFyleJoin>) -> Void) -> NSObjectProtocol {
		let name = Name.draftFyleJoinWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionUriRepresentation = notification.userInfo!["discussionUriRepresentation"] as! TypeSafeURL<PersistedDiscussion>
			let draftUriRepresentation = notification.userInfo!["draftUriRepresentation"] as! TypeSafeURL<PersistedDraft>
			let draftFyleJoinUriRepresentation = notification.userInfo!["draftFyleJoinUriRepresentation"] as! TypeSafeURL<PersistedDraftFyleJoin>
			block(discussionUriRepresentation, draftUriRepresentation, draftFyleJoinUriRepresentation)
		}
	}

	static func observeFyleMessageJoinWasWiped(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeURL<PersistedDiscussion>, TypeSafeURL<PersistedMessage>, TypeSafeURL<FyleMessageJoinWithStatus>) -> Void) -> NSObjectProtocol {
		let name = Name.fyleMessageJoinWasWiped.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionUriRepresentation = notification.userInfo!["discussionUriRepresentation"] as! TypeSafeURL<PersistedDiscussion>
			let messageUriRepresentation = notification.userInfo!["messageUriRepresentation"] as! TypeSafeURL<PersistedMessage>
			let fyleMessageJoinUriRepresentation = notification.userInfo!["fyleMessageJoinUriRepresentation"] as! TypeSafeURL<FyleMessageJoinWithStatus>
			block(discussionUriRepresentation, messageUriRepresentation, fyleMessageJoinUriRepresentation)
		}
	}

}

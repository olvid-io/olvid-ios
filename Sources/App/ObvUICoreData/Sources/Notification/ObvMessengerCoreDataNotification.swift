/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvUIObvCircledInitials

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
	case newMessageExpiration(expirationDate: Date)
	case persistedMessageReactionReceivedWasDeletedOnSentMessage(messagePermanentID: MessageSentPermanentID, contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>)
	case persistedMessageReactionReceivedWasInsertedOrUpdated(objectID: TypeSafeManagedObjectID<PersistedMessageReactionReceived>)
	case persistedContactGroupHasUpdatedContactIdentities(persistedContactGroupObjectID: NSManagedObjectID, insertedContacts: Set<PersistedObvContactIdentity>, removedContacts: Set<PersistedObvContactIdentity>)
	case aReadOncePersistedMessageSentWasSent(persistedMessageSentPermanentID: MessageSentPermanentID, persistedDiscussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>)
	case persistedDiscussionHasNewTitle(objectID: TypeSafeManagedObjectID<PersistedDiscussion>, title: String)
	case persistedDiscussionWasDeleted(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, objectIDOfDeletedDiscussion: TypeSafeManagedObjectID<PersistedDiscussion>)
	case ownedIdentityWasReactivated(ownedIdentityObjectID: NSManagedObjectID)
	case ownedIdentityWasDeactivated(ownedIdentityObjectID: NSManagedObjectID)
	case persistedMessageSystemWasDeleted(objectID: NSManagedObjectID, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
	case persistedMessagesWereDeleted(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>)
	case persistedMessagesWereWiped(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>)
	case persistedDiscussionStatusChanged(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, newStatus: PersistedDiscussion.Status)
	case persistedGroupV2UpdateIsFinished(objectID: TypeSafeManagedObjectID<PersistedGroupV2>, ownedCryptoId: ObvCryptoId, groupIdentifier: GroupV2Identifier)
	case ownedCircledInitialsConfigurationDidChange(ownedIdentityPermanentID: ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>, ownedCryptoId: ObvCryptoId, newOwnedCircledInitialsConfiguration: CircledInitialsConfiguration)
	case ownedIdentityHiddenStatusChanged(ownedCryptoId: ObvCryptoId, isHidden: Bool)
	case badgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity(ownedCryptoId: ObvCryptoId)
	case groupV2TrustedDetailsShouldBeReplacedByPublishedDetails(ownCryptoId: ObvCryptoId, groupIdentifier: GroupV2Identifier)
	case persistedMessageReceivedWasDeleted(objectID: NSManagedObjectID, messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, sortIndex: Double, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
	case theBodyOfPersistedMessageReceivedDidChange(persistedMessageReceivedObjectID: NSManagedObjectID)
	case persistedDiscussionWasArchived(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>)
	case fyleMessageJoinWithStatusWasInserted(fyleMessageJoinObjectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>)
	case fyleMessageJoinWithStatusWasUpdated(fyleMessageJoinObjectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>)
	case discussionLocalConfigurationHasBeenUpdated(newValue: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>)
	case statusOfSentFyleMessageJoinDidChange(sentJoinID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>, messageID: TypeSafeManagedObjectID<PersistedMessageSent>, discussionID: TypeSafeManagedObjectID<PersistedDiscussion>)
	case aSecureChannelWithContactDeviceWasJustCreated(contactDeviceObjectID: TypeSafeManagedObjectID<PersistedObvContactDevice>)

	private enum Name {
		case newMessageExpiration
		case persistedMessageReactionReceivedWasDeletedOnSentMessage
		case persistedMessageReactionReceivedWasInsertedOrUpdated
		case persistedContactGroupHasUpdatedContactIdentities
		case aReadOncePersistedMessageSentWasSent
		case persistedDiscussionHasNewTitle
		case persistedDiscussionWasDeleted
		case ownedIdentityWasReactivated
		case ownedIdentityWasDeactivated
		case persistedMessageSystemWasDeleted
		case persistedMessagesWereDeleted
		case persistedMessagesWereWiped
		case persistedDiscussionStatusChanged
		case persistedGroupV2UpdateIsFinished
		case ownedCircledInitialsConfigurationDidChange
		case ownedIdentityHiddenStatusChanged
		case badgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity
		case groupV2TrustedDetailsShouldBeReplacedByPublishedDetails
		case persistedMessageReceivedWasDeleted
		case theBodyOfPersistedMessageReceivedDidChange
		case persistedDiscussionWasArchived
		case fyleMessageJoinWithStatusWasInserted
		case fyleMessageJoinWithStatusWasUpdated
		case discussionLocalConfigurationHasBeenUpdated
		case statusOfSentFyleMessageJoinDidChange
		case aSecureChannelWithContactDeviceWasJustCreated

		private var namePrefix: String { String(describing: ObvMessengerCoreDataNotification.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ObvMessengerCoreDataNotification) -> NSNotification.Name {
			switch notification {
			case .newMessageExpiration: return Name.newMessageExpiration.name
			case .persistedMessageReactionReceivedWasDeletedOnSentMessage: return Name.persistedMessageReactionReceivedWasDeletedOnSentMessage.name
			case .persistedMessageReactionReceivedWasInsertedOrUpdated: return Name.persistedMessageReactionReceivedWasInsertedOrUpdated.name
			case .persistedContactGroupHasUpdatedContactIdentities: return Name.persistedContactGroupHasUpdatedContactIdentities.name
			case .aReadOncePersistedMessageSentWasSent: return Name.aReadOncePersistedMessageSentWasSent.name
			case .persistedDiscussionHasNewTitle: return Name.persistedDiscussionHasNewTitle.name
			case .persistedDiscussionWasDeleted: return Name.persistedDiscussionWasDeleted.name
			case .ownedIdentityWasReactivated: return Name.ownedIdentityWasReactivated.name
			case .ownedIdentityWasDeactivated: return Name.ownedIdentityWasDeactivated.name
			case .persistedMessageSystemWasDeleted: return Name.persistedMessageSystemWasDeleted.name
			case .persistedMessagesWereDeleted: return Name.persistedMessagesWereDeleted.name
			case .persistedMessagesWereWiped: return Name.persistedMessagesWereWiped.name
			case .persistedDiscussionStatusChanged: return Name.persistedDiscussionStatusChanged.name
			case .persistedGroupV2UpdateIsFinished: return Name.persistedGroupV2UpdateIsFinished.name
			case .ownedCircledInitialsConfigurationDidChange: return Name.ownedCircledInitialsConfigurationDidChange.name
			case .ownedIdentityHiddenStatusChanged: return Name.ownedIdentityHiddenStatusChanged.name
			case .badgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity: return Name.badgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity.name
			case .groupV2TrustedDetailsShouldBeReplacedByPublishedDetails: return Name.groupV2TrustedDetailsShouldBeReplacedByPublishedDetails.name
			case .persistedMessageReceivedWasDeleted: return Name.persistedMessageReceivedWasDeleted.name
			case .theBodyOfPersistedMessageReceivedDidChange: return Name.theBodyOfPersistedMessageReceivedDidChange.name
			case .persistedDiscussionWasArchived: return Name.persistedDiscussionWasArchived.name
			case .fyleMessageJoinWithStatusWasInserted: return Name.fyleMessageJoinWithStatusWasInserted.name
			case .fyleMessageJoinWithStatusWasUpdated: return Name.fyleMessageJoinWithStatusWasUpdated.name
			case .discussionLocalConfigurationHasBeenUpdated: return Name.discussionLocalConfigurationHasBeenUpdated.name
			case .statusOfSentFyleMessageJoinDidChange: return Name.statusOfSentFyleMessageJoinDidChange.name
			case .aSecureChannelWithContactDeviceWasJustCreated: return Name.aSecureChannelWithContactDeviceWasJustCreated.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
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
		case .ownedIdentityWasReactivated(ownedIdentityObjectID: let ownedIdentityObjectID):
			info = [
				"ownedIdentityObjectID": ownedIdentityObjectID,
			]
		case .ownedIdentityWasDeactivated(ownedIdentityObjectID: let ownedIdentityObjectID):
			info = [
				"ownedIdentityObjectID": ownedIdentityObjectID,
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
		case .persistedGroupV2UpdateIsFinished(objectID: let objectID, ownedCryptoId: let ownedCryptoId, groupIdentifier: let groupIdentifier):
			info = [
				"objectID": objectID,
				"ownedCryptoId": ownedCryptoId,
				"groupIdentifier": groupIdentifier,
			]
		case .ownedCircledInitialsConfigurationDidChange(ownedIdentityPermanentID: let ownedIdentityPermanentID, ownedCryptoId: let ownedCryptoId, newOwnedCircledInitialsConfiguration: let newOwnedCircledInitialsConfiguration):
			info = [
				"ownedIdentityPermanentID": ownedIdentityPermanentID,
				"ownedCryptoId": ownedCryptoId,
				"newOwnedCircledInitialsConfiguration": newOwnedCircledInitialsConfiguration,
			]
		case .ownedIdentityHiddenStatusChanged(ownedCryptoId: let ownedCryptoId, isHidden: let isHidden):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"isHidden": isHidden,
			]
		case .badgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .groupV2TrustedDetailsShouldBeReplacedByPublishedDetails(ownCryptoId: let ownCryptoId, groupIdentifier: let groupIdentifier):
			info = [
				"ownCryptoId": ownCryptoId,
				"groupIdentifier": groupIdentifier,
			]
		case .persistedMessageReceivedWasDeleted(objectID: let objectID, messageIdentifierFromEngine: let messageIdentifierFromEngine, ownedCryptoId: let ownedCryptoId, sortIndex: let sortIndex, discussionObjectID: let discussionObjectID):
			info = [
				"objectID": objectID,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"ownedCryptoId": ownedCryptoId,
				"sortIndex": sortIndex,
				"discussionObjectID": discussionObjectID,
			]
		case .theBodyOfPersistedMessageReceivedDidChange(persistedMessageReceivedObjectID: let persistedMessageReceivedObjectID):
			info = [
				"persistedMessageReceivedObjectID": persistedMessageReceivedObjectID,
			]
		case .persistedDiscussionWasArchived(discussionPermanentID: let discussionPermanentID):
			info = [
				"discussionPermanentID": discussionPermanentID,
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
		case .statusOfSentFyleMessageJoinDidChange(sentJoinID: let sentJoinID, messageID: let messageID, discussionID: let discussionID):
			info = [
				"sentJoinID": sentJoinID,
				"messageID": messageID,
				"discussionID": discussionID,
			]
		case .aSecureChannelWithContactDeviceWasJustCreated(contactDeviceObjectID: let contactDeviceObjectID):
			info = [
				"contactDeviceObjectID": contactDeviceObjectID,
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
		// The payload crosses to the posting queue unchecked: it is `Any`, and each notification's author decides what it may carry.
		nonisolated(unsafe) let userInfo = self.userInfo
		queue.async {
			NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
		}
	}

	private func postOnDispatchQueue(withLabel label: String, object anObject: Any? = nil) {
		let name = Name.forInternalNotification(self)
		// The payload crosses to the posting queue unchecked: it is `Any`, and each notification's author decides what it may carry.
		nonisolated(unsafe) let userInfo = self.userInfo
		nonisolated(unsafe) let anObject = anObject
		DispatchQueue(label: label).async {
			NotificationCenter.default.post(name: name, object: anObject, userInfo: userInfo)
		}
	}

	public static func observeNewMessageExpiration(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Date) -> Void) -> NSObjectProtocol {
		let name = Name.newMessageExpiration.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let expirationDate = notification.userInfo!["expirationDate"] as! Date
			block(expirationDate)
		}
	}

	public static func observePersistedMessageReactionReceivedWasDeletedOnSentMessage(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (MessageSentPermanentID, ObvManagedObjectPermanentID<PersistedObvContactIdentity>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageReactionReceivedWasDeletedOnSentMessage.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let messagePermanentID = notification.userInfo!["messagePermanentID"] as! MessageSentPermanentID
			let contactPermanentID = notification.userInfo!["contactPermanentID"] as! ObvManagedObjectPermanentID<PersistedObvContactIdentity>
			block(messagePermanentID, contactPermanentID)
		}
	}

	public static func observePersistedMessageReactionReceivedWasInsertedOrUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedMessageReactionReceived>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageReactionReceivedWasInsertedOrUpdated.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! TypeSafeManagedObjectID<PersistedMessageReactionReceived>
			block(objectID)
		}
	}

	public static func observePersistedContactGroupHasUpdatedContactIdentities(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, Set<PersistedObvContactIdentity>, Set<PersistedObvContactIdentity>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactGroupHasUpdatedContactIdentities.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedContactGroupObjectID = notification.userInfo!["persistedContactGroupObjectID"] as! NSManagedObjectID
			let insertedContacts = notification.userInfo!["insertedContacts"] as! Set<PersistedObvContactIdentity>
			let removedContacts = notification.userInfo!["removedContacts"] as! Set<PersistedObvContactIdentity>
			block(persistedContactGroupObjectID, insertedContacts, removedContacts)
		}
	}

	public static func observeAReadOncePersistedMessageSentWasSent(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (MessageSentPermanentID, ObvManagedObjectPermanentID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.aReadOncePersistedMessageSentWasSent.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageSentPermanentID = notification.userInfo!["persistedMessageSentPermanentID"] as! MessageSentPermanentID
			let persistedDiscussionPermanentID = notification.userInfo!["persistedDiscussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			block(persistedMessageSentPermanentID, persistedDiscussionPermanentID)
		}
	}

	public static func observePersistedDiscussionHasNewTitle(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDiscussion>, String) -> Void) -> NSObjectProtocol {
		let name = Name.persistedDiscussionHasNewTitle.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			let title = notification.userInfo!["title"] as! String
			block(objectID, title)
		}
	}

	public static func observePersistedDiscussionWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, TypeSafeManagedObjectID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedDiscussionWasDeleted.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let objectIDOfDeletedDiscussion = notification.userInfo!["objectIDOfDeletedDiscussion"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			block(discussionPermanentID, objectIDOfDeletedDiscussion)
		}
	}

	public static func observeOwnedIdentityWasReactivated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityWasReactivated.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentityObjectID = notification.userInfo!["ownedIdentityObjectID"] as! NSManagedObjectID
			block(ownedIdentityObjectID)
		}
	}

	public static func observeOwnedIdentityWasDeactivated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityWasDeactivated.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentityObjectID = notification.userInfo!["ownedIdentityObjectID"] as! NSManagedObjectID
			block(ownedIdentityObjectID)
		}
	}

	public static func observePersistedMessageSystemWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, TypeSafeManagedObjectID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageSystemWasDeleted.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! NSManagedObjectID
			let discussionObjectID = notification.userInfo!["discussionObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			block(objectID, discussionObjectID)
		}
	}

	public static func observePersistedMessagesWereDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, Set<ObvManagedObjectPermanentID<PersistedMessage>>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessagesWereDeleted.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let messagePermanentIDs = notification.userInfo!["messagePermanentIDs"] as! Set<ObvManagedObjectPermanentID<PersistedMessage>>
			block(discussionPermanentID, messagePermanentIDs)
		}
	}

	public static func observePersistedMessagesWereWiped(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, Set<ObvManagedObjectPermanentID<PersistedMessage>>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessagesWereWiped.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let messagePermanentIDs = notification.userInfo!["messagePermanentIDs"] as! Set<ObvManagedObjectPermanentID<PersistedMessage>>
			block(discussionPermanentID, messagePermanentIDs)
		}
	}

	public static func observePersistedDiscussionStatusChanged(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, PersistedDiscussion.Status) -> Void) -> NSObjectProtocol {
		let name = Name.persistedDiscussionStatusChanged.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let newStatus = notification.userInfo!["newStatus"] as! PersistedDiscussion.Status
			block(discussionPermanentID, newStatus)
		}
	}

	public static func observePersistedGroupV2UpdateIsFinished(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedGroupV2>, ObvCryptoId, GroupV2Identifier) -> Void) -> NSObjectProtocol {
		let name = Name.persistedGroupV2UpdateIsFinished.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! TypeSafeManagedObjectID<PersistedGroupV2>
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let groupIdentifier = notification.userInfo!["groupIdentifier"] as! GroupV2Identifier
			block(objectID, ownedCryptoId, groupIdentifier)
		}
	}

	public static func observeOwnedCircledInitialsConfigurationDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>, ObvCryptoId, CircledInitialsConfiguration) -> Void) -> NSObjectProtocol {
		let name = Name.ownedCircledInitialsConfigurationDidChange.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentityPermanentID = notification.userInfo!["ownedIdentityPermanentID"] as! ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let newOwnedCircledInitialsConfiguration = notification.userInfo!["newOwnedCircledInitialsConfiguration"] as! CircledInitialsConfiguration
			block(ownedIdentityPermanentID, ownedCryptoId, newOwnedCircledInitialsConfiguration)
		}
	}

	public static func observeOwnedIdentityHiddenStatusChanged(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Bool) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityHiddenStatusChanged.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let isHidden = notification.userInfo!["isHidden"] as! Bool
			block(ownedCryptoId, isHidden)
		}
	}

	public static func observeBadgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.badgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(ownedCryptoId)
		}
	}

	public static func observeGroupV2TrustedDetailsShouldBeReplacedByPublishedDetails(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, GroupV2Identifier) -> Void) -> NSObjectProtocol {
		let name = Name.groupV2TrustedDetailsShouldBeReplacedByPublishedDetails.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownCryptoId = notification.userInfo!["ownCryptoId"] as! ObvCryptoId
			let groupIdentifier = notification.userInfo!["groupIdentifier"] as! GroupV2Identifier
			block(ownCryptoId, groupIdentifier)
		}
	}

	public static func observePersistedMessageReceivedWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, Data, ObvCryptoId, Double, TypeSafeManagedObjectID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageReceivedWasDeleted.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! NSManagedObjectID
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let sortIndex = notification.userInfo!["sortIndex"] as! Double
			let discussionObjectID = notification.userInfo!["discussionObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			block(objectID, messageIdentifierFromEngine, ownedCryptoId, sortIndex, discussionObjectID)
		}
	}

	public static func observeTheBodyOfPersistedMessageReceivedDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.theBodyOfPersistedMessageReceivedDidChange.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageReceivedObjectID = notification.userInfo!["persistedMessageReceivedObjectID"] as! NSManagedObjectID
			block(persistedMessageReceivedObjectID)
		}
	}

	public static func observePersistedDiscussionWasArchived(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedDiscussionWasArchived.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			block(discussionPermanentID)
		}
	}

	public static func observeFyleMessageJoinWithStatusWasInserted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) -> Void) -> NSObjectProtocol {
		let name = Name.fyleMessageJoinWithStatusWasInserted.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let fyleMessageJoinObjectID = notification.userInfo!["fyleMessageJoinObjectID"] as! TypeSafeManagedObjectID<FyleMessageJoinWithStatus>
			block(fyleMessageJoinObjectID)
		}
	}

	public static func observeFyleMessageJoinWithStatusWasUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) -> Void) -> NSObjectProtocol {
		let name = Name.fyleMessageJoinWithStatusWasUpdated.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let fyleMessageJoinObjectID = notification.userInfo!["fyleMessageJoinObjectID"] as! TypeSafeManagedObjectID<FyleMessageJoinWithStatus>
			block(fyleMessageJoinObjectID)
		}
	}

	public static func observeDiscussionLocalConfigurationHasBeenUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (PersistedDiscussionLocalConfigurationValue, TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) -> Void) -> NSObjectProtocol {
		let name = Name.discussionLocalConfigurationHasBeenUpdated.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let newValue = notification.userInfo!["newValue"] as! PersistedDiscussionLocalConfigurationValue
			let localConfigurationObjectID = notification.userInfo!["localConfigurationObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>
			block(newValue, localConfigurationObjectID)
		}
	}

	public static func observeStatusOfSentFyleMessageJoinDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>, TypeSafeManagedObjectID<PersistedMessageSent>, TypeSafeManagedObjectID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.statusOfSentFyleMessageJoinDidChange.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let sentJoinID = notification.userInfo!["sentJoinID"] as! TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>
			let messageID = notification.userInfo!["messageID"] as! TypeSafeManagedObjectID<PersistedMessageSent>
			let discussionID = notification.userInfo!["discussionID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			block(sentJoinID, messageID, discussionID)
		}
	}

	public static func observeASecureChannelWithContactDeviceWasJustCreated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedObvContactDevice>) -> Void) -> NSObjectProtocol {
		let name = Name.aSecureChannelWithContactDeviceWasJustCreated.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactDeviceObjectID = notification.userInfo!["contactDeviceObjectID"] as! TypeSafeManagedObjectID<PersistedObvContactDevice>
			block(contactDeviceObjectID)
		}
	}

}

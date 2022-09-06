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
import PhotosUI

fileprivate struct OptionalWrapper<T> {
	let value: T?
	public init() {
		self.value = nil
	}
	public init(_ value: T?) {
		self.value = value
	}
}

enum NewSingleDiscussionNotification {
	case userWantsToReadReceivedMessagesThatRequiresUserAction(persistedMessageObjectIDs: Set<NSManagedObjectID>)
	case userWantsToAddAttachmentsToDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, itemProviders: [NSItemProvider], completionHandler: (Bool) -> Void)
	case userWantsToAddAttachmentsToDraftFromURLs(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, urls: [URL], completionHandler: (Bool) -> Void)
	case userWantsToDeleteAllAttachmentsToDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>)
	case userWantsToReplyToMessage(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>)
	case userWantsToRemoveReplyToMessage(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>)
	case userWantsToSendDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, textBody: String)
	case userWantsToSendDraftWithOneAttachement(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, attachementsURL: [URL])
	case insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, markAsRead: Bool)
	case userWantsToUpdateDraftExpiration(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?)
	case userWantsToUpdateDraftBody(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, body: String)
	case draftCouldNotBeSent(persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>)
	case userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>)
	case userWantsToDownloadReceivedFyleMessageJoinWithStatus(receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>)

	private enum Name {
		case userWantsToReadReceivedMessagesThatRequiresUserAction
		case userWantsToAddAttachmentsToDraft
		case userWantsToAddAttachmentsToDraftFromURLs
		case userWantsToDeleteAllAttachmentsToDraft
		case userWantsToReplyToMessage
		case userWantsToRemoveReplyToMessage
		case userWantsToSendDraft
		case userWantsToSendDraftWithOneAttachement
		case insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty
		case userWantsToUpdateDraftExpiration
		case userWantsToUpdateDraftBody
		case draftCouldNotBeSent
		case userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus
		case userWantsToDownloadReceivedFyleMessageJoinWithStatus

		private var namePrefix: String { String(describing: NewSingleDiscussionNotification.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: NewSingleDiscussionNotification) -> NSNotification.Name {
			switch notification {
			case .userWantsToReadReceivedMessagesThatRequiresUserAction: return Name.userWantsToReadReceivedMessagesThatRequiresUserAction.name
			case .userWantsToAddAttachmentsToDraft: return Name.userWantsToAddAttachmentsToDraft.name
			case .userWantsToAddAttachmentsToDraftFromURLs: return Name.userWantsToAddAttachmentsToDraftFromURLs.name
			case .userWantsToDeleteAllAttachmentsToDraft: return Name.userWantsToDeleteAllAttachmentsToDraft.name
			case .userWantsToReplyToMessage: return Name.userWantsToReplyToMessage.name
			case .userWantsToRemoveReplyToMessage: return Name.userWantsToRemoveReplyToMessage.name
			case .userWantsToSendDraft: return Name.userWantsToSendDraft.name
			case .userWantsToSendDraftWithOneAttachement: return Name.userWantsToSendDraftWithOneAttachement.name
			case .insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty: return Name.insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty.name
			case .userWantsToUpdateDraftExpiration: return Name.userWantsToUpdateDraftExpiration.name
			case .userWantsToUpdateDraftBody: return Name.userWantsToUpdateDraftBody.name
			case .draftCouldNotBeSent: return Name.draftCouldNotBeSent.name
			case .userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus: return Name.userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus.name
			case .userWantsToDownloadReceivedFyleMessageJoinWithStatus: return Name.userWantsToDownloadReceivedFyleMessageJoinWithStatus.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .userWantsToReadReceivedMessagesThatRequiresUserAction(persistedMessageObjectIDs: let persistedMessageObjectIDs):
			info = [
				"persistedMessageObjectIDs": persistedMessageObjectIDs,
			]
		case .userWantsToAddAttachmentsToDraft(draftObjectID: let draftObjectID, itemProviders: let itemProviders, completionHandler: let completionHandler):
			info = [
				"draftObjectID": draftObjectID,
				"itemProviders": itemProviders,
				"completionHandler": completionHandler,
			]
		case .userWantsToAddAttachmentsToDraftFromURLs(draftObjectID: let draftObjectID, urls: let urls, completionHandler: let completionHandler):
			info = [
				"draftObjectID": draftObjectID,
				"urls": urls,
				"completionHandler": completionHandler,
			]
		case .userWantsToDeleteAllAttachmentsToDraft(draftObjectID: let draftObjectID):
			info = [
				"draftObjectID": draftObjectID,
			]
		case .userWantsToReplyToMessage(messageObjectID: let messageObjectID, draftObjectID: let draftObjectID):
			info = [
				"messageObjectID": messageObjectID,
				"draftObjectID": draftObjectID,
			]
		case .userWantsToRemoveReplyToMessage(draftObjectID: let draftObjectID):
			info = [
				"draftObjectID": draftObjectID,
			]
		case .userWantsToSendDraft(draftObjectID: let draftObjectID, textBody: let textBody):
			info = [
				"draftObjectID": draftObjectID,
				"textBody": textBody,
			]
		case .userWantsToSendDraftWithOneAttachement(draftObjectID: let draftObjectID, attachementsURL: let attachementsURL):
			info = [
				"draftObjectID": draftObjectID,
				"attachementsURL": attachementsURL,
			]
		case .insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(discussionObjectID: let discussionObjectID, markAsRead: let markAsRead):
			info = [
				"discussionObjectID": discussionObjectID,
				"markAsRead": markAsRead,
			]
		case .userWantsToUpdateDraftExpiration(draftObjectID: let draftObjectID, value: let value):
			info = [
				"draftObjectID": draftObjectID,
				"value": OptionalWrapper(value),
			]
		case .userWantsToUpdateDraftBody(draftObjectID: let draftObjectID, body: let body):
			info = [
				"draftObjectID": draftObjectID,
				"body": body,
			]
		case .draftCouldNotBeSent(persistedDraftObjectID: let persistedDraftObjectID):
			info = [
				"persistedDraftObjectID": persistedDraftObjectID,
			]
		case .userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(receivedJoinObjectID: let receivedJoinObjectID):
			info = [
				"receivedJoinObjectID": receivedJoinObjectID,
			]
		case .userWantsToDownloadReceivedFyleMessageJoinWithStatus(receivedJoinObjectID: let receivedJoinObjectID):
			info = [
				"receivedJoinObjectID": receivedJoinObjectID,
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

	static func observeUserWantsToReadReceivedMessagesThatRequiresUserAction(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Set<NSManagedObjectID>) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToReadReceivedMessagesThatRequiresUserAction.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageObjectIDs = notification.userInfo!["persistedMessageObjectIDs"] as! Set<NSManagedObjectID>
			block(persistedMessageObjectIDs)
		}
	}

	static func observeUserWantsToAddAttachmentsToDraft(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDraft>, [NSItemProvider], @escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToAddAttachmentsToDraft.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let draftObjectID = notification.userInfo!["draftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			let itemProviders = notification.userInfo!["itemProviders"] as! [NSItemProvider]
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(draftObjectID, itemProviders, completionHandler)
		}
	}

	static func observeUserWantsToAddAttachmentsToDraftFromURLs(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDraft>, [URL], @escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToAddAttachmentsToDraftFromURLs.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let draftObjectID = notification.userInfo!["draftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			let urls = notification.userInfo!["urls"] as! [URL]
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(draftObjectID, urls, completionHandler)
		}
	}

	static func observeUserWantsToDeleteAllAttachmentsToDraft(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDraft>) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToDeleteAllAttachmentsToDraft.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let draftObjectID = notification.userInfo!["draftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			block(draftObjectID)
		}
	}

	static func observeUserWantsToReplyToMessage(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedMessage>, TypeSafeManagedObjectID<PersistedDraft>) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToReplyToMessage.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let messageObjectID = notification.userInfo!["messageObjectID"] as! TypeSafeManagedObjectID<PersistedMessage>
			let draftObjectID = notification.userInfo!["draftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			block(messageObjectID, draftObjectID)
		}
	}

	static func observeUserWantsToRemoveReplyToMessage(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDraft>) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToRemoveReplyToMessage.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let draftObjectID = notification.userInfo!["draftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			block(draftObjectID)
		}
	}

	static func observeUserWantsToSendDraft(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDraft>, String) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToSendDraft.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let draftObjectID = notification.userInfo!["draftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			let textBody = notification.userInfo!["textBody"] as! String
			block(draftObjectID, textBody)
		}
	}

	static func observeUserWantsToSendDraftWithOneAttachement(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDraft>, [URL]) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToSendDraftWithOneAttachement.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let draftObjectID = notification.userInfo!["draftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			let attachementsURL = notification.userInfo!["attachementsURL"] as! [URL]
			block(draftObjectID, attachementsURL)
		}
	}

	static func observeInsertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDiscussion>, Bool) -> Void) -> NSObjectProtocol {
		let name = Name.insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionObjectID = notification.userInfo!["discussionObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			let markAsRead = notification.userInfo!["markAsRead"] as! Bool
			block(discussionObjectID, markAsRead)
		}
	}

	static func observeUserWantsToUpdateDraftExpiration(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDraft>, PersistedDiscussionSharedConfigurationValue?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUpdateDraftExpiration.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let draftObjectID = notification.userInfo!["draftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			let valueWrapper = notification.userInfo!["value"] as! OptionalWrapper<PersistedDiscussionSharedConfigurationValue>
			let value = valueWrapper.value
			block(draftObjectID, value)
		}
	}

	static func observeUserWantsToUpdateDraftBody(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDraft>, String) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUpdateDraftBody.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let draftObjectID = notification.userInfo!["draftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			let body = notification.userInfo!["body"] as! String
			block(draftObjectID, body)
		}
	}

	static func observeDraftCouldNotBeSent(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDraft>) -> Void) -> NSObjectProtocol {
		let name = Name.draftCouldNotBeSent.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedDraftObjectID = notification.userInfo!["persistedDraftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			block(persistedDraftObjectID)
		}
	}

	static func observeUserWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let receivedJoinObjectID = notification.userInfo!["receivedJoinObjectID"] as! TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>
			block(receivedJoinObjectID)
		}
	}

	static func observeUserWantsToDownloadReceivedFyleMessageJoinWithStatus(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToDownloadReceivedFyleMessageJoinWithStatus.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let receivedJoinObjectID = notification.userInfo!["receivedJoinObjectID"] as! TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>
			block(receivedJoinObjectID)
		}
	}

}

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
import ObvTypes
import ObvEngine
import OlvidUtils
import ObvCrypto

fileprivate struct OptionalWrapper<T> {
	let value: T?
	public init() {
		self.value = nil
	}
	public init(_ value: T?) {
		self.value = value
	}
}

enum PersistedMessageReceivedNotification {
	case persistedMessageReceivedWasDeleted(objectID: NSManagedObjectID, messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, sortIndex: Double, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
	case persistedMessageReceivedWasRead(persistedMessageReceivedObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>)
	case aDeliveredReturnReceiptShouldBeSentForPersistedMessageReceived(returnReceipt: ReturnReceiptJSON, contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data)
	case theBodyOfPersistedMessageReceivedDidChange(persistedMessageReceivedObjectID: NSManagedObjectID)

	private enum Name {
		case persistedMessageReceivedWasDeleted
		case persistedMessageReceivedWasRead
		case aDeliveredReturnReceiptShouldBeSentForPersistedMessageReceived
		case theBodyOfPersistedMessageReceivedDidChange

		private var namePrefix: String { String(describing: PersistedMessageReceivedNotification.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: PersistedMessageReceivedNotification) -> NSNotification.Name {
			switch notification {
			case .persistedMessageReceivedWasDeleted: return Name.persistedMessageReceivedWasDeleted.name
			case .persistedMessageReceivedWasRead: return Name.persistedMessageReceivedWasRead.name
			case .aDeliveredReturnReceiptShouldBeSentForPersistedMessageReceived: return Name.aDeliveredReturnReceiptShouldBeSentForPersistedMessageReceived.name
			case .theBodyOfPersistedMessageReceivedDidChange: return Name.theBodyOfPersistedMessageReceivedDidChange.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
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

	static func observePersistedMessageReceivedWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, Data, ObvCryptoId, Double, TypeSafeManagedObjectID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
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

	static func observePersistedMessageReceivedWasRead(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedMessageReceived>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageReceivedWasRead.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageReceivedObjectID = notification.userInfo!["persistedMessageReceivedObjectID"] as! TypeSafeManagedObjectID<PersistedMessageReceived>
			block(persistedMessageReceivedObjectID)
		}
	}

	static func observeADeliveredReturnReceiptShouldBeSentForPersistedMessageReceived(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ReturnReceiptJSON, ObvCryptoId, ObvCryptoId, Data) -> Void) -> NSObjectProtocol {
		let name = Name.aDeliveredReturnReceiptShouldBeSentForPersistedMessageReceived.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let returnReceipt = notification.userInfo!["returnReceipt"] as! ReturnReceiptJSON
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			block(returnReceipt, contactCryptoId, ownedCryptoId, messageIdentifierFromEngine)
		}
	}

	static func observeTheBodyOfPersistedMessageReceivedDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.theBodyOfPersistedMessageReceivedDidChange.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageReceivedObjectID = notification.userInfo!["persistedMessageReceivedObjectID"] as! NSManagedObjectID
			block(persistedMessageReceivedObjectID)
		}
	}

}

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

enum ReceivedFyleMessageJoinWithStatusNotifications {
	case receivedFyleJoinHasBeenMarkAsOpened(receivedFyleJoinID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>)
	case aDeliveredReturnReceiptShouldBeSentForAReceivedFyleMessageJoinWithStatus(returnReceipt: ReturnReceiptJSON, contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int)

	private enum Name {
		case receivedFyleJoinHasBeenMarkAsOpened
		case aDeliveredReturnReceiptShouldBeSentForAReceivedFyleMessageJoinWithStatus

		private var namePrefix: String { String(describing: ReceivedFyleMessageJoinWithStatusNotifications.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ReceivedFyleMessageJoinWithStatusNotifications) -> NSNotification.Name {
			switch notification {
			case .receivedFyleJoinHasBeenMarkAsOpened: return Name.receivedFyleJoinHasBeenMarkAsOpened.name
			case .aDeliveredReturnReceiptShouldBeSentForAReceivedFyleMessageJoinWithStatus: return Name.aDeliveredReturnReceiptShouldBeSentForAReceivedFyleMessageJoinWithStatus.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
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

	static func observeReceivedFyleJoinHasBeenMarkAsOpened(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) -> Void) -> NSObjectProtocol {
		let name = Name.receivedFyleJoinHasBeenMarkAsOpened.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let receivedFyleJoinID = notification.userInfo!["receivedFyleJoinID"] as! TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>
			block(receivedFyleJoinID)
		}
	}

	static func observeADeliveredReturnReceiptShouldBeSentForAReceivedFyleMessageJoinWithStatus(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ReturnReceiptJSON, ObvCryptoId, ObvCryptoId, Data, Int) -> Void) -> NSObjectProtocol {
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

}

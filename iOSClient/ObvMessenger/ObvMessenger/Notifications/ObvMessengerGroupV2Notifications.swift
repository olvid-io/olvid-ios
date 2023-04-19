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

enum ObvMessengerGroupV2Notifications {
	case groupV2TrustedDetailsShouldBeReplacedByPublishedDetails(ownCryptoId: ObvCryptoId, groupIdentifier: Data)
	case displayedContactGroupWasJustCreated(permanentID: ObvManagedObjectPermanentID<DisplayedContactGroup>)

	private enum Name {
		case groupV2TrustedDetailsShouldBeReplacedByPublishedDetails
		case displayedContactGroupWasJustCreated

		private var namePrefix: String { String(describing: ObvMessengerGroupV2Notifications.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ObvMessengerGroupV2Notifications) -> NSNotification.Name {
			switch notification {
			case .groupV2TrustedDetailsShouldBeReplacedByPublishedDetails: return Name.groupV2TrustedDetailsShouldBeReplacedByPublishedDetails.name
			case .displayedContactGroupWasJustCreated: return Name.displayedContactGroupWasJustCreated.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .groupV2TrustedDetailsShouldBeReplacedByPublishedDetails(ownCryptoId: let ownCryptoId, groupIdentifier: let groupIdentifier):
			info = [
				"ownCryptoId": ownCryptoId,
				"groupIdentifier": groupIdentifier,
			]
		case .displayedContactGroupWasJustCreated(permanentID: let permanentID):
			info = [
				"permanentID": permanentID,
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

	static func observeGroupV2TrustedDetailsShouldBeReplacedByPublishedDetails(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Data) -> Void) -> NSObjectProtocol {
		let name = Name.groupV2TrustedDetailsShouldBeReplacedByPublishedDetails.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownCryptoId = notification.userInfo!["ownCryptoId"] as! ObvCryptoId
			let groupIdentifier = notification.userInfo!["groupIdentifier"] as! Data
			block(ownCryptoId, groupIdentifier)
		}
	}

	static func observeDisplayedContactGroupWasJustCreated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<DisplayedContactGroup>) -> Void) -> NSObjectProtocol {
		let name = Name.displayedContactGroupWasJustCreated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let permanentID = notification.userInfo!["permanentID"] as! ObvManagedObjectPermanentID<DisplayedContactGroup>
			block(permanentID)
		}
	}

}

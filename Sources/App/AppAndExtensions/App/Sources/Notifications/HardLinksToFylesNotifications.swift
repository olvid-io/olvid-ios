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
import ObvUICoreData

fileprivate struct OptionalWrapper<T> {
	let value: T?
	public init() {
		self.value = nil
	}
	public init(_ value: T?) {
		self.value = value
	}
}

enum HardLinksToFylesNotifications {
	case requestHardLinkToFyle(fyleElement: FyleElement, completionHandler: (@Sendable (Result<HardLinkToFyle,Error>) -> Void))
	case requestAllHardLinksToFyles(fyleElements: [FyleElement], completionHandler: (@Sendable ([HardLinkToFyle?]) -> Void))

	private enum Name {
		case requestHardLinkToFyle
		case requestAllHardLinksToFyles

		private var namePrefix: String { String(describing: HardLinksToFylesNotifications.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: HardLinksToFylesNotifications) -> NSNotification.Name {
			switch notification {
			case .requestHardLinkToFyle: return Name.requestHardLinkToFyle.name
			case .requestAllHardLinksToFyles: return Name.requestAllHardLinksToFyles.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .requestHardLinkToFyle(fyleElement: let fyleElement, completionHandler: let completionHandler):
			info = [
				"fyleElement": fyleElement,
				"completionHandler": completionHandler,
			]
		case .requestAllHardLinksToFyles(fyleElements: let fyleElements, completionHandler: let completionHandler):
			info = [
				"fyleElements": fyleElements,
				"completionHandler": completionHandler,
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

	static func observeRequestHardLinkToFyle(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (FyleElement, @escaping (@Sendable (Result<HardLinkToFyle,Error>) -> Void)) -> Void) -> NSObjectProtocol {
		let name = Name.requestHardLinkToFyle.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let fyleElement = notification.userInfo!["fyleElement"] as! FyleElement
			let completionHandler = notification.userInfo!["completionHandler"] as! (@Sendable (Result<HardLinkToFyle,Error>) -> Void)
			block(fyleElement, completionHandler)
		}
	}

	static func observeRequestAllHardLinksToFyles(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping ([FyleElement], @escaping (@Sendable ([HardLinkToFyle?]) -> Void)) -> Void) -> NSObjectProtocol {
		let name = Name.requestAllHardLinksToFyles.name
		// Handed to the observation unchecked: the block is called on the delivery queue, which its author chose.
		nonisolated(unsafe) let block = block
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let fyleElements = notification.userInfo!["fyleElements"] as! [FyleElement]
			let completionHandler = notification.userInfo!["completionHandler"] as! (@Sendable ([HardLinkToFyle?]) -> Void)
			block(fyleElements, completionHandler)
		}
	}

}

/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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

fileprivate struct OptionalWrapper<T> {
	let value: T?
	public init() {
		self.value = nil
	}
	public init(_ value: T?) {
		self.value = value
	}
}

public enum ObvMessengerSettingsNotifications {
	case contactsSortOrderDidChange
	case preferredComposeMessageViewActionsDidChange
	case isIncludesCallsInRecentsEnabledSettingDidChange
	case performInteractionDonationSettingDidChange
	case identityColorStyleDidChange
	case receiveCallsOnThisDeviceSettingDidChange

	private enum Name {
		case contactsSortOrderDidChange
		case preferredComposeMessageViewActionsDidChange
		case isIncludesCallsInRecentsEnabledSettingDidChange
		case performInteractionDonationSettingDidChange
		case identityColorStyleDidChange
		case receiveCallsOnThisDeviceSettingDidChange

		private var namePrefix: String { String(describing: ObvMessengerSettingsNotifications.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ObvMessengerSettingsNotifications) -> NSNotification.Name {
			switch notification {
			case .contactsSortOrderDidChange: return Name.contactsSortOrderDidChange.name
			case .preferredComposeMessageViewActionsDidChange: return Name.preferredComposeMessageViewActionsDidChange.name
			case .isIncludesCallsInRecentsEnabledSettingDidChange: return Name.isIncludesCallsInRecentsEnabledSettingDidChange.name
			case .performInteractionDonationSettingDidChange: return Name.performInteractionDonationSettingDidChange.name
			case .identityColorStyleDidChange: return Name.identityColorStyleDidChange.name
			case .receiveCallsOnThisDeviceSettingDidChange: return Name.receiveCallsOnThisDeviceSettingDidChange.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .contactsSortOrderDidChange:
			info = nil
		case .preferredComposeMessageViewActionsDidChange:
			info = nil
		case .isIncludesCallsInRecentsEnabledSettingDidChange:
			info = nil
		case .performInteractionDonationSettingDidChange:
			info = nil
		case .identityColorStyleDidChange:
			info = nil
		case .receiveCallsOnThisDeviceSettingDidChange:
			info = nil
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
		DispatchQueue(label: label).async {
			NotificationCenter.default.post(name: name, object: anObject, userInfo: userInfo)
		}
	}

	public static func observeContactsSortOrderDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.contactsSortOrderDidChange.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	public static func observePreferredComposeMessageViewActionsDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.preferredComposeMessageViewActionsDidChange.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	public static func observeIsIncludesCallsInRecentsEnabledSettingDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.isIncludesCallsInRecentsEnabledSettingDidChange.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	public static func observePerformInteractionDonationSettingDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.performInteractionDonationSettingDidChange.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	public static func observeIdentityColorStyleDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.identityColorStyleDidChange.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	public static func observeReceiveCallsOnThisDeviceSettingDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.receiveCallsOnThisDeviceSettingDidChange.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

}

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
import ObvTypes
import ObvCrypto
import OlvidUtils

fileprivate struct OptionalWrapper<T> {
	let value: T?
	public init() {
		self.value = nil
	}
	public init(_ value: T?) {
		self.value = value
	}
}

public enum ObvBackupNotification {
	case backupableManagerDatabaseContentChanged(flowId: FlowIdentifier)

	private enum Name {
		case backupableManagerDatabaseContentChanged

		private var namePrefix: String { String(describing: ObvBackupNotification.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ObvBackupNotification) -> NSNotification.Name {
			switch notification {
			case .backupableManagerDatabaseContentChanged: return Name.backupableManagerDatabaseContentChanged.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .backupableManagerDatabaseContentChanged(flowId: let flowId):
			info = [
				"flowId": flowId,
			]
		}
		return info
	}

	public func postOnBackgroundQueue(_ queue: DispatchQueue? = nil, within notificationDelegate: ObvNotificationDelegate) {
		let name = Name.forInternalNotification(self)
		let label = "Queue for posting \(name.rawValue) notification"
		let backgroundQueue = queue ?? DispatchQueue(label: label)
		backgroundQueue.async {
			notificationDelegate.post(name: name, userInfo: userInfo)
		}
	}

	public static func observeBackupableManagerDatabaseContentChanged(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.backupableManagerDatabaseContentChanged.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(flowId)
		}
	}

}

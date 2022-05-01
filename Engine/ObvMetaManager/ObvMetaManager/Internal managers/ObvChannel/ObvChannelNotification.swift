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

public enum ObvChannelNotification {
	case newConfirmedObliviousChannel(currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID)
	case deletedConfirmedObliviousChannel(currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID)
	case networkReceivedMessageWasProcessed(messageId: MessageIdentifier, flowId: FlowIdentifier)

	private enum Name {
		case newConfirmedObliviousChannel
		case deletedConfirmedObliviousChannel
		case networkReceivedMessageWasProcessed

		private var namePrefix: String { String(describing: ObvChannelNotification.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ObvChannelNotification) -> NSNotification.Name {
			switch notification {
			case .newConfirmedObliviousChannel: return Name.newConfirmedObliviousChannel.name
			case .deletedConfirmedObliviousChannel: return Name.deletedConfirmedObliviousChannel.name
			case .networkReceivedMessageWasProcessed: return Name.networkReceivedMessageWasProcessed.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .newConfirmedObliviousChannel(currentDeviceUid: let currentDeviceUid, remoteCryptoIdentity: let remoteCryptoIdentity, remoteDeviceUid: let remoteDeviceUid):
			info = [
				"currentDeviceUid": currentDeviceUid,
				"remoteCryptoIdentity": remoteCryptoIdentity,
				"remoteDeviceUid": remoteDeviceUid,
			]
		case .deletedConfirmedObliviousChannel(currentDeviceUid: let currentDeviceUid, remoteCryptoIdentity: let remoteCryptoIdentity, remoteDeviceUid: let remoteDeviceUid):
			info = [
				"currentDeviceUid": currentDeviceUid,
				"remoteCryptoIdentity": remoteCryptoIdentity,
				"remoteDeviceUid": remoteDeviceUid,
			]
		case .networkReceivedMessageWasProcessed(messageId: let messageId, flowId: let flowId):
			info = [
				"messageId": messageId,
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

	public static func observeNewConfirmedObliviousChannel(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (UID, ObvCryptoIdentity, UID) -> Void) -> NSObjectProtocol {
		let name = Name.newConfirmedObliviousChannel.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let currentDeviceUid = notification.userInfo!["currentDeviceUid"] as! UID
			let remoteCryptoIdentity = notification.userInfo!["remoteCryptoIdentity"] as! ObvCryptoIdentity
			let remoteDeviceUid = notification.userInfo!["remoteDeviceUid"] as! UID
			block(currentDeviceUid, remoteCryptoIdentity, remoteDeviceUid)
		}
	}

	public static func observeDeletedConfirmedObliviousChannel(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (UID, ObvCryptoIdentity, UID) -> Void) -> NSObjectProtocol {
		let name = Name.deletedConfirmedObliviousChannel.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let currentDeviceUid = notification.userInfo!["currentDeviceUid"] as! UID
			let remoteCryptoIdentity = notification.userInfo!["remoteCryptoIdentity"] as! ObvCryptoIdentity
			let remoteDeviceUid = notification.userInfo!["remoteDeviceUid"] as! UID
			block(currentDeviceUid, remoteCryptoIdentity, remoteDeviceUid)
		}
	}

	public static func observeNetworkReceivedMessageWasProcessed(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (MessageIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.networkReceivedMessageWasProcessed.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let messageId = notification.userInfo!["messageId"] as! MessageIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(messageId, flowId)
		}
	}

}

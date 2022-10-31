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
import ObvCrypto
import ObvTypes
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

public enum ObvProtocolNotification {
	case mutualScanContactAdded(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, signature: Data)
	case protocolMessageToProcess(protocolMessageId: MessageIdentifier, flowId: FlowIdentifier)
	case protocolMessageProcessed(protocolMessageId: MessageIdentifier, flowId: FlowIdentifier)
	case groupV2UpdateDidFail(ownedIdentity: ObvCryptoIdentity, appGroupIdentifier: Data, flowId: FlowIdentifier)

	private enum Name {
		case mutualScanContactAdded
		case protocolMessageToProcess
		case protocolMessageProcessed
		case groupV2UpdateDidFail

		private var namePrefix: String { String(describing: ObvProtocolNotification.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ObvProtocolNotification) -> NSNotification.Name {
			switch notification {
			case .mutualScanContactAdded: return Name.mutualScanContactAdded.name
			case .protocolMessageToProcess: return Name.protocolMessageToProcess.name
			case .protocolMessageProcessed: return Name.protocolMessageProcessed.name
			case .groupV2UpdateDidFail: return Name.groupV2UpdateDidFail.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .mutualScanContactAdded(ownedIdentity: let ownedIdentity, contactIdentity: let contactIdentity, signature: let signature):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactIdentity": contactIdentity,
				"signature": signature,
			]
		case .protocolMessageToProcess(protocolMessageId: let protocolMessageId, flowId: let flowId):
			info = [
				"protocolMessageId": protocolMessageId,
				"flowId": flowId,
			]
		case .protocolMessageProcessed(protocolMessageId: let protocolMessageId, flowId: let flowId):
			info = [
				"protocolMessageId": protocolMessageId,
				"flowId": flowId,
			]
		case .groupV2UpdateDidFail(ownedIdentity: let ownedIdentity, appGroupIdentifier: let appGroupIdentifier, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"appGroupIdentifier": appGroupIdentifier,
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

	public static func observeMutualScanContactAdded(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity, Data) -> Void) -> NSObjectProtocol {
		let name = Name.mutualScanContactAdded.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvCryptoIdentity
			let signature = notification.userInfo!["signature"] as! Data
			block(ownedIdentity, contactIdentity, signature)
		}
	}

	public static func observeProtocolMessageToProcess(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (MessageIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.protocolMessageToProcess.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let protocolMessageId = notification.userInfo!["protocolMessageId"] as! MessageIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(protocolMessageId, flowId)
		}
	}

	public static func observeProtocolMessageProcessed(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (MessageIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.protocolMessageProcessed.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let protocolMessageId = notification.userInfo!["protocolMessageId"] as! MessageIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(protocolMessageId, flowId)
		}
	}

	public static func observeGroupV2UpdateDidFail(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, Data, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.groupV2UpdateDidFail.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let appGroupIdentifier = notification.userInfo!["appGroupIdentifier"] as! Data
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, appGroupIdentifier, flowId)
		}
	}

}

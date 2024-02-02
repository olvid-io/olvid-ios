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
	case protocolMessageToProcess(protocolMessageId: ObvMessageIdentifier, flowId: FlowIdentifier)
	case protocolMessageProcessed(protocolMessageId: ObvMessageIdentifier, flowId: FlowIdentifier)
	case groupV2UpdateDidFail(ownedIdentity: ObvCryptoIdentity, appGroupIdentifier: Data, flowId: FlowIdentifier)
	case protocolReceivedMessageWasDeleted(protocolMessageId: ObvMessageIdentifier)
	case keycloakSynchronizationRequired(ownedIdentity: ObvCryptoIdentity)
	case contactIntroductionInvitationSent(ownedIdentity: ObvCryptoIdentity, contactIdentityA: ObvCryptoIdentity, contactIdentityB: ObvCryptoIdentity)
	case theCurrentDeviceWasNotPartOfTheLastOwnedDeviceDiscoveryResults(ownedIdentity: ObvCryptoIdentity)
	case anOwnedIdentityTransferProtocolFailed(ownedCryptoIdentity: ObvCryptoIdentity, protocolInstanceUID: UID, error: Error)

	private enum Name {
		case mutualScanContactAdded
		case protocolMessageToProcess
		case protocolMessageProcessed
		case groupV2UpdateDidFail
		case protocolReceivedMessageWasDeleted
		case keycloakSynchronizationRequired
		case contactIntroductionInvitationSent
		case theCurrentDeviceWasNotPartOfTheLastOwnedDeviceDiscoveryResults
		case anOwnedIdentityTransferProtocolFailed

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
			case .protocolReceivedMessageWasDeleted: return Name.protocolReceivedMessageWasDeleted.name
			case .keycloakSynchronizationRequired: return Name.keycloakSynchronizationRequired.name
			case .contactIntroductionInvitationSent: return Name.contactIntroductionInvitationSent.name
			case .theCurrentDeviceWasNotPartOfTheLastOwnedDeviceDiscoveryResults: return Name.theCurrentDeviceWasNotPartOfTheLastOwnedDeviceDiscoveryResults.name
			case .anOwnedIdentityTransferProtocolFailed: return Name.anOwnedIdentityTransferProtocolFailed.name
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
		case .protocolReceivedMessageWasDeleted(protocolMessageId: let protocolMessageId):
			info = [
				"protocolMessageId": protocolMessageId,
			]
		case .keycloakSynchronizationRequired(ownedIdentity: let ownedIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
			]
		case .contactIntroductionInvitationSent(ownedIdentity: let ownedIdentity, contactIdentityA: let contactIdentityA, contactIdentityB: let contactIdentityB):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactIdentityA": contactIdentityA,
				"contactIdentityB": contactIdentityB,
			]
		case .theCurrentDeviceWasNotPartOfTheLastOwnedDeviceDiscoveryResults(ownedIdentity: let ownedIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
			]
		case .anOwnedIdentityTransferProtocolFailed(ownedCryptoIdentity: let ownedCryptoIdentity, protocolInstanceUID: let protocolInstanceUID, error: let error):
			info = [
				"ownedCryptoIdentity": ownedCryptoIdentity,
				"protocolInstanceUID": protocolInstanceUID,
				"error": error,
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

	public static func observeProtocolMessageToProcess(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvMessageIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.protocolMessageToProcess.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let protocolMessageId = notification.userInfo!["protocolMessageId"] as! ObvMessageIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(protocolMessageId, flowId)
		}
	}

	public static func observeProtocolMessageProcessed(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvMessageIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.protocolMessageProcessed.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let protocolMessageId = notification.userInfo!["protocolMessageId"] as! ObvMessageIdentifier
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

	public static func observeProtocolReceivedMessageWasDeleted(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvMessageIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.protocolReceivedMessageWasDeleted.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let protocolMessageId = notification.userInfo!["protocolMessageId"] as! ObvMessageIdentifier
			block(protocolMessageId)
		}
	}

	public static func observeKeycloakSynchronizationRequired(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.keycloakSynchronizationRequired.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			block(ownedIdentity)
		}
	}

	public static func observeContactIntroductionInvitationSent(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity, ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.contactIntroductionInvitationSent.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let contactIdentityA = notification.userInfo!["contactIdentityA"] as! ObvCryptoIdentity
			let contactIdentityB = notification.userInfo!["contactIdentityB"] as! ObvCryptoIdentity
			block(ownedIdentity, contactIdentityA, contactIdentityB)
		}
	}

	public static func observeTheCurrentDeviceWasNotPartOfTheLastOwnedDeviceDiscoveryResults(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.theCurrentDeviceWasNotPartOfTheLastOwnedDeviceDiscoveryResults.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			block(ownedIdentity)
		}
	}

	public static func observeAnOwnedIdentityTransferProtocolFailed(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, UID, Error) -> Void) -> NSObjectProtocol {
		let name = Name.anOwnedIdentityTransferProtocolFailed.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedCryptoIdentity = notification.userInfo!["ownedCryptoIdentity"] as! ObvCryptoIdentity
			let protocolInstanceUID = notification.userInfo!["protocolInstanceUID"] as! UID
			let error = notification.userInfo!["error"] as! Error
			block(ownedCryptoIdentity, protocolInstanceUID, error)
		}
	}

}

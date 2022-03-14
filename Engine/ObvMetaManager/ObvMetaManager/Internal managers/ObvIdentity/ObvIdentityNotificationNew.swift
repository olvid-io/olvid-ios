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

public enum ObvIdentityNotificationNew {
	case contactIdentityIsNowTrusted(contactIdentity: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
	case newOwnedIdentityWithinIdentityManager(cryptoIdentity: ObvCryptoIdentity)
	case ownedIdentityWasDeactivated(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
	case ownedIdentityWasReactivated(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
	case deletedContactDevice(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, flowId: FlowIdentifier)
	case newContactDevice(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, flowId: FlowIdentifier)
	case serverLabelHasBeenDeleted(ownedIdentity: ObvCryptoIdentity, label: String)
	case contactWasDeleted(ownedCryptoIdentity: ObvCryptoIdentity, contactCryptoIdentity: ObvCryptoIdentity, contactTrustedIdentityDetails: ObvIdentityDetails)
	case latestPhotoOfContactGroupOwnedHasBeenUpdated(groupUid: UID, ownedIdentity: ObvCryptoIdentity)
	case publishedPhotoOfContactGroupOwnedHasBeenUpdated(groupUid: UID, ownedIdentity: ObvCryptoIdentity)
	case publishedPhotoOfContactGroupJoinedHasBeenUpdated(groupUid: UID, ownedIdentity: ObvCryptoIdentity, groupOwner: ObvCryptoIdentity)
	case trustedPhotoOfContactGroupJoinedHasBeenUpdated(groupUid: UID, ownedIdentity: ObvCryptoIdentity, groupOwner: ObvCryptoIdentity)
	case publishedPhotoOfOwnedIdentityHasBeenUpdated(ownedIdentity: ObvCryptoIdentity)
	case publishedPhotoOfContactIdentityHasBeenUpdated(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity)
	case trustedPhotoOfContactIdentityHasBeenUpdated(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity)
	case ownedIdentityKeycloakServerChanged(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
	case contactWasUpdatedWithinTheIdentityManager(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
	case contactIsActiveChanged(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, isActive: Bool, flowId: FlowIdentifier)
	case contactWasRevokedAsCompromised(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
	case contactObvCapabilitiesWereUpdated(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
	case ownedIdentityCapabilitiesWereUpdated(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)

	private enum Name {
		case contactIdentityIsNowTrusted
		case newOwnedIdentityWithinIdentityManager
		case ownedIdentityWasDeactivated
		case ownedIdentityWasReactivated
		case deletedContactDevice
		case newContactDevice
		case serverLabelHasBeenDeleted
		case contactWasDeleted
		case latestPhotoOfContactGroupOwnedHasBeenUpdated
		case publishedPhotoOfContactGroupOwnedHasBeenUpdated
		case publishedPhotoOfContactGroupJoinedHasBeenUpdated
		case trustedPhotoOfContactGroupJoinedHasBeenUpdated
		case publishedPhotoOfOwnedIdentityHasBeenUpdated
		case publishedPhotoOfContactIdentityHasBeenUpdated
		case trustedPhotoOfContactIdentityHasBeenUpdated
		case ownedIdentityKeycloakServerChanged
		case contactWasUpdatedWithinTheIdentityManager
		case contactIsActiveChanged
		case contactWasRevokedAsCompromised
		case contactObvCapabilitiesWereUpdated
		case ownedIdentityCapabilitiesWereUpdated

		private var namePrefix: String { String(describing: ObvIdentityNotificationNew.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ObvIdentityNotificationNew) -> NSNotification.Name {
			switch notification {
			case .contactIdentityIsNowTrusted: return Name.contactIdentityIsNowTrusted.name
			case .newOwnedIdentityWithinIdentityManager: return Name.newOwnedIdentityWithinIdentityManager.name
			case .ownedIdentityWasDeactivated: return Name.ownedIdentityWasDeactivated.name
			case .ownedIdentityWasReactivated: return Name.ownedIdentityWasReactivated.name
			case .deletedContactDevice: return Name.deletedContactDevice.name
			case .newContactDevice: return Name.newContactDevice.name
			case .serverLabelHasBeenDeleted: return Name.serverLabelHasBeenDeleted.name
			case .contactWasDeleted: return Name.contactWasDeleted.name
			case .latestPhotoOfContactGroupOwnedHasBeenUpdated: return Name.latestPhotoOfContactGroupOwnedHasBeenUpdated.name
			case .publishedPhotoOfContactGroupOwnedHasBeenUpdated: return Name.publishedPhotoOfContactGroupOwnedHasBeenUpdated.name
			case .publishedPhotoOfContactGroupJoinedHasBeenUpdated: return Name.publishedPhotoOfContactGroupJoinedHasBeenUpdated.name
			case .trustedPhotoOfContactGroupJoinedHasBeenUpdated: return Name.trustedPhotoOfContactGroupJoinedHasBeenUpdated.name
			case .publishedPhotoOfOwnedIdentityHasBeenUpdated: return Name.publishedPhotoOfOwnedIdentityHasBeenUpdated.name
			case .publishedPhotoOfContactIdentityHasBeenUpdated: return Name.publishedPhotoOfContactIdentityHasBeenUpdated.name
			case .trustedPhotoOfContactIdentityHasBeenUpdated: return Name.trustedPhotoOfContactIdentityHasBeenUpdated.name
			case .ownedIdentityKeycloakServerChanged: return Name.ownedIdentityKeycloakServerChanged.name
			case .contactWasUpdatedWithinTheIdentityManager: return Name.contactWasUpdatedWithinTheIdentityManager.name
			case .contactIsActiveChanged: return Name.contactIsActiveChanged.name
			case .contactWasRevokedAsCompromised: return Name.contactWasRevokedAsCompromised.name
			case .contactObvCapabilitiesWereUpdated: return Name.contactObvCapabilitiesWereUpdated.name
			case .ownedIdentityCapabilitiesWereUpdated: return Name.ownedIdentityCapabilitiesWereUpdated.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .contactIdentityIsNowTrusted(contactIdentity: let contactIdentity, ownedIdentity: let ownedIdentity, flowId: let flowId):
			info = [
				"contactIdentity": contactIdentity,
				"ownedIdentity": ownedIdentity,
				"flowId": flowId,
			]
		case .newOwnedIdentityWithinIdentityManager(cryptoIdentity: let cryptoIdentity):
			info = [
				"cryptoIdentity": cryptoIdentity,
			]
		case .ownedIdentityWasDeactivated(ownedCryptoIdentity: let ownedCryptoIdentity, flowId: let flowId):
			info = [
				"ownedCryptoIdentity": ownedCryptoIdentity,
				"flowId": flowId,
			]
		case .ownedIdentityWasReactivated(ownedCryptoIdentity: let ownedCryptoIdentity, flowId: let flowId):
			info = [
				"ownedCryptoIdentity": ownedCryptoIdentity,
				"flowId": flowId,
			]
		case .deletedContactDevice(ownedIdentity: let ownedIdentity, contactIdentity: let contactIdentity, contactDeviceUid: let contactDeviceUid, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactIdentity": contactIdentity,
				"contactDeviceUid": contactDeviceUid,
				"flowId": flowId,
			]
		case .newContactDevice(ownedIdentity: let ownedIdentity, contactIdentity: let contactIdentity, contactDeviceUid: let contactDeviceUid, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactIdentity": contactIdentity,
				"contactDeviceUid": contactDeviceUid,
				"flowId": flowId,
			]
		case .serverLabelHasBeenDeleted(ownedIdentity: let ownedIdentity, label: let label):
			info = [
				"ownedIdentity": ownedIdentity,
				"label": label,
			]
		case .contactWasDeleted(ownedCryptoIdentity: let ownedCryptoIdentity, contactCryptoIdentity: let contactCryptoIdentity, contactTrustedIdentityDetails: let contactTrustedIdentityDetails):
			info = [
				"ownedCryptoIdentity": ownedCryptoIdentity,
				"contactCryptoIdentity": contactCryptoIdentity,
				"contactTrustedIdentityDetails": contactTrustedIdentityDetails,
			]
		case .latestPhotoOfContactGroupOwnedHasBeenUpdated(groupUid: let groupUid, ownedIdentity: let ownedIdentity):
			info = [
				"groupUid": groupUid,
				"ownedIdentity": ownedIdentity,
			]
		case .publishedPhotoOfContactGroupOwnedHasBeenUpdated(groupUid: let groupUid, ownedIdentity: let ownedIdentity):
			info = [
				"groupUid": groupUid,
				"ownedIdentity": ownedIdentity,
			]
		case .publishedPhotoOfContactGroupJoinedHasBeenUpdated(groupUid: let groupUid, ownedIdentity: let ownedIdentity, groupOwner: let groupOwner):
			info = [
				"groupUid": groupUid,
				"ownedIdentity": ownedIdentity,
				"groupOwner": groupOwner,
			]
		case .trustedPhotoOfContactGroupJoinedHasBeenUpdated(groupUid: let groupUid, ownedIdentity: let ownedIdentity, groupOwner: let groupOwner):
			info = [
				"groupUid": groupUid,
				"ownedIdentity": ownedIdentity,
				"groupOwner": groupOwner,
			]
		case .publishedPhotoOfOwnedIdentityHasBeenUpdated(ownedIdentity: let ownedIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
			]
		case .publishedPhotoOfContactIdentityHasBeenUpdated(ownedIdentity: let ownedIdentity, contactIdentity: let contactIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactIdentity": contactIdentity,
			]
		case .trustedPhotoOfContactIdentityHasBeenUpdated(ownedIdentity: let ownedIdentity, contactIdentity: let contactIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactIdentity": contactIdentity,
			]
		case .ownedIdentityKeycloakServerChanged(ownedCryptoIdentity: let ownedCryptoIdentity, flowId: let flowId):
			info = [
				"ownedCryptoIdentity": ownedCryptoIdentity,
				"flowId": flowId,
			]
		case .contactWasUpdatedWithinTheIdentityManager(ownedIdentity: let ownedIdentity, contactIdentity: let contactIdentity, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactIdentity": contactIdentity,
				"flowId": flowId,
			]
		case .contactIsActiveChanged(ownedIdentity: let ownedIdentity, contactIdentity: let contactIdentity, isActive: let isActive, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactIdentity": contactIdentity,
				"isActive": isActive,
				"flowId": flowId,
			]
		case .contactWasRevokedAsCompromised(ownedIdentity: let ownedIdentity, contactIdentity: let contactIdentity, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactIdentity": contactIdentity,
				"flowId": flowId,
			]
		case .contactObvCapabilitiesWereUpdated(ownedIdentity: let ownedIdentity, contactIdentity: let contactIdentity, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactIdentity": contactIdentity,
				"flowId": flowId,
			]
		case .ownedIdentityCapabilitiesWereUpdated(ownedIdentity: let ownedIdentity, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
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

	public static func observeContactIdentityIsNowTrusted(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.contactIdentityIsNowTrusted.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvCryptoIdentity
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(contactIdentity, ownedIdentity, flowId)
		}
	}

	public static func observeNewOwnedIdentityWithinIdentityManager(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.newOwnedIdentityWithinIdentityManager.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let cryptoIdentity = notification.userInfo!["cryptoIdentity"] as! ObvCryptoIdentity
			block(cryptoIdentity)
		}
	}

	public static func observeOwnedIdentityWasDeactivated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityWasDeactivated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedCryptoIdentity = notification.userInfo!["ownedCryptoIdentity"] as! ObvCryptoIdentity
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedCryptoIdentity, flowId)
		}
	}

	public static func observeOwnedIdentityWasReactivated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityWasReactivated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedCryptoIdentity = notification.userInfo!["ownedCryptoIdentity"] as! ObvCryptoIdentity
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedCryptoIdentity, flowId)
		}
	}

	public static func observeDeletedContactDevice(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity, UID, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.deletedContactDevice.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvCryptoIdentity
			let contactDeviceUid = notification.userInfo!["contactDeviceUid"] as! UID
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, contactIdentity, contactDeviceUid, flowId)
		}
	}

	public static func observeNewContactDevice(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity, UID, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.newContactDevice.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvCryptoIdentity
			let contactDeviceUid = notification.userInfo!["contactDeviceUid"] as! UID
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, contactIdentity, contactDeviceUid, flowId)
		}
	}

	public static func observeServerLabelHasBeenDeleted(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, String) -> Void) -> NSObjectProtocol {
		let name = Name.serverLabelHasBeenDeleted.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let label = notification.userInfo!["label"] as! String
			block(ownedIdentity, label)
		}
	}

	public static func observeContactWasDeleted(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity, ObvIdentityDetails) -> Void) -> NSObjectProtocol {
		let name = Name.contactWasDeleted.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedCryptoIdentity = notification.userInfo!["ownedCryptoIdentity"] as! ObvCryptoIdentity
			let contactCryptoIdentity = notification.userInfo!["contactCryptoIdentity"] as! ObvCryptoIdentity
			let contactTrustedIdentityDetails = notification.userInfo!["contactTrustedIdentityDetails"] as! ObvIdentityDetails
			block(ownedCryptoIdentity, contactCryptoIdentity, contactTrustedIdentityDetails)
		}
	}

	public static func observeLatestPhotoOfContactGroupOwnedHasBeenUpdated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (UID, ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.latestPhotoOfContactGroupOwnedHasBeenUpdated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let groupUid = notification.userInfo!["groupUid"] as! UID
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			block(groupUid, ownedIdentity)
		}
	}

	public static func observePublishedPhotoOfContactGroupOwnedHasBeenUpdated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (UID, ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.publishedPhotoOfContactGroupOwnedHasBeenUpdated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let groupUid = notification.userInfo!["groupUid"] as! UID
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			block(groupUid, ownedIdentity)
		}
	}

	public static func observePublishedPhotoOfContactGroupJoinedHasBeenUpdated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (UID, ObvCryptoIdentity, ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.publishedPhotoOfContactGroupJoinedHasBeenUpdated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let groupUid = notification.userInfo!["groupUid"] as! UID
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let groupOwner = notification.userInfo!["groupOwner"] as! ObvCryptoIdentity
			block(groupUid, ownedIdentity, groupOwner)
		}
	}

	public static func observeTrustedPhotoOfContactGroupJoinedHasBeenUpdated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (UID, ObvCryptoIdentity, ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.trustedPhotoOfContactGroupJoinedHasBeenUpdated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let groupUid = notification.userInfo!["groupUid"] as! UID
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let groupOwner = notification.userInfo!["groupOwner"] as! ObvCryptoIdentity
			block(groupUid, ownedIdentity, groupOwner)
		}
	}

	public static func observePublishedPhotoOfOwnedIdentityHasBeenUpdated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.publishedPhotoOfOwnedIdentityHasBeenUpdated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			block(ownedIdentity)
		}
	}

	public static func observePublishedPhotoOfContactIdentityHasBeenUpdated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.publishedPhotoOfContactIdentityHasBeenUpdated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvCryptoIdentity
			block(ownedIdentity, contactIdentity)
		}
	}

	public static func observeTrustedPhotoOfContactIdentityHasBeenUpdated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.trustedPhotoOfContactIdentityHasBeenUpdated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvCryptoIdentity
			block(ownedIdentity, contactIdentity)
		}
	}

	public static func observeOwnedIdentityKeycloakServerChanged(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityKeycloakServerChanged.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedCryptoIdentity = notification.userInfo!["ownedCryptoIdentity"] as! ObvCryptoIdentity
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedCryptoIdentity, flowId)
		}
	}

	public static func observeContactWasUpdatedWithinTheIdentityManager(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.contactWasUpdatedWithinTheIdentityManager.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvCryptoIdentity
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, contactIdentity, flowId)
		}
	}

	public static func observeContactIsActiveChanged(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity, Bool, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.contactIsActiveChanged.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvCryptoIdentity
			let isActive = notification.userInfo!["isActive"] as! Bool
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, contactIdentity, isActive, flowId)
		}
	}

	public static func observeContactWasRevokedAsCompromised(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.contactWasRevokedAsCompromised.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvCryptoIdentity
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, contactIdentity, flowId)
		}
	}

	public static func observeContactObvCapabilitiesWereUpdated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.contactObvCapabilitiesWereUpdated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvCryptoIdentity
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, contactIdentity, flowId)
		}
	}

	public static func observeOwnedIdentityCapabilitiesWereUpdated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityCapabilitiesWereUpdated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, flowId)
		}
	}

}

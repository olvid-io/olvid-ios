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
	case newOwnedIdentityWithinIdentityManager(cryptoIdentity: ObvCryptoIdentity)
	case ownedIdentityWasDeactivated(ownedCryptoIdentity: ObvCryptoIdentity)
	case ownedIdentityWasReactivated(ownedCryptoIdentity: ObvCryptoIdentity)
	case deletedContactDevice(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID)
	case newContactDevice(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, createdDuringChannelCreation: Bool, flowId: FlowIdentifier)
	case updatedContactDevice(deviceIdentifier: ObvContactDeviceIdentifier)
	case serverLabelHasBeenDeleted(ownedIdentity: ObvCryptoIdentity, label: UID)
	case contactWasDeleted(ownedCryptoIdentity: ObvCryptoIdentity, contactCryptoIdentity: ObvCryptoIdentity)
	case latestPhotoOfContactGroupOwnedHasBeenUpdated(groupUid: UID, ownedIdentity: ObvCryptoIdentity)
	case publishedPhotoOfContactGroupOwnedHasBeenUpdated(groupUid: UID, ownedIdentity: ObvCryptoIdentity)
	case publishedPhotoOfContactGroupJoinedHasBeenUpdated(groupUid: UID, ownedIdentity: ObvCryptoIdentity, groupOwner: ObvCryptoIdentity)
	case trustedPhotoOfContactGroupJoinedHasBeenUpdated(groupUid: UID, ownedIdentity: ObvCryptoIdentity, groupOwner: ObvCryptoIdentity)
	case publishedPhotoOfOwnedIdentityHasBeenUpdated(ownedIdentity: ObvCryptoIdentity)
	case publishedPhotoOfContactIdentityHasBeenUpdated(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity)
	case trustedPhotoOfContactIdentityHasBeenUpdated(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity)
	case ownedIdentityKeycloakServerChanged(ownedCryptoIdentity: ObvCryptoIdentity)
	case contactWasRevokedAsCompromised(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity)
	case contactObvCapabilitiesWereUpdated(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity)
	case ownedIdentityCapabilitiesWereUpdated(ownedIdentity: ObvCryptoIdentity)
	case contactIdentityOneToOneStatusChanged(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity)
	case groupV2WasCreated(obvGroupV2: ObvGroupV2, initiator: ObvGroupV2.CreationOrUpdateInitiator)
	case groupV2WasUpdated(obvGroupV2: ObvGroupV2, initiator: ObvGroupV2.CreationOrUpdateInitiator)
	case groupV2WasDeleted(ownedIdentity: ObvCryptoIdentity, appGroupIdentifier: Data)
	case contactIsCertifiedByOwnKeycloakStatusChanged(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, newIsCertifiedByOwnKeycloak: Bool)
	case pushTopicOfKeycloakGroupWasUpdated(ownedCryptoId: ObvCryptoIdentity)
	case newRemoteOwnedDevice(ownedCryptoId: ObvCryptoIdentity, remoteDeviceUid: UID, createdDuringChannelCreation: Bool)
	case anOwnedDeviceWasUpdated(ownedCryptoId: ObvCryptoIdentity)
	case anOwnedDeviceWasDeleted(ownedCryptoId: ObvCryptoIdentity)
	case newActiveOwnedIdentity(ownedCryptoIdentity: ObvCryptoIdentity)

	private enum Name {
		case newOwnedIdentityWithinIdentityManager
		case ownedIdentityWasDeactivated
		case ownedIdentityWasReactivated
		case deletedContactDevice
		case newContactDevice
		case updatedContactDevice
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
		case contactWasRevokedAsCompromised
		case contactObvCapabilitiesWereUpdated
		case ownedIdentityCapabilitiesWereUpdated
		case contactIdentityOneToOneStatusChanged
		case groupV2WasCreated
		case groupV2WasUpdated
		case groupV2WasDeleted
		case contactIsCertifiedByOwnKeycloakStatusChanged
		case pushTopicOfKeycloakGroupWasUpdated
		case newRemoteOwnedDevice
		case anOwnedDeviceWasUpdated
		case anOwnedDeviceWasDeleted
		case newActiveOwnedIdentity

		private var namePrefix: String { String(describing: ObvIdentityNotificationNew.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ObvIdentityNotificationNew) -> NSNotification.Name {
			switch notification {
			case .newOwnedIdentityWithinIdentityManager: return Name.newOwnedIdentityWithinIdentityManager.name
			case .ownedIdentityWasDeactivated: return Name.ownedIdentityWasDeactivated.name
			case .ownedIdentityWasReactivated: return Name.ownedIdentityWasReactivated.name
			case .deletedContactDevice: return Name.deletedContactDevice.name
			case .newContactDevice: return Name.newContactDevice.name
			case .updatedContactDevice: return Name.updatedContactDevice.name
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
			case .contactWasRevokedAsCompromised: return Name.contactWasRevokedAsCompromised.name
			case .contactObvCapabilitiesWereUpdated: return Name.contactObvCapabilitiesWereUpdated.name
			case .ownedIdentityCapabilitiesWereUpdated: return Name.ownedIdentityCapabilitiesWereUpdated.name
			case .contactIdentityOneToOneStatusChanged: return Name.contactIdentityOneToOneStatusChanged.name
			case .groupV2WasCreated: return Name.groupV2WasCreated.name
			case .groupV2WasUpdated: return Name.groupV2WasUpdated.name
			case .groupV2WasDeleted: return Name.groupV2WasDeleted.name
			case .contactIsCertifiedByOwnKeycloakStatusChanged: return Name.contactIsCertifiedByOwnKeycloakStatusChanged.name
			case .pushTopicOfKeycloakGroupWasUpdated: return Name.pushTopicOfKeycloakGroupWasUpdated.name
			case .newRemoteOwnedDevice: return Name.newRemoteOwnedDevice.name
			case .anOwnedDeviceWasUpdated: return Name.anOwnedDeviceWasUpdated.name
			case .anOwnedDeviceWasDeleted: return Name.anOwnedDeviceWasDeleted.name
			case .newActiveOwnedIdentity: return Name.newActiveOwnedIdentity.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .newOwnedIdentityWithinIdentityManager(cryptoIdentity: let cryptoIdentity):
			info = [
				"cryptoIdentity": cryptoIdentity,
			]
		case .ownedIdentityWasDeactivated(ownedCryptoIdentity: let ownedCryptoIdentity):
			info = [
				"ownedCryptoIdentity": ownedCryptoIdentity,
			]
		case .ownedIdentityWasReactivated(ownedCryptoIdentity: let ownedCryptoIdentity):
			info = [
				"ownedCryptoIdentity": ownedCryptoIdentity,
			]
		case .deletedContactDevice(ownedIdentity: let ownedIdentity, contactIdentity: let contactIdentity, contactDeviceUid: let contactDeviceUid):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactIdentity": contactIdentity,
				"contactDeviceUid": contactDeviceUid,
			]
		case .newContactDevice(ownedIdentity: let ownedIdentity, contactIdentity: let contactIdentity, contactDeviceUid: let contactDeviceUid, createdDuringChannelCreation: let createdDuringChannelCreation, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactIdentity": contactIdentity,
				"contactDeviceUid": contactDeviceUid,
				"createdDuringChannelCreation": createdDuringChannelCreation,
				"flowId": flowId,
			]
		case .updatedContactDevice(deviceIdentifier: let deviceIdentifier):
			info = [
				"deviceIdentifier": deviceIdentifier,
			]
		case .serverLabelHasBeenDeleted(ownedIdentity: let ownedIdentity, label: let label):
			info = [
				"ownedIdentity": ownedIdentity,
				"label": label,
			]
		case .contactWasDeleted(ownedCryptoIdentity: let ownedCryptoIdentity, contactCryptoIdentity: let contactCryptoIdentity):
			info = [
				"ownedCryptoIdentity": ownedCryptoIdentity,
				"contactCryptoIdentity": contactCryptoIdentity,
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
		case .ownedIdentityKeycloakServerChanged(ownedCryptoIdentity: let ownedCryptoIdentity):
			info = [
				"ownedCryptoIdentity": ownedCryptoIdentity,
			]
		case .contactWasRevokedAsCompromised(ownedIdentity: let ownedIdentity, contactIdentity: let contactIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactIdentity": contactIdentity,
			]
		case .contactObvCapabilitiesWereUpdated(ownedIdentity: let ownedIdentity, contactIdentity: let contactIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactIdentity": contactIdentity,
			]
		case .ownedIdentityCapabilitiesWereUpdated(ownedIdentity: let ownedIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
			]
		case .contactIdentityOneToOneStatusChanged(ownedIdentity: let ownedIdentity, contactIdentity: let contactIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactIdentity": contactIdentity,
			]
		case .groupV2WasCreated(obvGroupV2: let obvGroupV2, initiator: let initiator):
			info = [
				"obvGroupV2": obvGroupV2,
				"initiator": initiator,
			]
		case .groupV2WasUpdated(obvGroupV2: let obvGroupV2, initiator: let initiator):
			info = [
				"obvGroupV2": obvGroupV2,
				"initiator": initiator,
			]
		case .groupV2WasDeleted(ownedIdentity: let ownedIdentity, appGroupIdentifier: let appGroupIdentifier):
			info = [
				"ownedIdentity": ownedIdentity,
				"appGroupIdentifier": appGroupIdentifier,
			]
		case .contactIsCertifiedByOwnKeycloakStatusChanged(ownedIdentity: let ownedIdentity, contactIdentity: let contactIdentity, newIsCertifiedByOwnKeycloak: let newIsCertifiedByOwnKeycloak):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactIdentity": contactIdentity,
				"newIsCertifiedByOwnKeycloak": newIsCertifiedByOwnKeycloak,
			]
		case .pushTopicOfKeycloakGroupWasUpdated(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .newRemoteOwnedDevice(ownedCryptoId: let ownedCryptoId, remoteDeviceUid: let remoteDeviceUid, createdDuringChannelCreation: let createdDuringChannelCreation):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"remoteDeviceUid": remoteDeviceUid,
				"createdDuringChannelCreation": createdDuringChannelCreation,
			]
		case .anOwnedDeviceWasUpdated(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .anOwnedDeviceWasDeleted(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .newActiveOwnedIdentity(ownedCryptoIdentity: let ownedCryptoIdentity):
			info = [
				"ownedCryptoIdentity": ownedCryptoIdentity,
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

	public static func observeNewOwnedIdentityWithinIdentityManager(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.newOwnedIdentityWithinIdentityManager.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let cryptoIdentity = notification.userInfo!["cryptoIdentity"] as! ObvCryptoIdentity
			block(cryptoIdentity)
		}
	}

	public static func observeOwnedIdentityWasDeactivated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityWasDeactivated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedCryptoIdentity = notification.userInfo!["ownedCryptoIdentity"] as! ObvCryptoIdentity
			block(ownedCryptoIdentity)
		}
	}

	public static func observeOwnedIdentityWasReactivated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityWasReactivated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedCryptoIdentity = notification.userInfo!["ownedCryptoIdentity"] as! ObvCryptoIdentity
			block(ownedCryptoIdentity)
		}
	}

	public static func observeDeletedContactDevice(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity, UID) -> Void) -> NSObjectProtocol {
		let name = Name.deletedContactDevice.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvCryptoIdentity
			let contactDeviceUid = notification.userInfo!["contactDeviceUid"] as! UID
			block(ownedIdentity, contactIdentity, contactDeviceUid)
		}
	}

	public static func observeNewContactDevice(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity, UID, Bool, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.newContactDevice.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvCryptoIdentity
			let contactDeviceUid = notification.userInfo!["contactDeviceUid"] as! UID
			let createdDuringChannelCreation = notification.userInfo!["createdDuringChannelCreation"] as! Bool
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, contactIdentity, contactDeviceUid, createdDuringChannelCreation, flowId)
		}
	}

	public static func observeUpdatedContactDevice(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvContactDeviceIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.updatedContactDevice.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let deviceIdentifier = notification.userInfo!["deviceIdentifier"] as! ObvContactDeviceIdentifier
			block(deviceIdentifier)
		}
	}

	public static func observeServerLabelHasBeenDeleted(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, UID) -> Void) -> NSObjectProtocol {
		let name = Name.serverLabelHasBeenDeleted.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let label = notification.userInfo!["label"] as! UID
			block(ownedIdentity, label)
		}
	}

	public static func observeContactWasDeleted(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.contactWasDeleted.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedCryptoIdentity = notification.userInfo!["ownedCryptoIdentity"] as! ObvCryptoIdentity
			let contactCryptoIdentity = notification.userInfo!["contactCryptoIdentity"] as! ObvCryptoIdentity
			block(ownedCryptoIdentity, contactCryptoIdentity)
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

	public static func observeOwnedIdentityKeycloakServerChanged(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityKeycloakServerChanged.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedCryptoIdentity = notification.userInfo!["ownedCryptoIdentity"] as! ObvCryptoIdentity
			block(ownedCryptoIdentity)
		}
	}

	public static func observeContactWasRevokedAsCompromised(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.contactWasRevokedAsCompromised.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvCryptoIdentity
			block(ownedIdentity, contactIdentity)
		}
	}

	public static func observeContactObvCapabilitiesWereUpdated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.contactObvCapabilitiesWereUpdated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvCryptoIdentity
			block(ownedIdentity, contactIdentity)
		}
	}

	public static func observeOwnedIdentityCapabilitiesWereUpdated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityCapabilitiesWereUpdated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			block(ownedIdentity)
		}
	}

	public static func observeContactIdentityOneToOneStatusChanged(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.contactIdentityOneToOneStatusChanged.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvCryptoIdentity
			block(ownedIdentity, contactIdentity)
		}
	}

	public static func observeGroupV2WasCreated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvGroupV2, ObvGroupV2.CreationOrUpdateInitiator) -> Void) -> NSObjectProtocol {
		let name = Name.groupV2WasCreated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let obvGroupV2 = notification.userInfo!["obvGroupV2"] as! ObvGroupV2
			let initiator = notification.userInfo!["initiator"] as! ObvGroupV2.CreationOrUpdateInitiator
			block(obvGroupV2, initiator)
		}
	}

	public static func observeGroupV2WasUpdated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvGroupV2, ObvGroupV2.CreationOrUpdateInitiator) -> Void) -> NSObjectProtocol {
		let name = Name.groupV2WasUpdated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let obvGroupV2 = notification.userInfo!["obvGroupV2"] as! ObvGroupV2
			let initiator = notification.userInfo!["initiator"] as! ObvGroupV2.CreationOrUpdateInitiator
			block(obvGroupV2, initiator)
		}
	}

	public static func observeGroupV2WasDeleted(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, Data) -> Void) -> NSObjectProtocol {
		let name = Name.groupV2WasDeleted.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let appGroupIdentifier = notification.userInfo!["appGroupIdentifier"] as! Data
			block(ownedIdentity, appGroupIdentifier)
		}
	}

	public static func observeContactIsCertifiedByOwnKeycloakStatusChanged(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity, Bool) -> Void) -> NSObjectProtocol {
		let name = Name.contactIsCertifiedByOwnKeycloakStatusChanged.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvCryptoIdentity
			let newIsCertifiedByOwnKeycloak = notification.userInfo!["newIsCertifiedByOwnKeycloak"] as! Bool
			block(ownedIdentity, contactIdentity, newIsCertifiedByOwnKeycloak)
		}
	}

	public static func observePushTopicOfKeycloakGroupWasUpdated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.pushTopicOfKeycloakGroupWasUpdated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoIdentity
			block(ownedCryptoId)
		}
	}

	public static func observeNewRemoteOwnedDevice(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, UID, Bool) -> Void) -> NSObjectProtocol {
		let name = Name.newRemoteOwnedDevice.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoIdentity
			let remoteDeviceUid = notification.userInfo!["remoteDeviceUid"] as! UID
			let createdDuringChannelCreation = notification.userInfo!["createdDuringChannelCreation"] as! Bool
			block(ownedCryptoId, remoteDeviceUid, createdDuringChannelCreation)
		}
	}

	public static func observeAnOwnedDeviceWasUpdated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.anOwnedDeviceWasUpdated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoIdentity
			block(ownedCryptoId)
		}
	}

	public static func observeAnOwnedDeviceWasDeleted(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.anOwnedDeviceWasDeleted.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoIdentity
			block(ownedCryptoId)
		}
	}

	public static func observeNewActiveOwnedIdentity(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.newActiveOwnedIdentity.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedCryptoIdentity = notification.userInfo!["ownedCryptoIdentity"] as! ObvCryptoIdentity
			block(ownedCryptoIdentity)
		}
	}

}

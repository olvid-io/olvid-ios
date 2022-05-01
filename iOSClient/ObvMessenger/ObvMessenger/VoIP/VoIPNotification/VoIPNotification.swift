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

fileprivate struct OptionalWrapper<T> {
	let value: T?
	public init() {
		self.value = nil
	}
	public init(_ value: T?) {
		self.value = value
	}
}

enum VoIPNotification {
	case userWantsToKickParticipant(call: GenericCall, callParticipant: CallParticipant)
	case userWantsToAddParticipants(call: GenericCall, contactIds: [OlvidUserId])
	case callHasBeenUpdated(callEssentials: CallEssentials, updateKind: CallUpdateKind)
	case callParticipantHasBeenUpdated(callParticipant: CallParticipant, updateKind: CallParticipantUpdateKind)
	case reportCallEvent(callUUID: UUID, callReport: CallReport, groupId: (groupUid: UID, groupOwner: ObvCryptoId)?, ownedCryptoId: ObvCryptoId)
	case showCallViewControllerForAnsweringNonCallKitIncomingCall(incomingCall: GenericCall)

	private enum Name {
		case userWantsToKickParticipant
		case userWantsToAddParticipants
		case callHasBeenUpdated
		case callParticipantHasBeenUpdated
		case reportCallEvent
		case showCallViewControllerForAnsweringNonCallKitIncomingCall

		private var namePrefix: String { String(describing: VoIPNotification.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: VoIPNotification) -> NSNotification.Name {
			switch notification {
			case .userWantsToKickParticipant: return Name.userWantsToKickParticipant.name
			case .userWantsToAddParticipants: return Name.userWantsToAddParticipants.name
			case .callHasBeenUpdated: return Name.callHasBeenUpdated.name
			case .callParticipantHasBeenUpdated: return Name.callParticipantHasBeenUpdated.name
			case .reportCallEvent: return Name.reportCallEvent.name
			case .showCallViewControllerForAnsweringNonCallKitIncomingCall: return Name.showCallViewControllerForAnsweringNonCallKitIncomingCall.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .userWantsToKickParticipant(call: let call, callParticipant: let callParticipant):
			info = [
				"call": call,
				"callParticipant": callParticipant,
			]
		case .userWantsToAddParticipants(call: let call, contactIds: let contactIds):
			info = [
				"call": call,
				"contactIds": contactIds,
			]
		case .callHasBeenUpdated(callEssentials: let callEssentials, updateKind: let updateKind):
			info = [
				"callEssentials": callEssentials,
				"updateKind": updateKind,
			]
		case .callParticipantHasBeenUpdated(callParticipant: let callParticipant, updateKind: let updateKind):
			info = [
				"callParticipant": callParticipant,
				"updateKind": updateKind,
			]
		case .reportCallEvent(callUUID: let callUUID, callReport: let callReport, groupId: let groupId, ownedCryptoId: let ownedCryptoId):
			info = [
				"callUUID": callUUID,
				"callReport": callReport,
				"groupId": OptionalWrapper(groupId),
				"ownedCryptoId": ownedCryptoId,
			]
		case .showCallViewControllerForAnsweringNonCallKitIncomingCall(incomingCall: let incomingCall):
			info = [
				"incomingCall": incomingCall,
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

	static func observeUserWantsToKickParticipant(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (GenericCall, CallParticipant) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToKickParticipant.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let call = notification.userInfo!["call"] as! GenericCall
			let callParticipant = notification.userInfo!["callParticipant"] as! CallParticipant
			block(call, callParticipant)
		}
	}

	static func observeUserWantsToAddParticipants(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (GenericCall, [OlvidUserId]) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToAddParticipants.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let call = notification.userInfo!["call"] as! GenericCall
			let contactIds = notification.userInfo!["contactIds"] as! [OlvidUserId]
			block(call, contactIds)
		}
	}

	static func observeCallHasBeenUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (CallEssentials, CallUpdateKind) -> Void) -> NSObjectProtocol {
		let name = Name.callHasBeenUpdated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let callEssentials = notification.userInfo!["callEssentials"] as! CallEssentials
			let updateKind = notification.userInfo!["updateKind"] as! CallUpdateKind
			block(callEssentials, updateKind)
		}
	}

	static func observeCallParticipantHasBeenUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (CallParticipant, CallParticipantUpdateKind) -> Void) -> NSObjectProtocol {
		let name = Name.callParticipantHasBeenUpdated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let callParticipant = notification.userInfo!["callParticipant"] as! CallParticipant
			let updateKind = notification.userInfo!["updateKind"] as! CallParticipantUpdateKind
			block(callParticipant, updateKind)
		}
	}

	static func observeReportCallEvent(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (UUID, CallReport, (groupUid: UID, groupOwner: ObvCryptoId)?, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.reportCallEvent.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let callUUID = notification.userInfo!["callUUID"] as! UUID
			let callReport = notification.userInfo!["callReport"] as! CallReport
			let groupIdWrapper = notification.userInfo!["groupId"] as! OptionalWrapper<(groupUid: UID, groupOwner: ObvCryptoId)>
			let groupId = groupIdWrapper.value
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(callUUID, callReport, groupId, ownedCryptoId)
		}
	}

	static func observeShowCallViewControllerForAnsweringNonCallKitIncomingCall(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (GenericCall) -> Void) -> NSObjectProtocol {
		let name = Name.showCallViewControllerForAnsweringNonCallKitIncomingCall.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let incomingCall = notification.userInfo!["incomingCall"] as! GenericCall
			block(incomingCall)
		}
	}

}

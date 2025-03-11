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
import CoreData
import ObvTypes
import ObvEngine
import OlvidUtils
import ObvCrypto
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

enum VoIPNotification {
	case reportCallEvent(callUUID: UUID, callReport: CallReport, groupId: GroupIdentifier?, ownedCryptoId: ObvCryptoId)
	case newCallToShow(model: OlvidCallViewController.Model)
	case noMoreCallInProgress
	case callWasEnded(uuidForCallKit: UUID)
	case serverDoesNotSupportCall
	case showCallView
	case hideCallView
	case newOwnedWebRTCMessageToSend(ownedCryptoId: ObvCryptoId, webrtcMessage: WebRTCMessageJSON)
	case anotherCallParticipantStartedCamera(otherParticipantNames: [String])

	private enum Name {
		case reportCallEvent
		case newCallToShow
		case noMoreCallInProgress
		case callWasEnded
		case serverDoesNotSupportCall
		case showCallView
		case hideCallView
		case newOwnedWebRTCMessageToSend
		case anotherCallParticipantStartedCamera

		private var namePrefix: String { String(describing: VoIPNotification.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: VoIPNotification) -> NSNotification.Name {
			switch notification {
			case .reportCallEvent: return Name.reportCallEvent.name
			case .newCallToShow: return Name.newCallToShow.name
			case .noMoreCallInProgress: return Name.noMoreCallInProgress.name
			case .callWasEnded: return Name.callWasEnded.name
			case .serverDoesNotSupportCall: return Name.serverDoesNotSupportCall.name
			case .showCallView: return Name.showCallView.name
			case .hideCallView: return Name.hideCallView.name
			case .newOwnedWebRTCMessageToSend: return Name.newOwnedWebRTCMessageToSend.name
			case .anotherCallParticipantStartedCamera: return Name.anotherCallParticipantStartedCamera.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .reportCallEvent(callUUID: let callUUID, callReport: let callReport, groupId: let groupId, ownedCryptoId: let ownedCryptoId):
			info = [
				"callUUID": callUUID,
				"callReport": callReport,
				"groupId": OptionalWrapper(groupId),
				"ownedCryptoId": ownedCryptoId,
			]
		case .newCallToShow(model: let model):
			info = [
				"model": model,
			]
		case .noMoreCallInProgress:
			info = nil
		case .callWasEnded(uuidForCallKit: let uuidForCallKit):
			info = [
				"uuidForCallKit": uuidForCallKit,
			]
		case .serverDoesNotSupportCall:
			info = nil
		case .showCallView:
			info = nil
		case .hideCallView:
			info = nil
		case .newOwnedWebRTCMessageToSend(ownedCryptoId: let ownedCryptoId, webrtcMessage: let webrtcMessage):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"webrtcMessage": webrtcMessage,
			]
		case .anotherCallParticipantStartedCamera(otherParticipantNames: let otherParticipantNames):
			info = [
				"otherParticipantNames": otherParticipantNames,
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
		DispatchQueue(label: label).async {
			NotificationCenter.default.post(name: name, object: anObject, userInfo: userInfo)
		}
	}

	static func observeReportCallEvent(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (UUID, CallReport, GroupIdentifier?, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.reportCallEvent.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let callUUID = notification.userInfo!["callUUID"] as! UUID
			let callReport = notification.userInfo!["callReport"] as! CallReport
			let groupIdWrapper = notification.userInfo!["groupId"] as! OptionalWrapper<GroupIdentifier>
			let groupId = groupIdWrapper.value
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(callUUID, callReport, groupId, ownedCryptoId)
		}
	}

	static func observeNewCallToShow(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (OlvidCallViewController.Model) -> Void) -> NSObjectProtocol {
		let name = Name.newCallToShow.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let model = notification.userInfo!["model"] as! OlvidCallViewController.Model
			block(model)
		}
	}

	static func observeNoMoreCallInProgress(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.noMoreCallInProgress.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeCallWasEnded(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (UUID) -> Void) -> NSObjectProtocol {
		let name = Name.callWasEnded.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let uuidForCallKit = notification.userInfo!["uuidForCallKit"] as! UUID
			block(uuidForCallKit)
		}
	}

	static func observeServerDoesNotSupportCall(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.serverDoesNotSupportCall.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeShowCallView(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.showCallView.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeHideCallView(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.hideCallView.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeNewOwnedWebRTCMessageToSend(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, WebRTCMessageJSON) -> Void) -> NSObjectProtocol {
		let name = Name.newOwnedWebRTCMessageToSend.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let webrtcMessage = notification.userInfo!["webrtcMessage"] as! WebRTCMessageJSON
			block(ownedCryptoId, webrtcMessage)
		}
	}

	static func observeAnotherCallParticipantStartedCamera(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping ([String]) -> Void) -> NSObjectProtocol {
		let name = Name.anotherCallParticipantStartedCamera.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let otherParticipantNames = notification.userInfo!["otherParticipantNames"] as! [String]
			block(otherParticipantNames)
		}
	}

}

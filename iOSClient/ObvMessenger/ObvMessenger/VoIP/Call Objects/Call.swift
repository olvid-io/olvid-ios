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
import CallKit
import ObvEngine
import ObvTypes

enum Role {
    case none
    case caller
    case recipient
}

typealias TurnSession = (sessionDescriptionType: String,
                         sessionDescription: String)

typealias TurnSessionWithCredentials = (sessionDescriptionType: String,
                         sessionDescription: String,
                         turnUserName: String?,
                         turnPassword: String?,
                         turnServersURL: [String]?)

protocol CallParticipantDelegate: AnyObject {

    var isOutgoingCall: Bool { get }
    var callParticipants: [CallParticipant] { get }

    func participantWasUpdated(callParticipant: CallParticipant, updateKind: CallParticipantUpdateKind)

    func connectionIsChecking(for callParticipant: CallParticipant)
    func connectionIsConnected(for callParticipant: CallParticipant)
    func connectionWasClosed(for callParticipant: CallParticipant)

    func dataChannelIsOpened(for callParticipant: CallParticipant)

    func updateParticipant(newCallParticipants: [ContactBytesAndNameJSON])
    func relay(from: ObvCryptoId, to: ObvCryptoId,
               messageType: WebRTCMessageJSON.MessageType, messagePayload: String)
    func receivedRelayedMessage(from: ObvCryptoId,
                                messageType: WebRTCMessageJSON.MessageType, messagePayload: String)

    func answerCallCompleted(for callParticipant: CallParticipant,
                             result: Result<TurnSession, Error>)

    func offerCallCompleted(for callParticipant: CallParticipant,
                            result: Result<TurnSessionWithCredentials, Error>)

    func restartCallCompleted(for callParticipant: CallParticipant,
                              result: Result<ReconnectCallMessageJSON, Error>)

    func shouldISendTheOfferToCallParticipant(contactIdentity: ObvCryptoId) -> Bool
}

struct ParticipantInfo {
    let contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>
    let isCaller: Bool
}

enum ParticipantId: Equatable, Hashable {
    case persisted(_ contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>)
    case cryptoId(_ cryptoId: ObvCryptoId)
}

enum ParticipantContactIdentificationStatus {
    case known(contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>)
    case unknown(cryptoId: ObvCryptoId, fullName: String)

    var contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>? {
        if case .known(let contactID) = self { return contactID} else { return nil }
    }
}

protocol TurnCredentials {
    var turnUserName: String { get }
    var turnPassword: String { get }
    var turnServers: [String]? { get }
}

struct TurnCredentialsImpl: TurnCredentials {
    let turnUserName: String
    let turnPassword: String
    let turnServers: [String]?
}

extension ObvTurnCredentials: TurnCredentials {
    var turnUserName: String { callerUsername }
    var turnPassword: String { callerPassword }
    var turnServers: [String]? { turnServersURL }
}

protocol CallParticipant: AnyObject {

    var uuid: UUID { get }
    var role: Role { get }
    var state: PeerState { get }
    var contactIsMuted: Bool { get }
    var isReady: Bool { get }

    var delegate: CallParticipantDelegate? { get set }

    var contactIdentificationStatus: ParticipantContactIdentificationStatus? { get }
    var info: ParticipantInfo? { get }
    var ownedIdentity: ObvCryptoId? { get }
    var contactIdentity: ObvCryptoId? { get }

    /// Use to be sent to others participants, we do not want to send the displayName that can include custom name
    var fullDisplayName: String? { get }
    var displayName: String? { get }
    var photoURL: URL? { get }
    var identityColors: (background: UIColor, text: UIColor)? { get }
    var turnCredentials: TurnCredentials? { get }

    func setPeerState(to state: PeerState)

    func createAnswer()
    func setCredentialsForOffer(turnCredentials: TurnCredentials)
    func createOffer()
    func handleReceivedRestartSdp(sessionDescriptionType: String,
                                  sessionDescription: String,
                                  reconnectCounter: Int,
                                  peerReconnectCounterToOverride: Int)

    func updateCaller(incomingCallMessage: IncomingCallMessageJSON, contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>)
    func updateRecipient(newParticipantOfferMessage: NewParticipantOfferMessageJSON, turnCredentials: TurnCredentials)

    func setRemoteDescription(sessionDescriptionType: String, sessionDescription: String, completionHandler: @escaping ((Error?) -> Void))
    func createRestartOffer()
    func closeConnection()

    func sendUpdateParticipantsMessageJSON(callParticipants: [CallParticipant])
    func sendDataChannelMessage(_ message: WebRTCDataChannelMessageJSON) throws

    var isMuted: Bool { get }
    func mute()
    func unmute()

    func invalidateTimeout()
}

protocol ContactInfo {
    var objectID: TypeSafeManagedObjectID<PersistedObvContactIdentity> { get }
    var ownedIdentity: ObvCryptoId? { get }
    var cryptoId: ObvCryptoId? { get }
    var fullDisplayName: String { get }
    var customDisplayName: String? { get }
    var sortDisplayName: String { get }
    var photoURL: URL? { get }
    var identityColors: (background: UIColor, text: UIColor)? { get }
}

protocol Call: AnyObject {

    var uuid: UUID { get }
    var uuidForWebRTC: UUID? { get }
    var groupId: (groupUid: UID, groupOwner: ObvCryptoId)? { get }
    var usesCallKit: Bool { get }
    var ownedIdentity: ObvCryptoId? { get }

    var endCallActionWasRequested: Bool { get set }

    var callParticipants: [CallParticipant] { get }
    var state: CallState { get }
    var stateDate: [CallState: Date] { get }
    var isMuted: Bool { get }

    func getParticipant(contact: ParticipantId) -> CallParticipant?
    func addParticipant(callParticipant: CallParticipant, report: Bool)

    func sendWebRTCMessage(to: CallParticipant, message: WebRTCMessageJSON, forStartingCall: Bool, completion: @escaping () -> Void)

    func mute(completion: ((ObvErrorCodeRequestTransactionError?) -> Void)?)
    func unmute(completion: ((ObvErrorCodeRequestTransactionError?) -> Void)?)

    func setKicked()
    func setUnanswered()

    func endCall(completion: ((ObvErrorCodeRequestTransactionError?) -> Void)?)

    func createRestartOffer()
    func handleReconnectCallMessage(callParticipant: CallParticipant, _ : ReconnectCallMessageJSON)

    func shouldISendTheOfferToCallParticipant(contactIdentity: ObvCryptoId) -> Bool
    func updateStateFromPeerStates()

    func scheduleCallTimeout()
    func invalidateCallTimeout()
}

enum ObvErrorCodeRequestTransactionError: Int {
    case unknown = 0
    case unentitled = 1
    case unknownCallProvider = 2
    case emptyTransaction = 3
    case unknownCallUUID = 4
    case callUUIDAlreadyExists = 5
    case invalidAction = 6
    case maximumCallGroupsReached = 7

    var localizedDescription: String {
        switch self {
        case .unknown: return "unknown"
        case .unentitled: return "unentitled"
        case .unknownCallProvider: return "unknownCallProvider"
        case .emptyTransaction: return "emptyTransaction"
        case .unknownCallUUID: return "unknownCallUUID"
        case .callUUIDAlreadyExists: return "callUUIDAlreadyExists"
        case .invalidAction: return "invalidAction"
        case .maximumCallGroupsReached: return "maximumCallGroupsReached"
        }
    }
}

protocol IncomingCall: Call {
    var messageIdentifierFromEngine: Data { get }
    var userAnsweredIncomingCall: Bool { get }
    var ringingMessageShouldBeSent: Bool { get set }
    var callHasBeenFiltered: Bool { get set }
    var receivedOfferMessages: [ParticipantId: (Date, NewParticipantOfferMessageJSON)] { get set}
    var callerCallParticipant: CallParticipant? { get }
    var initialParticipantCount: Int? { get }
    func answerCall(completion: ((ObvErrorCodeRequestTransactionError?) -> Void)?)
    func pushKitNotificationReceived()
    func setDecryptedElements(incomingCallMessage: IncomingCallMessageJSON, contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, uuidForWebRTC: UUID)

}
protocol OutgoingCall: Call {
    func startCall(contactIdentifier: String, handleValue: String, completion: ((ObvErrorCodeRequestTransactionError?) -> Void)?)
    func processAnswerIncomingCallJSON(callParticipant: CallParticipant, _: AnswerIncomingCallJSON, completionHandler: @escaping ((Error?) -> Void))
    func getParticipant(contact: ParticipantId) -> CallParticipant?
    func processUserWantsToAddParticipants(contactIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>])
    func setPermissionDeniedByServer()
    func setCallInitiationNotSupported()
}

enum CallUpdateKind {
    case state(newState: CallState)
    case mute
    case callParticipantChange
}

enum CallParticipantUpdateKind {
    case state(newState: PeerState)
    case contactID
    case contactMuted
}

enum CallState: Hashable, CustomDebugStringConvertible {
    case initial
    case userAnsweredIncomingCall
    case gettingTurnCredentials // Only for outgoing calls
    case initializingCall
    case ringing
    case callInProgress

    case hangedUp
    case kicked
    case callRejected

    case permissionDeniedByServer
    case unanswered
    case callInitiationNotSupported

    var debugDescription: String {
        switch self {
        case .kicked: return "kicked"
        case .userAnsweredIncomingCall: return "userAnsweredIncomingCall"
        case .gettingTurnCredentials: return "gettingTurnCredentials"
        case .initializingCall: return "initializingCall"
        case .ringing: return "ringing"
        case .initial: return "initial"
        case .callRejected: return "callRejected"
        case .callInProgress: return "callInProgress"
        case .hangedUp: return "hangedUp"
        case .permissionDeniedByServer: return "permissionDeniedByServer"
        case .unanswered: return "unanswered"
        case .callInitiationNotSupported: return "callInitiationNotSupported"
        }
    }

    var isFinalState: Bool {
        switch self {
        case .callRejected, .hangedUp, .unanswered, .callInitiationNotSupported, .kicked: return true
        case .gettingTurnCredentials, .userAnsweredIncomingCall, .initializingCall, .ringing, .initial, .callInProgress, .permissionDeniedByServer: return false
        }
    }
}

enum PeerState: Hashable, CustomDebugStringConvertible {
    case initial
    case startCallMessageSent
    case ringing
    case busy
    case callRejected
    case connectingToPeer
    case connected
    case reconnecting
    case hangedUp
    case kicked
    case timeout

    var debugDescription: String {
        switch self {
        case .initial: return "initial"
        case .startCallMessageSent: return "startCallMessageSent"
        case .busy: return "busy"
        case .reconnecting: return "reconnecting"
        case .ringing: return "ringing"
        case .callRejected: return "callRejected"
        case .connectingToPeer: return "connectingToPeer"
        case .connected: return "connected"
        case .hangedUp: return "hangedUp"
        case .kicked: return "kicked"
        case .timeout: return "timeout"
        }
    }

    var isFinalState: Bool {
        switch self {
        case .callRejected, .hangedUp, .kicked, .timeout: return true
        case .initial, .startCallMessageSent, .ringing, .busy, .connectingToPeer, .connected, .reconnecting: return false
        }
    }

}

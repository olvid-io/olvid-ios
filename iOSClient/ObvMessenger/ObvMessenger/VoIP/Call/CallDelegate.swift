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


// MARK: - CallDelegate

protocol CallDelegate: AnyObject {
    
    func processReceivedWebRTCMessage(messageType: WebRTCMessageJSON.MessageType, serializedMessagePayload: String, callIdentifier: UUID, contact: OlvidUserId, messageUploadTimestampFromServer: Date, messageIdentifierFromEngine: Data?) async
    func processNewParticipantOfferMessageJSON(_ newParticipantOffer: NewParticipantOfferMessageJSON, uuidForWebRTC: UUID, contact: OlvidUserId, messageUploadTimestampFromServer: Date) async throws
    static func report(call: Call, report: CallReport)
    func newParticipantWasAdded(call: Call, callParticipant: CallParticipant) async
    func callReachedFinalState(call: Call) async
    func outgoingCallReachedReachedInProgressState(call: Call) async
    func callOutOfBoundEnded(call: Call, reason: ObvCallEndedReason) async

}


// MARK: - IncomingCallDelegate

protocol IncomingCallDelegate: CallDelegate {}


// MARK: - OutgoingCallDelegate

protocol OutgoingCallDelegate: CallDelegate {
    func turnCredentialsRequiredByOutgoingCall(outgoingCallUuidForWebRTC: UUID, forOwnedIdentity ownedIdentityCryptoId: ObvCryptoId) async
}

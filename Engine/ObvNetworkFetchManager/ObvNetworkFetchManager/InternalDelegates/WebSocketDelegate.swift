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

protocol WebSocketDelegate {
    
    func connectAll(flowId: FlowIdentifier) async
    func disconnectAll(flowId: FlowIdentifier) async

    func setWebSocketServerURL(for serverURL: URL, to webSocketServerURL: URL) async
    func setDeviceUid(to deviceUid: UID, for identity: ObvCryptoIdentity) async
    func setServerSessionToken(to token: Data, for identity: ObvCryptoIdentity) async

    func sendDeleteReturnReceipt(ownedIdentity: ObvCryptoIdentity, serverUid: UID) async throws

    func getWebSocketState(ownedIdentity: ObvCryptoIdentity) async throws -> (URLSessionTask.State,TimeInterval?)

    func updateListOfOwnedIdentites(ownedIdentities: Set<ObvCryptoIdentity>, flowId: FlowIdentifier) async

}

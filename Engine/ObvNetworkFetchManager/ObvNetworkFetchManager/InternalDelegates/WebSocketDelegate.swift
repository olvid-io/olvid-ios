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
    
    func applicationDidStartRunning(flowId: FlowIdentifier)
    func applicationDidEnterBackground()

    func connectAll()

    func setWebSocketServerURL(to webSocketServerURL: URL, for identity: ObvCryptoIdentity)
    func setDeviceUid(to deviceUid: UID, for identity: ObvCryptoIdentity)
    func setServerSessionToken(to token: Data, for identity: ObvCryptoIdentity)
    func updateWebSocketServerURL(for serverURL: URL, to webSocketServerURL: URL)

    func sendDeleteReturnReceipt(ownedIdentity: ObvCryptoIdentity, serverUid: UID) throws

    func getWebSocketState(ownedIdentity: ObvCryptoIdentity, completionHander: @escaping (Result<(URLSessionTask.State,TimeInterval?),Error>) -> Void)

    func updatedListOfOwnedIdentites(ownedIdentities: Set<ObvCryptoIdentity>, flowId: FlowIdentifier)

}

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
import ObvTypes


struct TurnCredentials {
    let turnUserName: String
    let turnPassword: String
    let turnServers: [String]?
}


extension ObvTurnCredentials {

    var turnCredentialsForCaller: TurnCredentials {
        TurnCredentials(turnUserName: callerUsername,
                        turnPassword: callerPassword,
                        turnServers: turnServersURL)
    }

    var turnCredentialsForRecipient: TurnCredentials {
        TurnCredentials(turnUserName: recipientUsername,
                        turnPassword: recipientPassword,
                        turnServers: turnServersURL)
    }

}


extension StartCallMessageJSON {

    var turnCredentials: TurnCredentials {
        TurnCredentials(turnUserName: turnUserName,
                        turnPassword: turnPassword,
                        turnServers: turnServers)
    }

}

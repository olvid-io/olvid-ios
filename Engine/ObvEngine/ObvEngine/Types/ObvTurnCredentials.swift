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

public struct ObvTurnCredentials {
    public let callerUsername: String
    public let callerPassword: String
    public let recipientUsername: String
    public let recipientPassword: String
    public let turnServersURL: [String]
    public init(callerUsername: String, callerPassword: String, recipientUsername: String, recipientPassword: String, turnServersURL: [String]) {
        self.callerUsername = callerUsername
        self.callerPassword = callerPassword
        self.recipientUsername = recipientUsername
        self.recipientPassword = recipientPassword
        self.turnServersURL = turnServersURL
    }
}

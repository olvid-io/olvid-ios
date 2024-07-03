/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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


public struct ObvNetworkFetchError {
    
    private static let descriptionPrefix = "[ObvNetworkFetchError]"
    
    public enum RegisterPushNotificationError: LocalizedError {
        
        case anotherDeviceIsAlreadyRegistered
        case couldNotParseReturnStatusFromServer
        case deviceToReplaceIsNotRegistered
        case invalidServerResponse
        case theDelegateManagerIsNotSet
        case failedToCreateServerMethod
        
        private static let descriptionPrefix = "[RegisterPushNotificationError]"

        public var errorDescription: String? {
            let description: String
            switch self {
            case .anotherDeviceIsAlreadyRegistered:
                description = "Another device is already registered"
            case .couldNotParseReturnStatusFromServer:
                description = "Could not parse the status returned by the server"
            case .deviceToReplaceIsNotRegistered:
                description = "Device to replace is not registered"
            case .invalidServerResponse:
                description = "Invalid server response"
            case .theDelegateManagerIsNotSet:
                description = "The delegate manager is not set"
            case .failedToCreateServerMethod:
                description = "Failed to create server method"
            }
            return [ObvNetworkFetchError.descriptionPrefix, Self.descriptionPrefix, description].joined(separator: " ")
        }
    }
}

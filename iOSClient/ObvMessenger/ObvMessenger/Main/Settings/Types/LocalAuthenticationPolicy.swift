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
import LocalAuthentication

enum AuthenticationMethod {
    case none
    case passcode
    case touchID
    case faceID

    static func currentBiometricEnrollement() -> LABiometryType? {
        var error: NSError?
        let laContext = LAContext()

        if laContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return laContext.biometryType
        } else {
            return nil
        }
    }

    static func bestAvailableAuthenticationMethod() -> AuthenticationMethod {
        // Check for available authentication methods
        var error: NSError?
        let laContext = LAContext()

        // We first check whether Touch ID or Face ID is unavailable or not enrolled
        if let biometryType = currentBiometricEnrollement() {
            switch biometryType {
            case .none: break
            case .touchID:
                return .touchID
            case .faceID:
                return .faceID
            @unknown default: assertionFailure()
            }
        } else {
            // No authentication with biometrics, check if passcode is available
            if laContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
                return .passcode
            }
        }
        return .none
    }

}

enum LocalAuthenticationPolicy: Int, CaseIterable {
    // No authentication
    case none
    // User authentication with biometry, Apple Watch, or the device passcode.
    case deviceOwnerAuthentication
    // User authentication with biometry, with custom passcode fallback
    case biometricsWithCustomPasscodeFallback
    // User authentication with custom passcode only
    case customPasscode

    var lockScreen: Bool {
        switch self {
        case .none: return false
        case .deviceOwnerAuthentication, .biometricsWithCustomPasscodeFallback, .customPasscode: return true
        }
    }

    var useCustomPasscode: Bool {
        switch self {
        case .none, .deviceOwnerAuthentication: return false
        case .biometricsWithCustomPasscodeFallback, .customPasscode: return true
        }
    }

    func isAvailable(whenBestAvailableAuthenticationMethodIs method: AuthenticationMethod) -> Bool {
        switch self {
        case .none:
            return true
        case .deviceOwnerAuthentication:
            return method != .none
        case .biometricsWithCustomPasscodeFallback:
            switch method {
            case .none, .passcode: return false
            case .touchID, .faceID: return true
            }
        case .customPasscode:
            return true
        }
    }

}

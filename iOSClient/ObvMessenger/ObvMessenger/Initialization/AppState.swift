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

enum RawAppState {
    
    case justLaunched
    case initializing
    case initialized
    
}

enum IOSAppState: CustomDebugStringConvertible {
    
    case inBackground
    case notActive
    case mayResignActive
    case active

    var debugDescription: String {
        switch self {
        case .notActive: return "Not active"
        case .mayResignActive: return "May resign active"
        case .active: return "Active"
        case .inBackground: return "In background"
        }
    }
    
}


enum AppState: CustomDebugStringConvertible, Equatable {
    
    case justLaunched(iOSAppState: IOSAppState, authenticateAutomaticallyNextTime: Bool, callInProgress: CallEssentials?, aCallRequiresNetworkConnection: Bool)
    case initializing(iOSAppState: IOSAppState, authenticateAutomaticallyNextTime: Bool, callInProgress: CallEssentials?, aCallRequiresNetworkConnection: Bool)
    case initialized(iOSAppState: IOSAppState, authenticated: Bool, authenticateAutomaticallyNextTime: Bool, callInProgress: CallEssentials?, aCallRequiresNetworkConnection: Bool)

    var raw: RawAppState {
        switch self {
        case .justLaunched: return RawAppState.justLaunched
        case .initializing: return RawAppState.initializing
        case .initialized: return RawAppState.initialized
        }
    }
    
    var iOSAppState: IOSAppState {
        switch self {
        case .justLaunched(iOSAppState: let iOSAppState, authenticateAutomaticallyNextTime: _, callInProgress: _, aCallRequiresNetworkConnection: _):
            return iOSAppState
        case .initializing(iOSAppState: let iOSAppState, authenticateAutomaticallyNextTime: _, callInProgress: _, aCallRequiresNetworkConnection: _):
            return iOSAppState
        case .initialized(iOSAppState: let iOSAppState, authenticated: _, authenticateAutomaticallyNextTime: _, callInProgress: _, aCallRequiresNetworkConnection: _):
            return iOSAppState
        }
    }
    
    var isInitializedAndActive: Bool {
        switch self {
        case .initialized(iOSAppState: let iOSState, authenticated: _, authenticateAutomaticallyNextTime: _, callInProgress: _, aCallRequiresNetworkConnection: _):
            return iOSState == .active
        default:
            return false
        }
    }
    
    var isInitialized: Bool {
        switch self {
        case .initialized: return true
        default: return false
        }
    }

    var isInitializing: Bool {
        switch self {
        case .initializing: return true
        default: return false
        }
    }

    var isJustLaunched: Bool {
        switch self {
        case .justLaunched: return true
        default: return false
        }
    }

    var isAuthenticated: Bool {
        switch self {
        case .justLaunched, .initializing:
            return false
        case .initialized(iOSAppState: _, authenticated: let authenticated, authenticateAutomaticallyNextTime: _, callInProgress: _, aCallRequiresNetworkConnection: _):
            return authenticated
        }
    }
    
    var debugDescription: String {
        switch self {
        case .justLaunched(iOSAppState: let iOSAppState, authenticateAutomaticallyNextTime: let next, callInProgress: let callAndState, aCallRequiresNetworkConnection: let aCallRequiresNetworkConnection):
            if let callAndState = callAndState {
                return "Just Launched (\(iOSAppState), authenticateAutomaticallyNextTime: \(next), callInProgress: \(callAndState.uuid.uuidString.prefix(4)) | \(callAndState.state), aCallRequiresNetworkConnection: \(aCallRequiresNetworkConnection))"
            } else {
                return "Just Launched (\(iOSAppState), authenticateAutomaticallyNextTime: \(next), callInProgress: None, aCallRequiresNetworkConnection: \(aCallRequiresNetworkConnection))"
            }
        case .initializing(iOSAppState: let iOSAppState, authenticateAutomaticallyNextTime: let next, callInProgress: let callAndState, aCallRequiresNetworkConnection: let aCallRequiresNetworkConnection):
            if let callAndState = callAndState {
                return "Initializing (\(iOSAppState), authenticateAutomaticallyNextTime: \(next), callInProgress: \(callAndState.uuid.uuidString.prefix(4)) | \(callAndState.state), aCallRequiresNetworkConnection: \(aCallRequiresNetworkConnection))"
            } else {
                return "Initializing (\(iOSAppState), authenticateAutomaticallyNextTime: \(next), callInProgress: None, aCallRequiresNetworkConnection: \(aCallRequiresNetworkConnection))"
            }
        case .initialized(iOSAppState: let iOSAppState, authenticated: let authenticated, authenticateAutomaticallyNextTime: let next, callInProgress: let callAndState, aCallRequiresNetworkConnection: let aCallRequiresNetworkConnection):
            if let callAndState = callAndState {
                return "Initialized (\(iOSAppState), authenticated: \(authenticated), authenticateAutomaticallyNextTime: \(next), callInProgress: \(callAndState.uuid.uuidString.prefix(4)) | \(callAndState.state), aCallRequiresNetworkConnection: \(aCallRequiresNetworkConnection))"
            } else {
                return "Initialized (\(iOSAppState), authenticated: \(authenticated), authenticateAutomaticallyNextTime: \(next), callInProgress: None, aCallRequiresNetworkConnection: \(aCallRequiresNetworkConnection))"
            }
        }
    }
    
    static func == (lhs: AppState, rhs: AppState) -> Bool {
        switch lhs {
        case .justLaunched(iOSAppState: let a0, authenticateAutomaticallyNextTime: let a1, callInProgress: let a2, aCallRequiresNetworkConnection: let a3):
            switch rhs {    
            case .justLaunched(iOSAppState: let b0, authenticateAutomaticallyNextTime: let b1, callInProgress: let b2, aCallRequiresNetworkConnection: let b3):
                return a0 == b0 && a1 == b1 && a2?.uuid == b2?.uuid && a2?.state == b2?.state && a3 == b3
            default:
                return false
            }
        case .initializing(iOSAppState: let a0, authenticateAutomaticallyNextTime: let a1, callInProgress: let a2, aCallRequiresNetworkConnection: let a3):
            switch rhs {
            case .initializing(iOSAppState: let b0, authenticateAutomaticallyNextTime: let b1, callInProgress: let b2, aCallRequiresNetworkConnection: let b3):
                return a0 == b0 && a1 == b1 && a2?.uuid == b2?.uuid && a2?.state == b2?.state && a3 == b3
            default:
                return false
            }
        case .initialized(iOSAppState: let a0, authenticated: let a1, authenticateAutomaticallyNextTime: let a2, callInProgress: let a3, aCallRequiresNetworkConnection: let a4):
            switch rhs {
            case .initialized(iOSAppState: let b0, authenticated: let b1, authenticateAutomaticallyNextTime: let b2, callInProgress: let b3, aCallRequiresNetworkConnection: let b4):
                return a0 == b0 && a1 == b1 && a2 == b2 && a3?.uuid == b3?.uuid && a3?.state == b3?.state && a4 == b4
            default:
                return false
            }
        }
    }

    var callInProgress: CallEssentials? {
        switch self {
        case .justLaunched(iOSAppState: _, authenticateAutomaticallyNextTime: _, callInProgress: let callAndState, aCallRequiresNetworkConnection: _),
                .initializing(iOSAppState: _, authenticateAutomaticallyNextTime: _, callInProgress: let callAndState, aCallRequiresNetworkConnection: _),
                .initialized(iOSAppState: _, authenticated: _, authenticateAutomaticallyNextTime: _, callInProgress: let callAndState, aCallRequiresNetworkConnection: _):
            return callAndState
        }
    }
    
    var aCallRequiresNetworkConnection: Bool {
        switch self {
        case .justLaunched(iOSAppState: _, authenticateAutomaticallyNextTime: _, callInProgress: _, aCallRequiresNetworkConnection: let aCallRequiresNetworkConnection),
                .initializing(iOSAppState: _, authenticateAutomaticallyNextTime: _, callInProgress: _, aCallRequiresNetworkConnection: let aCallRequiresNetworkConnection),
                .initialized(iOSAppState: _, authenticated: _, authenticateAutomaticallyNextTime: _, callInProgress: _, aCallRequiresNetworkConnection: let aCallRequiresNetworkConnection):
            return aCallRequiresNetworkConnection
        }
    }
    
}

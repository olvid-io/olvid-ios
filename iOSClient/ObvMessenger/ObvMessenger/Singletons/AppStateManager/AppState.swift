/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

typealias CallAndState = (call: Call, state: CallState)

enum AppState: CustomDebugStringConvertible, Equatable {
    
    case justLaunched(iOSAppState: IOSAppState, authenticateAutomaticallyNextTime: Bool, callInProgress: CallAndState?)
    case initializing(iOSAppState: IOSAppState, authenticateAutomaticallyNextTime: Bool, callInProgress: CallAndState?)
    case initialized(iOSAppState: IOSAppState, authenticated: Bool, authenticateAutomaticallyNextTime: Bool, callInProgress: CallAndState?)

    var raw: RawAppState {
        switch self {
        case .justLaunched: return RawAppState.justLaunched
        case .initializing: return RawAppState.initializing
        case .initialized: return RawAppState.initialized
        }
    }
    
    var iOSAppState: IOSAppState {
        switch self {
        case .justLaunched(iOSAppState: let iOSAppState, authenticateAutomaticallyNextTime: _, callInProgress: _):
            return iOSAppState
        case .initializing(iOSAppState: let iOSAppState, authenticateAutomaticallyNextTime: _, callInProgress: _):
            return iOSAppState
        case .initialized(iOSAppState: let iOSAppState, authenticated: _, authenticateAutomaticallyNextTime: _, callInProgress: _):
            return iOSAppState
        }
    }
    
    var isInitializedAndActive: Bool {
        switch self {
        case .initialized(iOSAppState: let iOSState, authenticated: _, authenticateAutomaticallyNextTime: _, callInProgress: _):
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
        case .initialized(iOSAppState: _, authenticated: let authenticated, authenticateAutomaticallyNextTime: _, callInProgress: _):
            return authenticated
        }
    }
    
    var debugDescription: String {
        switch self {
        case .justLaunched(iOSAppState: let iOSAppState, authenticateAutomaticallyNextTime: let next, callInProgress: let callAndState):
            if let callAndState = callAndState {
                return "Just Launched (\(iOSAppState), authenticateAutomaticallyNextTime: \(next), callInProgress: \(callAndState.call.uuid.uuidString.prefix(4)) | \(callAndState.state))"
            } else {
                return "Just Launched (\(iOSAppState), authenticateAutomaticallyNextTime: \(next), callInProgress: None)"
            }
        case .initializing(iOSAppState: let iOSAppState, authenticateAutomaticallyNextTime: let next, callInProgress: let callAndState):
            if let callAndState = callAndState {
                return "Initializing (\(iOSAppState), authenticateAutomaticallyNextTime: \(next), callInProgress: \(callAndState.call.uuid.uuidString.prefix(4)) | \(callAndState.state))"
            } else {
                return "Initializing (\(iOSAppState), authenticateAutomaticallyNextTime: \(next), callInProgress: None)"
            }
        case .initialized(iOSAppState: let iOSAppState, authenticated: let authenticated, authenticateAutomaticallyNextTime: let next, callInProgress: let callAndState):
            if let callAndState = callAndState {
                return "Initialized (\(iOSAppState), authenticated: \(authenticated), authenticateAutomaticallyNextTime: \(next), callInProgress: \(callAndState.call.uuid.uuidString.prefix(4)) | \(callAndState.state))"
            } else {
                return "Initialized (\(iOSAppState), authenticated: \(authenticated), authenticateAutomaticallyNextTime: \(next), callInProgress: None)"
            }
        }
    }
    
    static func == (lhs: AppState, rhs: AppState) -> Bool {
        switch lhs {
        case .justLaunched(iOSAppState: let a0, authenticateAutomaticallyNextTime: let a1, callInProgress: let a2):
            switch rhs {
            case .justLaunched(iOSAppState: let b0, authenticateAutomaticallyNextTime: let b1, callInProgress: let b2):
                return a0 == b0 && a1 == b1 && a2?.call.uuid == b2?.call.uuid && a2?.state == b2?.state
            default:
                return false
            }
        case .initializing(iOSAppState: let a0, authenticateAutomaticallyNextTime: let a1, callInProgress: let a2):
            switch rhs {
            case .initializing(iOSAppState: let b0, authenticateAutomaticallyNextTime: let b1, callInProgress: let b2):
                return a0 == b0 && a1 == b1 && a2?.call.uuid == b2?.call.uuid && a2?.state == b2?.state
            default:
                return false
            }
        case .initialized(iOSAppState: let a0, authenticated: let a1, authenticateAutomaticallyNextTime: let a2, callInProgress: let a3):
            switch rhs {
            case .initialized(iOSAppState: let b0, authenticated: let b1, authenticateAutomaticallyNextTime: let b2, callInProgress: let b3):
                return a0 == b0 && a1 == b1 && a2 == b2 && a3?.call.uuid == b3?.call.uuid && a3?.state == b3?.state
            default:
                return false
            }
        }
    }

    var callInProgress: Call? {
        switch self {
        case .justLaunched(iOSAppState: _, authenticateAutomaticallyNextTime: _, callInProgress: let callAndState):
            return callAndState?.call
        case .initializing(iOSAppState: _, authenticateAutomaticallyNextTime: _, callInProgress: let callAndState):
            return callAndState?.call
        case .initialized(iOSAppState: _, authenticated: _, authenticateAutomaticallyNextTime: _, callInProgress: let callAndState):
            return callAndState?.call
        }
    }
}

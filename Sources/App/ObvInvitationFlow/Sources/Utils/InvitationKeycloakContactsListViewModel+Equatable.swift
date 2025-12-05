/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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


extension InvitationKeycloakContactsListViewModel: Equatable {
    
    public static func == (lhs: InvitationKeycloakContactsListViewModel, rhs: InvitationKeycloakContactsListViewModel) -> Bool {
        switch lhs {
        case .success(let a):
            switch rhs {
            case .success(let b):
                return a == b
            default:
                return false
            }
        case .searchError(let lhsSearchError):
            switch rhs {
            case .searchError(let rhsSearchError):
                switch lhsSearchError {
                case .authenticationRequired:
                    switch rhsSearchError {
                    case .authenticationRequired:
                        return true
                    default:
                        return false
                    }
                case .ownedIdentityNotManaged:
                    switch rhsSearchError {
                    case .ownedIdentityNotManaged:
                        return true
                    default:
                        return false
                    }
                case .userHasCancelled:
                    switch rhsSearchError {
                    case .userHasCancelled:
                        return true
                    default:
                        return false
                    }
                case .keycloakApiRequest(_):
                    switch rhsSearchError {
                    case .keycloakApiRequest:
                        return true
                    default:
                        return false
                    }
                case .unkownError(_):
                    switch rhsSearchError {
                    case .unkownError:
                        return true
                    default:
                        return false
                    }
                }
            default:
                return false
            }
        }
    }
    
}

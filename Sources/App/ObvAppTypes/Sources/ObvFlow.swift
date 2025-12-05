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


/// Represents one of the four possible user flows within the Olvid app.
///
/// This enum is used to:
/// - Track the user's current activity in `OlvidUserActivity`.
/// - Tag tabs in the `UITabBarController` (implemented by `ObvSubTabBarControllerNew`).
/// - Tag sidebar items in the `primary` column of the `UISplitViewController` (implemented by `MainFlowViewController`).
public enum ObvFlow: String, Equatable, Sendable, CaseIterable {
    case latestDiscussions = "latestDiscussions"
    case contacts = "contacts"
    case groups = "groups"
    case invitations = "invitations"
}


extension ObvFlow: CustomDebugStringConvertible {
    
    public var debugDescription: String {
        self.rawValue
    }
    
}

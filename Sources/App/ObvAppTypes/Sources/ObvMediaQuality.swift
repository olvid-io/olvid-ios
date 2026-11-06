/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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


/// The quality at which photos and videos are sent.
///
/// Lives here rather than beside the share extension's UI because the user's last choice is remembered in
/// `ObvMessengerSettings`, which sits below that module.
public enum ObvMediaQuality: String, CaseIterable, Identifiable, Sendable {

    /// HD - original quality
    case high

    /// SD - compressed/transcoded
    case standard

    public var id: String { rawValue }

}

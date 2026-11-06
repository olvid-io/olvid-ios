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


/// A custom server together with an *optional* API key (license).
///
/// Unlike ``ServerAndAPIKey`` — whose `apiKey` is non-optional and which doubles as a wire/license type in
/// OlvidURL parsing — this type represents the case where a custom server is known but the API key may be
/// absent. Typically produced when a scanned configuration is processed during onboarding:
///
/// - the user accepts a usable scanned key → `apiKey` is non-`nil` (generate on `server`, register the key);
/// - the user keeps only the scanned custom server because its key is already used → `apiKey` is `nil`
///   (generate on `server`, register nothing).
public struct CustomServerAndOptionalAPIKey: Sendable, Equatable {

    public let server: URL
    public let apiKey: UUID?

    public init(server: URL, apiKey: UUID?) {
        self.server = server
        self.apiKey = apiKey
    }

}

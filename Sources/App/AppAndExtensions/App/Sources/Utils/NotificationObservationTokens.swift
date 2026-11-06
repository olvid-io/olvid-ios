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


/// Holds notification observation tokens and removes the observations when it is freed.
///
/// A holder rather than an array and a `deinit` on the observing object, because of isolation: a view controller is
/// main-actor isolated, a global-actor-isolated class's `deinit` is nonisolated, and it may not read an isolated
/// stored property of non-`Sendable` type such as `[NSObjectProtocol]`. This class is isolated to nothing, so
/// letting go of it is the teardown, and the owner needs no `deinit`.
final class NotificationObservationTokens {

    private let tokens: [NSObjectProtocol]

    init(_ tokens: [NSObjectProtocol]) {
        self.tokens = tokens
    }

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

}

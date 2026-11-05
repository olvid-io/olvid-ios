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
import CoreData

/// Runs `body` on a fresh background Core Data context and bridges the result back to the
/// calling async context via a checked throwing continuation.
///
/// **Contract for `body` implementations:**
/// - To return a value: call `continuation.resume(returning:)` and return normally.
/// - To signal an error: throw — do **not** call `continuation.resume(throwing:)` directly.
///   The catch block handles that. Calling `continuation.resume(throwing:)` and then throwing
///   is a double-resume and causes a fatal error at runtime.
func withCheckedThrowingContextualContinuation<T>( _ body: @escaping (CheckedContinuation<T, any Error>, NSManagedObjectContext) throws -> Void) async throws -> sending T {
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in

        ObvStack.shared.performBackgroundTask { context in
            do {
                try body(continuation, context)
            } catch {
                return continuation.resume(throwing: error)
            }
        }
    }
}


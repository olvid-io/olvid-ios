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
import CoreData

enum ContextualContinuationResultWithAdditionalInfos<T> {
    case contextHasNoChanges
    case contextHasChanges(T, contextToSave: NSManagedObjectContext)
}

enum ContextualContinuationResult {
    case contextHasNoChanges
    case contextHasChanges(contextToSave: NSManagedObjectContext)
}

func withCheckedThrowingContextualContinuation<T>( _ body: @escaping (CheckedContinuation<ContextualContinuationResultWithAdditionalInfos<T>, any Error>, NSManagedObjectContext) throws -> Void) async throws -> sending ContextualContinuationResultWithAdditionalInfos<T> {
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ContextualContinuationResultWithAdditionalInfos<T>, any Error>) in
        ObvStack.shared.performBackgroundTask { context in
            do {
                try body(continuation, context)
            } catch {
                return continuation.resume(throwing: error)
            }
        }
    }
}


func withCheckedThrowingContextualContinuation( _ body: @escaping (CheckedContinuation<ContextualContinuationResult, any Error>, NSManagedObjectContext) throws -> Void) async throws -> sending ContextualContinuationResult {
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ContextualContinuationResult, any Error>) in
        ObvStack.shared.performBackgroundTask { context in
            do {
                try body(continuation, context)
            } catch {
                return continuation.resume(throwing: error)
            }
        }
    }
}


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

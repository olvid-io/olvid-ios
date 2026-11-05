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

import Intents
import OSLog
import ObvAppTypes
import ObvAppCoreConstants


/// Handles `INSetMessageAttributeIntent` within the Intents extension.
///
/// Only the `.read` attribute is supported; all other attributes are rejected at the resolution
/// step so Siri can report an appropriate error without reaching `handle`.
///
/// **Intent lifecycle**
/// 1. ``resolveAttribute(for:)`` — accepts `.read`; rejects all other values with `.unsupported()`.
/// 2. ``confirm(intent:)`` — verifies that identifiers are present and the attribute is `.read`;
///    returns `.ready` or `.failure`.
/// 3. ``handle(intent:)`` — marks each message identified by `intent.identifiers` as read via
///    the coordinator. All identifiers are attempted even if one fails; returns `.success` when all
///    succeed, `.failureMessageNotFound` when an identifier cannot be decoded, `.failure` on a
///    coordinator error.
final class SetMessageAttributeIntentHandler: NSObject {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "SetMessageAttributeIntentHandler")

    private let coordinator: IntentCoordinator

    init(coordinator: IntentCoordinator) {
        self.coordinator = coordinator
    }

}


// MARK: - Implementing INSetMessageAttributeIntentHandling

extension SetMessageAttributeIntentHandler: INSetMessageAttributeIntentHandling {

    func resolveAttribute(for intent: INSetMessageAttributeIntent) async -> INMessageAttributeResolutionResult {
        Self.logger.info("✅🏁 Resolving attribute for INSetMessageAttributeIntent")
        switch intent.attribute {
        case .read:
            Self.logger.info("✅ Attribute is .read, returning success")
            return .success(with: .read)
        case .unknown:
            Self.logger.info("✅ Attribute is .unknown, returning needsValue")
            return .needsValue()
        case .unread, .flagged, .unflagged, .played:
            Self.logger.error("✅ Unsupported attribute \(intent.attribute.rawValue), returning unsupported")
            return .unsupported()
        @unknown default:
            Self.logger.error("✅ Unsupported attribute \(intent.attribute.rawValue), returning unsupported")
            return .unsupported()
        }
    }


    func confirm(intent: INSetMessageAttributeIntent) async -> INSetMessageAttributeIntentResponse {
        Self.logger.info("✅🏁 Confirming INSetMessageAttributeIntent")

        guard !(intent.identifiers ?? []).isEmpty else {
            Self.logger.error("✅ No identifiers provided")
            return INSetMessageAttributeIntentResponse(code: .failure, userActivity: nil)
        }

        guard intent.attribute == .read else {
            Self.logger.error("✅ Unsupported attribute \(intent.attribute.rawValue) at confirm — resolveAttribute should have rejected it")
            return INSetMessageAttributeIntentResponse(code: .failureMessageAttributeNotSet, userActivity: nil)
        }

        Self.logger.info("✅ Confirmed, returning .ready")
        return INSetMessageAttributeIntentResponse(code: .ready, userActivity: nil)
    }


    func handle(intent: INSetMessageAttributeIntent) async -> INSetMessageAttributeIntentResponse {

        Self.logger.info("✅🏁 Handling INSetMessageAttributeIntent")

        guard intent.attribute == .read else {
            Self.logger.error("✅ Unsupported attribute \(intent.attribute.rawValue)")
            return INSetMessageAttributeIntentResponse(code: .failureMessageAttributeNotSet, userActivity: nil)
        }

        let identifiers = intent.identifiers ?? []
        guard !identifiers.isEmpty else {
            Self.logger.error("✅ No identifiers to process")
            return INSetMessageAttributeIntentResponse(code: .failureMessageNotFound, userActivity: nil)
        }

        Self.logger.info("✅ Marking \(identifiers.count) message(s) as read")

        var anyFailed = false
        var anyNotFound = false

        for identifier in identifiers {
            guard let messageAppIdentifier = ObvMessageAppIdentifier(identifier) else {
                Self.logger.error("✅ Could not decode ObvMessageAppIdentifier from '\(identifier, privacy: .private)'")
                anyNotFound = true
                continue
            }
            do {
                try await coordinator.markMessageAsRead(messageAppIdentifier: messageAppIdentifier)
            } catch {
                Self.logger.error("✅ Failed to mark message as read: \(error)")
                anyFailed = true
            }
        }

        // INSetMessageAttributeIntentResponseCode has no .partial, so any coordinator failure forces .failure
        // and any undecodable identifier forces .failureMessageNotFound. Log both signals unconditionally
        // before returning the response, otherwise the "failed + notFound" case silently drops the notFound info.
        if anyFailed {
            Self.logger.error("✅ One or more mark-as-read calls failed")
            return INSetMessageAttributeIntentResponse(code: .failure, userActivity: nil)
        }
        if anyNotFound {
            Self.logger.error("✅ One or more identifiers could not be decoded")
            return INSetMessageAttributeIntentResponse(code: .failureMessageNotFound, userActivity: nil)
        }
        Self.logger.info("✅ All messages marked as read successfully")
        return INSetMessageAttributeIntentResponse(code: .success, userActivity: nil)

    }

}

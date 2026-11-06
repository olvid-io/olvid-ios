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
import CoreData
import ObvSettings
import OlvidUtils
import ObvAppCoreConstants
import ObvUserNotificationsDatabase


/// Entry point of the Intents extension.
///
/// The system instantiates this class and calls `handler(for:)` for each incoming `INIntent`.
/// `IntentHandler` acts as a router: it creates one shared `IntentCoordinator` and returns the
/// appropriate handler object for each intent type.
///
/// **Supported intents**
/// - `INStartCallIntent` → ``StartCallIntentHandler``
///   Handles calls initiated from the system Phone app's Recents list. Declaring this intent in
///   `IntentsSupported` (Info.plist) ensures the app receives a modern `INStartCallIntent` via
///   `SceneDelegate.scene(_:continue:)` rather than the legacy `INStartAudioCallIntent`.
/// - `INSendMessageIntent` → ``SendMessageIntentHandler``
///   Handles send-message requests from Siri and system surfaces (e.g. CarPlay).
/// - `INSearchForMessagesIntent` → ``SearchForMessagesIntentHandler``
///   Handles message search requests from Siri.
/// - `INSetMessageAttributeIntent` → ``SetMessageAttributeIntentHandler``
///   Handles marking messages as read/unread via Siri.
class IntentHandler: INExtension {

    private let coordinator: IntentCoordinator
    private let runningLog: RunningLogError
    private var nseStackAvailable = false

    /// Consumes App-database writes made by other processes (mainly the main app marking messages as
    /// read) so the extension's long-lived Core Data coordinator doesn't keep serving a stale row
    /// cache. Built once, after `ObvStack` is ready, and retained for the extension's process
    /// lifetime so it keeps observing `NSPersistentStoreRemoteChange` across successive intents.
    private var appHistoryMerger: ObvPersistentHistoryMerger?

    /// Same idea for the user-notifications database: consumes NSE inserts and main-app drains so the
    /// extension doesn't re-surface pending messages that have since been delivered or drained. Built
    /// once the user-notifications stack is available, and retained for the process lifetime.
    private var nseHistoryMerger: ObvPersistentHistoryMerger?

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "IntentHandler")


    override init() {
        self.runningLog = .init()
        self.coordinator = .init(runningLog: runningLog)
        super.init()
    }


    override func handler(for intent: INIntent) -> Any {

        // Initialize the Core Data stack (this call does nothing if it was called before, e.g., to handle a previous intent)
        do {
            try ObvStack.initSharedInstance(
                transactionAuthor: ObvUICoreDataConstants.AppCategory.intentExtension.transactionAuthor,
                runningLog: runningLog,
                enableMigrations: false)
        } catch {
            Self.logger.fault("Failed to initialize the Core Data stack in the Intents extension — a migration may be required. The user must launch the main app first. Error: \(error.localizedDescription)")
            // Returning `self` is Apple's documented "I can't handle this intent" fallback: `IntentHandler` (an
            // `INExtension`) intentionally does not conform to any of the SiriKit handling protocols, so SiriKit
            // sees no handler and tells the user it can't help. SiriKit does not let `handler(for:)` return a
            // structured failure with a custom message — the only way to surface "launch the main app to finish
            // a migration" is the main app itself on next launch. Do not replace this with a typed failure handler.
            return self
        }

        // Build the App-DB persistent-history merger once, now that ObvStack is ready, and retain it
        // for the process lifetime so it keeps consuming `NSPersistentStoreRemoteChange` across
        // successive intents. Without this, the extension's long-lived coordinator serves a stale row
        // cache: messages the main app has marked as read still look `.new`, so a "read my messages"
        // request re-reads them. The merger also records this consumer's history cursor in the shared
        // token store, so the app's launch-time prune won't delete history this extension still needs.
        if appHistoryMerger == nil {
            let mergerTargetContext = ObvStack.shared.newBackgroundContext()
            mergerTargetContext.automaticallyMergesChangesFromParent = true
            appHistoryMerger = ObvPersistentHistoryMerger(
                backgroundContext: mergerTargetContext,
                logSubsystem: ObvAppCoreConstants.logSubsystem,
                localTransactionAuthor: ObvUICoreDataConstants.AppCategory.intentExtension.transactionAuthor,
                contextCreator: ObvStack.shared,
                persistentStoreCoordinator: ObvStack.shared.persistentStoreCoordinator,
                tokenStore: ObvStack.historyConsumerTokenStore)
        }

        // Best-effort initialization of the user-notification Core Data stack (idempotent). This stack
        // is owned by the Notification Service Extension; the Intents extension only reads it to surface
        // messages that haven't been drained into the app database yet. `deleteStoreOnFailure: false`
        // because we are a read-only consumer — wiping the store here would destroy pending-message
        // rows the NSE has written but the app drain hasn't picked up. On failure we log and continue:
        // intent handlers that consult this stack must check `nseStackAvailable` and fall back to the
        // app database only.
        if !nseStackAvailable {
            do {
                try ObvUserNotificationsStack.initSharedInstance(
                    transactionAuthor: ObvUICoreDataConstants.AppCategory.intentExtension.transactionAuthor,
                    runningLog: runningLog,
                    enableMigrations: false,
                    deleteStoreOnFailure: false)
                nseStackAvailable = true

                // Mirror the App-DB merger for the user-notifications store, so the extension sees
                // NSE inserts and main-app drains and doesn't re-surface already-delivered/drained
                // pending messages from a stale row cache.
                if nseHistoryMerger == nil {
                    let nseMergerTargetContext = ObvUserNotificationsStack.shared.newBackgroundContext()
                    nseMergerTargetContext.automaticallyMergesChangesFromParent = true
                    nseHistoryMerger = ObvPersistentHistoryMerger(
                        backgroundContext: nseMergerTargetContext,
                        logSubsystem: ObvAppCoreConstants.logSubsystem,
                        localTransactionAuthor: ObvUICoreDataConstants.AppCategory.intentExtension.transactionAuthor,
                        contextCreator: ObvUserNotificationsStack.shared,
                        persistentStoreCoordinator: ObvUserNotificationsStack.shared.persistentStoreCoordinator,
                        tokenStore: ObvUserNotificationsStack.historyConsumerTokenStore)
                }
            } catch {
                Self.logger.fault("Failed to initialize the user-notifications Core Data stack in the Intents extension. The intent will proceed without consulting that store. Error: \(error.localizedDescription)")
            }
        }

        // Best-effort engine warmup: start initializing the ObvEngine now so it is likely ready
        // by the time a handle(intent:) method calls sendMessage or markMessageAsRead.
        // This is not a correctness requirement — those methods call initialize() internally —
        // but it reduces latency for the user.
        Task { try? await coordinator.initialize() }

        switch intent {
        case is INStartCallIntent:
            return StartCallIntentHandler()
        case is INSendMessageIntent:
            return SendMessageIntentHandler(coordinator: coordinator)
        case is INSearchForMessagesIntent:
            return SearchForMessagesIntentHandler(nseStackAvailable: nseStackAvailable, appHistoryMerger: appHistoryMerger, nseHistoryMerger: nseHistoryMerger)
        case is INSetMessageAttributeIntent:
            return SetMessageAttributeIntentHandler(coordinator: coordinator)
        default:
            return self
        }
    }
}

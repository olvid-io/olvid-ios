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


protocol BackgroundTasksManagerDelegate: AnyObject {

    func syncAppDatabasesWithEngine(backgroundTasksManager: BackgroundTasksManager) async throws

    // For backups
    func newBackupsAreConfiguredAndCanBePerformed() async throws -> Bool
    func createAndUploadDeviceAndProfilesBackupDuringBackgroundProcessing() async throws
    
    // For Message Ids kept for later by the AppInboxService
    func syncMessageIdsKeptForLater(_ backgroundTasksManager: BackgroundTasksManager) async throws

    /// Drains the engine's inbox — lists, waits for the app to process what was listed, and sweeps the finished rows away — until there is nothing left,
    /// until `deadline`, or until `run` is asked to stop.
    ///
    /// Takes a deadline and a stop flag rather than the `BGProcessingTask` itself, deliberately: the settings row that triggers a drain on a simulator, where
    /// background tasks are never scheduled, has to drive exactly the same code. What is left in the background handler is the plumbing — the launch, the
    /// expiry, the completion, the rescheduling — and none of it can be tested where the drain can, so none of it does anything interesting.
    func drainEngineInbox(_ backgroundTasksManager: BackgroundTasksManager, deadline: Date, run: ObvInboxDrainInProgress) async -> ObvInboxDrainReport

}

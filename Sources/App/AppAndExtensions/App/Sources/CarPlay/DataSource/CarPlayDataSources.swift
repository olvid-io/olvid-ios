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
import OlvidUtils
import ObvTypes
import ObvUICoreData
import ObvCarPlay
import ObvSettings
import ObvAppCoreConstants

struct CarPlayDataSources {

    let carPlayDiscussionsListViewDataSource: any CarPlayDiscussionsListViewDataSource
    let backgroundContext: NSManagedObjectContext
    let remoteChangeObserver: ObvPersistentHistoryMerger

    @MainActor
    init(viewContext: NSManagedObjectContext,
         backgroundContext: NSManagedObjectContext) {

        backgroundContext.automaticallyMergesChangesFromParent = true

        self.backgroundContext = backgroundContext

        self.carPlayDiscussionsListViewDataSource = CarPlayDiscussionsListViewAppDataSource(
            viewContext: viewContext,
            backgroundContext: backgroundContext)

        self.remoteChangeObserver = ObvPersistentHistoryMerger(
            backgroundContext: backgroundContext,
            logSubsystem: ObvAppCoreConstants.logSubsystem,
            localTransactionAuthor: ObvUICoreDataConstants.AppCategory.mainApp.transactionAuthor,
            contextCreator: ObvStack.shared,
            persistentStoreCoordinator: ObvStack.shared.persistentStoreCoordinator,
            tokenStore: ObvStack.historyConsumerTokenStore)
    }

}

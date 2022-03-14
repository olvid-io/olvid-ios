/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import os.log
import OlvidUtils
import UIKit

final class UpdateDiscussionLocalConfigurationOperation: ContextualOperationWithSpecificReasonForCancel<UpdateDiscussionLocalConfigurationOperationReasonForCancel> {

    private let value: PersistedDiscussionLocalConfigurationValue
    private let input: Input

    fileprivate static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    enum Input {
        case configurationObjectID(TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>)
        case discussionObjectID(TypeSafeManagedObjectID<PersistedDiscussion>)
    }

    init(value: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) {
        self.value = value
        self.input = .configurationObjectID(localConfigurationObjectID)
        super.init()
    }

    init(value: PersistedDiscussionLocalConfigurationValue, persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) {
        self.value = value
        self.input = .discussionObjectID(persistedDiscussionObjectID)
        super.init()
    }

    override func main() {
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            do {
                let localConfiguration: PersistedDiscussionLocalConfiguration
                switch input {
                case .configurationObjectID(let objectID):
                    guard let _localConfiguration = try PersistedDiscussionLocalConfiguration.get(with: objectID, within: context) else {
                        return cancel(withReason: .couldNotFindDiscussionLocalConfiguration)
                    }
                    localConfiguration = _localConfiguration
                case .discussionObjectID(let objectID):
                    guard let discussion = try? PersistedDiscussion.get(objectID: objectID, within: context) else {
                        return cancel(withReason: .couldNotFindDiscussionLocalConfiguration)
                    }
                    localConfiguration = discussion.localConfiguration
                }
                
                localConfiguration.update(with: value)
                try context.save(logOnFailure: Self.log)
            
                ObvMessengerInternalNotification.discussionLocalConfigurationHasBeenUpdated(newValue: value, localConfigurationObjectID: localConfiguration.typedObjectID).postOnDispatchQueue()

                if case .muteNotificationsDuration = value,
                   let expiration = localConfiguration.currentMuteNotificationsEndDate {
                    ObvMessengerInternalNotification.newMuteExpiration(expirationDate: expiration).postOnDispatchQueue()
                }

            } catch(let error) {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
    }

}

enum UpdateDiscussionLocalConfigurationOperationReasonForCancel: LocalizedErrorWithLogType {

    case coreDataError(error: Error)
    case couldNotFindDiscussionLocalConfiguration

    var logType: OSLogType {
        switch self {
        case .coreDataError:
            return .fault
        case .couldNotFindDiscussionLocalConfiguration:
            return .error
        }
    }

    var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindDiscussionLocalConfiguration:
            return "Could not find local configuration in database"
        }
    }


}


extension AppDelegate {

    func scheduleBackgroundTaskForUpdatingBadge() {
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            let nextExpirationDate: Date?
            do {
                nextExpirationDate = try PersistedDiscussionLocalConfiguration.getEarliestMuteExpirationDate(laterThan: Date(), within: context)
            } catch {
                os_log("🤿 We do not schedule any background task for updating badge since there is no mute expiration left", log: log, type: .info)
                return
            }
            guard let nextExpirationDate = nextExpirationDate else { return}

            os_log("🤿 Submit new update badge operation", log: log, type: .info)
            let log = UpdateDiscussionLocalConfigurationOperation.log
            do {
                try BackgroundTasksManager.shared.submit(task: .updateBadge, earliestBeginDate: nextExpirationDate)
            } catch {
                guard ObvMessengerConstants.isRunningOnRealDevice else { assertionFailure("We should not be scheduling BG tasks on a simulator as they are unsuported"); return }
                os_log("🤿 Could not schedule next expiration: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
        }
    }


}

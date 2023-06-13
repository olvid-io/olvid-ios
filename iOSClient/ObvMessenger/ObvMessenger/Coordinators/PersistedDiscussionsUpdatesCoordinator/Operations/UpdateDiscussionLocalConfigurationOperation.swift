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
import ObvUICoreData

final class UpdateDiscussionLocalConfigurationOperation: ContextualOperationWithSpecificReasonForCancel<UpdateDiscussionLocalConfigurationOperationReasonForCancel> {

    private let value: PersistedDiscussionLocalConfigurationValue
    private let input: Input

    fileprivate static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: UpdateDiscussionLocalConfigurationOperation.self))

    enum Input {
        case configurationObjectID(TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>)
        case discussionPermanentID(ObvManagedObjectPermanentID<PersistedDiscussion>)
    }

    init(value: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) {
        self.value = value
        self.input = .configurationObjectID(localConfigurationObjectID)
        super.init()
    }

    init(value: PersistedDiscussionLocalConfigurationValue, discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) {
        self.value = value
        self.input = .discussionPermanentID(discussionPermanentID)
        super.init()
    }

    override func main() {
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            do {
                let localConfiguration: PersistedDiscussionLocalConfiguration
                switch input {
                case .configurationObjectID(let objectID):
                    guard let _localConfiguration = try PersistedDiscussionLocalConfiguration.get(with: objectID, within: obvContext.context) else {
                        return cancel(withReason: .couldNotFindDiscussionLocalConfiguration)
                    }
                    localConfiguration = _localConfiguration
                case .discussionPermanentID(let discussionPermanentID):
                    guard let discussion = try? PersistedDiscussion.getManagedObject(withPermanentID: discussionPermanentID, within: obvContext.context) else {
                        return cancel(withReason: .couldNotFindDiscussionLocalConfiguration)
                    }
                    localConfiguration = discussion.localConfiguration
                }

                localConfiguration.update(with: value)

                let value = self.value
                try obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return }
                    if case .muteNotificationsEndDate = value,
                       let expiration = localConfiguration.currentMuteNotificationsEndDate {
                        // This is catched by the MuteDiscussionManager in order to schedule a BG operation allowing to remove the mute
                        ObvMessengerInternalNotification.newMuteExpiration(expirationDate: expiration)
                            .postOnDispatchQueue()
                    }
                }

            } catch(let error) {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
    }

}

enum UpdateDiscussionLocalConfigurationOperationReasonForCancel: LocalizedErrorWithLogType {

    case contextIsNil
    case coreDataError(error: Error)
    case couldNotFindDiscussionLocalConfiguration

    var logType: OSLogType {
        switch self {
        case .coreDataError, .contextIsNil:
            return .fault
        case .couldNotFindDiscussionLocalConfiguration:
            return .error
        }
    }

    var errorDescription: String? {
        switch self {
        case .contextIsNil: return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindDiscussionLocalConfiguration:
            return "Could not find local configuration in database"
        }
    }


}

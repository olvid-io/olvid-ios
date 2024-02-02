/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvEngine
import OlvidUtils
import ObvUICoreData
import ObvSettings


final class DeleteAllJsonMessagesSavedByNotificationExtension: OperationWithSpecificReasonForCancel<DeleteAllJsonMessagesSavedByNotificationExtensionReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: DeleteAllJsonMessagesSavedByNotificationExtension.self))

    override func main() {
        
        guard let urls = try? FileManager.default.contentsOfDirectory(at: ObvUICoreDataConstants.ContainerURL.forMessagesDecryptedWithinNotificationExtension.url, includingPropertiesForKeys: nil) else {
            os_log("We could not list the serialized json files saved by the notification extension", log: log, type: .error)
            return cancel(withReason: .couldNotListContentsOfDirectory)
        }
        
        for url in urls {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                os_log("Failed to delete a notification content: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
        os_log("📮 Clean files saved by the notification extension", log: log, type: .info)

    }
    
}

enum DeleteAllJsonMessagesSavedByNotificationExtensionReasonForCancel: LocalizedErrorWithLogType {
    
    case couldNotListContentsOfDirectory
    
    var logType: OSLogType {
        switch self {
        case .couldNotListContentsOfDirectory:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .couldNotListContentsOfDirectory:
            return "Could not list content of directory"
        }
    }

}

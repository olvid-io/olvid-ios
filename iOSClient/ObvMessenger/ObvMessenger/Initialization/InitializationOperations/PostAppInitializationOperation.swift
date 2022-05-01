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
import os.log
import OlvidUtils
import ObvEngine

final class PostAppInitializationOperation: OperationWithSpecificReasonForCancel<PostAppInitializationOperationReasonForCancel> {

    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: PostAppInitializationOperation.self))
    let obvEngine: ObvEngine
    
    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        super.init()
    }
    
    
    override func main() {
        migrationToV0_9_4()
        ObvMessengerSettings.Alert.removeSecureCallsInBeta()
    }
    
    
    private func migrationToV0_9_4() {
        DispatchQueue(label: "migrationToV0_9_4").async { [weak self] in
            self?.downloadUserDataIfNecessary()
        }
    }

    
    private func downloadUserDataIfNecessary() {
        let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)!
        let key = ObvMessengerConstants.userDataHasBeenDownloadedAfterMigration

        guard !userDefaults.bool(forKey: key) else { return /* Already done the job */}

        do {
            try obvEngine.downloadAllUserData()
        } catch {
            os_log("Could not download user data: %{public}@", log: log, type: .info, error.localizedDescription)
            assertionFailure()
        }

        userDefaults.set(true, forKey: key) /* Mark as Done */
    }

}


enum PostAppInitializationOperationReasonForCancel: LocalizedErrorWithLogType {
    
    var logType: OSLogType {
        return .debug
    }
    
}

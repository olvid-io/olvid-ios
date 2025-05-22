/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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


extension PersistedGroupV2 {

    var backupItem: PersistedGroupV2BackupItem {
        let conf: PersistedDiscussionConfigurationBackupItem?
        if let discussion = self.discussion {
            let _conf = PersistedDiscussionConfigurationBackupItem(
                local: discussion.localConfiguration,
                shared: discussion.sharedConfiguration)
            conf = _conf.isEmpty ? nil : _conf
        } else {
            conf = nil
        }
        return PersistedGroupV2BackupItem(
            groupIdentifier: self.groupIdentifier,
            customName: self.customNameSanitized,
            discussionConfigurationBackupItem: conf)
    }

}


extension PersistedGroupV2BackupItem {

    func updateExistingInstance(_ groupV2: PersistedGroupV2) {

        if let localConfiguration = groupV2.discussion?.localConfiguration {
            self.discussionConfigurationBackupItem?.updateExistingInstance(localConfiguration)
        }
        if let sharedConfiguration = groupV2.discussion?.sharedConfiguration {
            self.discussionConfigurationBackupItem?.updateExistingInstance(sharedConfiguration)
        }

    }

}

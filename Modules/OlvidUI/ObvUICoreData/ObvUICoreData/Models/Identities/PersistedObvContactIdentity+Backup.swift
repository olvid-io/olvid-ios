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

// MARK: - For Backup purposes

extension PersistedObvContactIdentity {

    var backupItem: PersistedObvContactIdentityBackupItem {
        var conf: PersistedDiscussionConfigurationBackupItem? = nil
        if let oneToOneDiscussion = self.oneToOneDiscussion {
            conf = PersistedDiscussionConfigurationBackupItem(
                local: oneToOneDiscussion.localConfiguration,
                shared: oneToOneDiscussion.sharedConfiguration)
            if conf?.isEmpty == true {
                conf = nil
            }
        }
        return PersistedObvContactIdentityBackupItem(
            identity: self.identity,
            customDisplayName: self.customDisplayName,
            note: self.note,
            discussionConfigurationBackupItem: conf)
    }

}


extension PersistedObvContactIdentityBackupItem {

    func updateExistingInstance(_ contact: PersistedObvContactIdentity) {

        _ = try? contact.setCustomDisplayName(to: self.customDisplayName)
        _ = contact.setNote(to: self.note)

        if let oneToOneDiscussion = contact.oneToOneDiscussion {
            self.discussionConfigurationBackupItem?.updateExistingInstance(oneToOneDiscussion.localConfiguration)
            self.discussionConfigurationBackupItem?.updateExistingInstance(oneToOneDiscussion.sharedConfiguration)
        }

    }

}

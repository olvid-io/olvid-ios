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

// We store these structs within the user defaults database used by the notification extension to notify the coordinator (within the app) of the notifications that the extension scheduled.
struct UNNotificationRequestIdentifierWithDate {
    let requestIdentifier: String
    let date: Date
}


extension UserDefaults {
    
    func notificationRequestIdentifiersWithDates(forKey key: String) -> [UNNotificationRequestIdentifierWithDate]? {
        guard let dic = self.object(forKey: key) as? [String: Date] else { return nil }
        let notificationRequestsWithDates = dic.map { UNNotificationRequestIdentifierWithDate(requestIdentifier: $0.key, date: $0.value) }
        return notificationRequestsWithDates
    }
    
    func set(_ notificationRequestIdentifiersWithDates: [UNNotificationRequestIdentifierWithDate], forKey key: String) {
        var dic = [String: Date]()
        for identifierWithDate in notificationRequestIdentifiersWithDates {
            dic[identifierWithDate.requestIdentifier] = identifierWithDate.date
        }
        self.set(dic, forKey: key)
    }
    
}

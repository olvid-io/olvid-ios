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

public enum DataMigrationManagerNotification {

    case migrationManagerWillMigrateStore(observableProgress: Progress, storeName: String)
    
    private enum Name {

        case migrationManagerWillMigrateStore

        private var namePrefix: String { String(describing: DataMigrationManagerNotification.self) }

        private var nameSuffix: String { String(describing: self) }

        var name: NSNotification.Name {
            let name = [namePrefix, nameSuffix].joined(separator: ".")
            return NSNotification.Name(name)
        }

        static func forInternalNotification(_ notification: DataMigrationManagerNotification) -> NSNotification.Name {
            switch notification {
            case .migrationManagerWillMigrateStore: return Name.migrationManagerWillMigrateStore.name
            }
        }
    }
    
    private var userInfo: [AnyHashable: Any]? {
        let info: [AnyHashable: Any]?
        switch self {
        case .migrationManagerWillMigrateStore(observableProgress: let observableProgress, storeName: let storeName):
            info = [
                "observableProgress": observableProgress,
                "storeName": storeName,
            ]
        }
        return info
    }

    func post(object anObject: Any? = nil) {
        let name = Name.forInternalNotification(self)
        NotificationCenter.default.post(name: name, object: anObject, userInfo: userInfo)
    }

    func postOnDispatchQueue(object anObject: Any? = nil) {
        let name = Name.forInternalNotification(self)
        postOnDispatchQueue(withLabel: "Queue for posting \(name.rawValue) notification", object: anObject)
    }

    func postOnDispatchQueue(_ queue: DispatchQueue) {
        let name = Name.forInternalNotification(self)
        queue.async { [userInfo] in
            NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
        }
    }

    private func postOnDispatchQueue(withLabel label: String, object anObject: Any? = nil) {
        let name = Name.forInternalNotification(self)
        DispatchQueue(label: label).async { [userInfo] in
            NotificationCenter.default.post(name: name, object: anObject, userInfo: userInfo)
        }
    }

    public static func observeMigrationManagerWillMigrateStore(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Progress, String) -> Void) -> NSObjectProtocol {
        let name = Name.migrationManagerWillMigrateStore.name
        return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
            let observableProgress = notification.userInfo!["observableProgress"] as! Progress
            let storeName = notification.userInfo!["storeName"] as! String
            block(observableProgress, storeName)
        }
    }

}

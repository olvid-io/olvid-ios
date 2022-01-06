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
import ObvTypes
import ObvEncoder
import ObvCrypto
import OlvidUtils
import os.log

@objc(PersistedEngineDialog)
final class PersistedEngineDialog: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "PersistedEngineDialog"
    private static let uuidKey = "uuid"
    private static let encodedObvDialogKey = "encodedObvDialog"
    private static let resendCounterKey = "resendCounter"
    
    // MARK: Attributes
    
    @NSManaged private(set) var uuid: UUID
    private var obvDialog: ObvDialog {
        get {
            let encodedValue = kvoSafePrimitiveValue(forKey: PersistedEngineDialog.encodedObvDialogKey) as! ObvEncoded
            return ObvDialog(encodedValue)!
        }
        set {
            kvoSafeSetPrimitiveValue(newValue.encode(), forKey: PersistedEngineDialog.encodedObvDialogKey)
        }
    }
    @NSManaged private(set) var resendCounter: Int
    
    // MARK: Other variables
    
    var obvContext: ObvContext?
    weak var appNotificationCenter: NotificationCenter?
    private var notificationRelatedChanges: NotificationRelatedChanges = []

    // MARK: - Initializer
    
    convenience init?(with obvDialog: ObvDialog, appNotificationCenter: NotificationCenter, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedEngineDialog.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.uuid = obvDialog.uuid
        self.obvDialog = obvDialog
        self.resendCounter = 0
        self.appNotificationCenter = appNotificationCenter
    }

}


// MARK: - Other methods

extension PersistedEngineDialog {
    
    func update(with obvDialog: ObvDialog) throws {
        guard self.uuid == obvDialog.uuid else { throw NSError() }
        self.obvDialog = obvDialog
        notificationRelatedChanges.insert(.obvDialog)
    }
    
    // MARK: - Resending notification
    
    func resend() {
        resendCounter += 1
        notificationRelatedChanges.insert(.resendCounter)
    }
    
}

// MARK: Convenience DB getters
extension PersistedEngineDialog {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedEngineDialog> {
        return NSFetchRequest<PersistedEngineDialog>(entityName: PersistedEngineDialog.entityName)
    }
    
    class func getAll(appNotificationCenter: NotificationCenter, within obvContext: ObvContext) -> Set<PersistedEngineDialog>? {
        let request: NSFetchRequest<PersistedEngineDialog> = PersistedEngineDialog.fetchRequest()
        guard let values = try? obvContext.fetch(request) else { return nil }
        return Set(values.map { $0.appNotificationCenter = appNotificationCenter; return $0 })
    }

    class func get(uid: UUID, appNotificationCenter: NotificationCenter, within obvContext: ObvContext) -> PersistedEngineDialog? {
        let request: NSFetchRequest<PersistedEngineDialog> = PersistedEngineDialog.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", uuidKey, uid as CVarArg)
        let item = (try? obvContext.fetch(request))?.first
        item?.appNotificationCenter = appNotificationCenter
        return item
    }
 
    static func deletePersistedDialog(uid: UUID, appNotificationCenter: NotificationCenter, within obvContext: ObvContext) {
        if let dialog = get(uid: uid, appNotificationCenter: appNotificationCenter, within: obvContext) {
            obvContext.delete(dialog)
        }
    }
}

// MARK: - Sending notifications to the App
extension PersistedEngineDialog {
    
    private struct NotificationRelatedChanges: OptionSet {
        let rawValue: UInt8
        static let resendCounter = NotificationRelatedChanges(rawValue: 1 << 0)
        static let obvDialog = NotificationRelatedChanges(rawValue: 1 << 1)
    }

    override func didSave() {
        super.didSave()
        
        guard let appNotificationCenter = self.appNotificationCenter else {
            assertionFailure("The app notification center is not set")
            return
        }
        
        if isDeleted {
            let userInfo = [ObvEngineNotification.APersistedDialogWasDeleted.Key.uuid: uuid]
            let notification = Notification(name: ObvEngineNotification.APersistedDialogWasDeleted.name, userInfo: userInfo)
            appNotificationCenter.post(notification)
        }

        if isInserted || notificationRelatedChanges.contains(.resendCounter) || notificationRelatedChanges.contains(.obvDialog) {
            // We do not export the uuid since it is already included in the obvDialog struct
            let userInfo = [ObvEngineNotification.NewUserDialogToPresent.Key.obvDialog: obvDialog]
            let notification = Notification(name: ObvEngineNotification.NewUserDialogToPresent.name, userInfo: userInfo)
            appNotificationCenter.post(notification)
        }
        
    }
}

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
    
    private static func makeError(message: String) -> Error {
        NSError(domain: "PersistedEngineDialog", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }

    // MARK: Attributes
    
    @NSManaged private(set) var uuid: UUID
    private(set) var obvDialog: ObvDialog? {
        get {
            guard let encodedValue = kvoSafePrimitiveValue(forKey: PersistedEngineDialog.encodedObvDialogKey) as? ObvEncoded else { return nil }
            return ObvDialog(encodedValue)
        }
        set {
            guard let newValue = newValue else { assertionFailure(); return }
            guard let encodedValue = try? newValue.obvEncode() else { assertionFailure(); return }
            kvoSafeSetPrimitiveValue(encodedValue, forKey: PersistedEngineDialog.encodedObvDialogKey)
        }
    }
    /// Returns `true` iff the serialized dialog cannot be deserialized, meaning that the type does not exist anymore in the current app version.
    /// This happened, e.g., when removing the dialog message telling the user that she accepted a group invite.
    var dialogIsObsolete: Bool {
        self.obvDialog == nil
    }
    
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
        self.appNotificationCenter = appNotificationCenter
    }

    func delete() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw Self.makeError(message: "Could not find context")}
        self.uuidOnDeletion = self.uuid
        self.ownedCryptoIdOnDeletion = self.obvDialog?.ownedCryptoId
        context.delete(self)
    }
    
    private var uuidOnDeletion: UUID?
    private var ownedCryptoIdOnDeletion: ObvCryptoId?
    
}


// MARK: - Other methods

extension PersistedEngineDialog {
    
    func update(with obvDialog: ObvDialog) throws {
        guard self.uuid == obvDialog.uuid else {
            throw Self.makeError(message: "Could not get obvDialog's uuid")
        }
        self.obvDialog = obvDialog
        notificationRelatedChanges.insert(.obvDialog)
    }
    
}

// MARK: Convenience DB getters
extension PersistedEngineDialog {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedEngineDialog> {
        return NSFetchRequest<PersistedEngineDialog>(entityName: PersistedEngineDialog.entityName)
    }
    
    class func getAll(appNotificationCenter: NotificationCenter, within obvContext: ObvContext) throws -> Set<PersistedEngineDialog> {
        let request: NSFetchRequest<PersistedEngineDialog> = PersistedEngineDialog.fetchRequest()
        let values = try obvContext.fetch(request)
        return Set(values.map { $0.appNotificationCenter = appNotificationCenter; return $0 })
    }

    class func get(uid: UUID, appNotificationCenter: NotificationCenter, within obvContext: ObvContext) throws -> PersistedEngineDialog? {
        let request: NSFetchRequest<PersistedEngineDialog> = PersistedEngineDialog.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", uuidKey, uid as CVarArg)
        let item = (try obvContext.fetch(request)).first
        item?.appNotificationCenter = appNotificationCenter
        return item
    }
 
    static func deletePersistedDialog(uid: UUID, appNotificationCenter: NotificationCenter, within obvContext: ObvContext) throws {
        if let dialog = try get(uid: uid, appNotificationCenter: appNotificationCenter, within: obvContext) {
            try dialog.delete()
        }
    }
}

// MARK: - Sending notifications to the App
extension PersistedEngineDialog {
    
    private struct NotificationRelatedChanges: OptionSet {
        let rawValue: UInt8
        static let obvDialog = NotificationRelatedChanges(rawValue: 1 << 1)
    }
    
    override func willSave() {
        super.willSave()
        
        if isDeleted {
            
            guard let managedObjectContext else { assertionFailure(); return }
            guard managedObjectContext.concurrencyType != .mainQueueConcurrencyType else { assertionFailure(); return }

            if self.uuidOnDeletion == nil {
                self.uuidOnDeletion = self.uuid
            }
            if self.ownedCryptoIdOnDeletion == nil {
                self.ownedCryptoIdOnDeletion = self.obvDialog?.ownedCryptoId
            }

        }
        
    }

    override func didSave() {
        super.didSave()
        
        guard let appNotificationCenter = self.appNotificationCenter else {
            assertionFailure("The app notification center is not set")
            return
        }
        
        if isDeleted, let uuidOnDeletion, let ownedCryptoIdOnDeletion {
            ObvEngineNotificationNew.aPersistedDialogWasDeleted(ownedCryptoId: ownedCryptoIdOnDeletion, uuid: uuidOnDeletion)
                .postOnBackgroundQueue(within: appNotificationCenter)
        }

        if isInserted || notificationRelatedChanges.contains(.obvDialog) {
            // We do not export the uuid since it is already included in the obvDialog struct
            guard let obvDialog = self.obvDialog else { assertionFailure(); return }
            ObvEngineNotificationNew.newUserDialogToPresent(obvDialog: obvDialog)
                .postOnBackgroundQueue(within: appNotificationCenter)
        }
        
    }
}

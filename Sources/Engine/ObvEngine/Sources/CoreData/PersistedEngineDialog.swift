/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OSLog
import CoreData
import ObvTypes
import ObvEncoder
import ObvCrypto
import OlvidUtils

@objc(PersistedEngineDialog)
final class PersistedEngineDialog: NSManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "PersistedEngineDialog"
    private static let uuidKey = "uuid"
    
    private static func makeError(message: String) -> Error {
        NSError(domain: "PersistedEngineDialog", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }

    // MARK: Attributes
    
    @NSManaged private(set) var uuid: UUID
    @NSManaged private var rawEncodedObvDialog: Data? // Non-optional in the model, raw value of an encoded ObvDialog
    
    /// Expected to be non-nil, except when a dialog is obsolote (see below).
    var obvDialog: ObvDialog? {
        get throws(ObvError) {
            guard let rawEncodedObvDialog else { assertionFailure(); throw .unexpectedNilValue }
            guard let encodedValue = ObvEncoded(withRawData: rawEncodedObvDialog) else { assertionFailure(); throw .couldNotParseValue }
            return ObvDialog(encodedValue)
        }
    }
    
    /// Returns `true` iff the serialized dialog cannot be deserialized, meaning that the type does not exist anymore in the current app version.
    /// This happened, e.g., when removing the dialog message telling the user that she accepted a group invite.
    var dialogIsObsolete: Bool {
        get throws(ObvError) {
            try self.obvDialog == nil
        }
    }
    
    // MARK: Other variables
    
    weak var appNotificationCenter: NotificationCenter?
    private var notificationRelatedChanges: NotificationRelatedChanges = []

    // MARK: - Initializer
    
    convenience init(with obvDialog: ObvDialog, appNotificationCenter: NotificationCenter, within context: NSManagedObjectContext) throws {
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedEngineDialog.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.uuid = obvDialog.uuid
        self.rawEncodedObvDialog = try obvDialog.obvEncode().rawData
        self.appNotificationCenter = appNotificationCenter
    }

    func delete() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw Self.makeError(message: "Could not find context")}
        self.uuidOnDeletion = self.uuid
        self.ownedCryptoIdOnDeletion = try? self.obvDialog?.ownedCryptoId
        context.delete(self)
    }
    
    private var uuidOnDeletion: UUID?
    private var ownedCryptoIdOnDeletion: ObvCryptoId?
    
    enum ObvError: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }
    
}


// MARK: - Other methods

extension PersistedEngineDialog {
    
    func update(with obvDialog: ObvDialog) throws {
        guard self.uuid == obvDialog.uuid else {
            throw Self.makeError(message: "Could not get obvDialog's uuid")
        }
        self.rawEncodedObvDialog = try obvDialog.obvEncode().rawData
        notificationRelatedChanges.insert(.obvDialog)
    }
    
}

// MARK: Convenience DB getters
extension PersistedEngineDialog {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedEngineDialog> {
        return NSFetchRequest<PersistedEngineDialog>(entityName: PersistedEngineDialog.entityName)
    }
    
    class func getAll(appNotificationCenter: NotificationCenter, within context: NSManagedObjectContext) throws -> Set<PersistedEngineDialog> {
        let request: NSFetchRequest<PersistedEngineDialog> = PersistedEngineDialog.fetchRequest()
        let values = try context.fetch(request)
        return Set(values.map { $0.appNotificationCenter = appNotificationCenter; return $0 })
    }

    class func get(uid: UUID, appNotificationCenter: NotificationCenter, within context: NSManagedObjectContext) throws -> PersistedEngineDialog? {
        let request: NSFetchRequest<PersistedEngineDialog> = PersistedEngineDialog.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", uuidKey, uid as CVarArg)
        let item = try context.fetch(request).first
        item?.appNotificationCenter = appNotificationCenter
        return item
    }
 
    static func deletePersistedDialog(uid: UUID, appNotificationCenter: NotificationCenter, within context: NSManagedObjectContext) throws {
        if let dialog = try get(uid: uid, appNotificationCenter: appNotificationCenter, within: context) {
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
                self.ownedCryptoIdOnDeletion = try? self.obvDialog?.ownedCryptoId
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
            guard let obvDialog = try? self.obvDialog else { assertionFailure(); return }
            ObvEngineNotificationNew.newUserDialogToPresent(obvDialog: obvDialog)
                .postOnBackgroundQueue(within: appNotificationCenter)
        }
        
    }
}

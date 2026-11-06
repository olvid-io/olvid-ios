/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

public extension NSManagedObjectContext {
    
    func save(logOnFailure log: OSLog) throws {
        var saveError: Error? = nil
        if self.hasChanges {
            do {
                try self.save()
            } catch let error {
                os_log("Could not save context with name %{public}@ and transaction author %{public}@", log: log, type: .fault, error.localizedDescription, self.name ?? "None", self.transactionAuthor ?? "None")
                os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                os_log("Could not save context: %{public}@", log: log, type: .fault, (error as NSError).userInfo)
                
                tryToLogCoreDataErrorDescription(error: error, log: log)
                logsWhatTheConflictActuallyIs(error: error, log: log)
                saveError = error
                
                debugPrint("--------------------------------------------------------------------------")
                debugPrint("context: \(self.debugDescription)")
                debugPrint("context.name: \(self.name ?? "None")")
                debugPrint("context.mergePolicy: \(String(describing: (self.mergePolicy as? NSMergePolicy)?.mergeType.debugDescription))")
                debugPrint("USER INFO", (error as NSError).userInfo)
                debugPrint("--------------------------------------------------------------------------")
            }
        }
        if let error = saveError {
            throw error
        }
    }
    
    /// **What a merge conflict actually is, in two lines instead of two rows** — added 2026-08-27, after one cost an afternoon.
    ///
    /// Core Data's `userInfo` is dumped above and it is complete, which is exactly the problem: for each conflict it prints the **whole** cached row and the
    /// **whole** store row, thirty-odd attributes each, and the diagnosis is the three that differ. Reading a real one by hand — a send that failed because a
    /// received message had been marked read underneath it — the work was entirely in diffing two walls of text and then establishing that the conflicting object
    /// was not one the failing save had touched at all.
    ///
    /// So this says both of those outright:
    ///
    /// - **which attributes differ**, and nothing else, between what this context had cached and what the store now holds;
    /// - **whether this context changed that object at all** — because a conflict on an object merely *faulted in* as a side effect of bookkeeping means the save
    ///   was lost to somebody else's edit and the answer is a retry or a merge policy, where a conflict on an object this save *modified* means two pieces of code
    ///   are editing one thing and the answer is elsewhere entirely. Those are different bugs and they look identical in the dump above.
    ///
    /// It also says what the save was *for*, which the dump never mentions: a conflict is only interesting beside the change it prevented.
    ///
    /// **Values are printed for numbers, dates and nulls, and withheld for strings and data.** That is not squeamishness: this is a messenger whose whole point is
    /// that message bodies are nobody else's business, and the attribute that provokes one of these is virtually always a status, a flag or a timestamp. The dump
    /// above is more leaky than this and predates it; that is a reason to fix that one day, not to copy it.
    private func logsWhatTheConflictActuallyIs(error: Error, log: OSLog) {

        let conflicts = ((error as NSError).userInfo[NSPersistentStoreSaveConflictsErrorKey] as? [NSMergeConflict]) ?? []
        guard !conflicts.isEmpty else { return }

        // What this save was for. Small sets in practice, and the one thing the dump never says.
        os_log("save conflict | this save was for | inserted: %{public}@ | updated: %{public}@ | deleted: %{public}@",
               log: log, type: .fault,
               Self.named(insertedObjects), Self.named(updatedObjects), Self.named(deletedObjects))

        for conflict in conflicts {

            let object = conflict.sourceObject
            let whatWeDidToIt: String
            if insertedObjects.contains(object) { whatWeDidToIt = "INSERTED HERE" }
            else if deletedObjects.contains(object) { whatWeDidToIt = "DELETED HERE" }
            else if updatedObjects.contains(object) { whatWeDidToIt = "UPDATED HERE — two writers of one object" }
            else { whatWeDidToIt = "not changed here, merely registered — this save was lost to somebody else's edit" }

            os_log("save conflict | %{public}@ v%{public}d→v%{public}d | %{public}@ | differs: %{public}@",
                   log: log, type: .fault,
                   Self.name(of: object), conflict.oldVersionNumber, conflict.newVersionNumber, whatWeDidToIt,
                   Self.whatDiffers(between: conflict.cachedSnapshot, and: conflict.persistedSnapshot))

        }

    }


    /// The keys whose values differ, with the values themselves where printing one gives nothing away.
    private static func whatDiffers(between cached: [String: Any]?, and persisted: [String: Any]?) -> String {
        guard let cached, let persisted else { return "no snapshots to compare — the conflict carries none, which happens for a deletion" }
        let keys = Set(cached.keys).union(persisted.keys).sorted()
        let differences: [String] = keys.compactMap { key in
            let before = cached[key], after = persisted[key]
            guard !Self.theSame(before, after) else { return nil }
            return "\(key) \(Self.shown(before))→\(Self.shown(after))"
        }
        return differences.isEmpty ? "nothing — the snapshots agree, so the version alone moved" : differences.joined(separator: ", ")
    }


    /// `NSObject`'s own equality, which every attribute value in a snapshot has, and *both nil* counting as the same.
    private static func theSame(_ one: Any?, _ other: Any?) -> Bool {
        switch (one as? NSObject, other as? NSObject) {
        case (nil, nil): return true
        case (let one?, let other?): return one.isEqual(other)
        default: return false
        }
    }


    /// A value, or a description of it where the value itself is nobody's business — see ``logsWhatTheConflictActuallyIs(error:log:)``.
    private static func shown(_ value: Any?) -> String {
        switch value {
        case .none: return "nil"
        case let text as String: return "<string, \(text.count) characters>"
        case let data as Data: return "<data, \(data.count) bytes>"
        case let object as NSManagedObject: return name(of: object)
        case let some?: return String(describing: some)
        }
    }


    private static func name(of object: NSManagedObject) -> String {
        "\(object.entity.name ?? "?")/\(object.objectID.uriRepresentation().lastPathComponent)"
    }


    private static func named(_ objects: Set<NSManagedObject>) -> String {
        objects.isEmpty ? "none" : objects.map(name(of:)).sorted().joined(separator: ", ")
    }


    // See CoreDataErrors.h
    private func tryToLogCoreDataErrorDescription(error: Error, log: OSLog) {
        guard let errorCode = (error as? CocoaError)?.errorCode else { return }
        let errorName: String
        switch errorCode {
        case NSManagedObjectValidationError:
            errorName = "NSManagedObjectValidationError - generic validation error"
        case NSManagedObjectConstraintValidationError:
            errorName = "NSManagedObjectConstraintValidationError - one or more uniqueness constraints were violated"
        case NSValidationMultipleErrorsError:
            errorName = "NSValidationMultipleErrorsError - generic message for error containing multiple validation errors"
        case NSValidationMissingMandatoryPropertyError:
            errorName = "NSValidationMissingMandatoryPropertyError - non-optional property with a nil value"
        case NSValidationRelationshipLacksMinimumCountError:
            errorName = "NSValidationRelationshipLacksMinimumCountError - to-many relationship with too few destination objects"
        case NSValidationRelationshipExceedsMaximumCountError:
            errorName = "NSValidationRelationshipExceedsMaximumCountError - bounded, to-many relationship with too many destination objects"
        case NSValidationRelationshipDeniedDeleteError:
            errorName = "NSValidationRelationshipDeniedDeleteError - some relationship with NSDeleteRuleDeny is non-empty"
        case NSValidationNumberTooLargeError:
            errorName = "NSValidationNumberTooLargeError - some numerical value is too large"
        case NSValidationNumberTooSmallError:
            errorName = "NSValidationNumberTooSmallError - some numerical value is too small"
        case NSValidationDateTooLateError:
            errorName = "NSValidationDateTooLateError - some date value is too late"
        case NSValidationDateTooSoonError:
            errorName = "NSValidationDateTooSoonError - some date value is too soon"
        case NSValidationInvalidDateError:
            errorName = "NSValidationInvalidDateError - some date value fails to match date pattern"
        case NSValidationStringTooLongError:
            errorName = "NSValidationStringTooLongError - some string value is too long"
        case NSValidationStringTooShortError:
            errorName = "NSValidationStringTooShortError - some string value is too short"
        case NSValidationStringPatternMatchingError:
            errorName = "NSValidationStringPatternMatchingError - some string value fails to match some pattern"
        case NSValidationInvalidURIError:
            errorName = "NSValidationInvalidURIError - some URI value cannot be represented as a string"
        case NSManagedObjectContextLockingError:
            errorName = "NSManagedObjectContextLockingError - can't acquire a lock in a managed object context"
        case NSPersistentStoreCoordinatorLockingError:
            errorName = "NSPersistentStoreCoordinatorLockingError - can't acquire a lock in a persistent store coordinator"
        case NSManagedObjectReferentialIntegrityError:
            errorName = "NSManagedObjectReferentialIntegrityError - attempt to fire a fault pointing to an object that does not exist (we can see the store, we can't see the object)"
        case NSManagedObjectExternalRelationshipError:
            errorName = "NSManagedObjectExternalRelationshipError - an object being saved has a relationship containing an object from another store"
        case NSManagedObjectMergeError:
            errorName = "NSManagedObjectMergeError - merge policy failed - unable to complete merging"
        case NSManagedObjectConstraintMergeError:
            errorName = "NSManagedObjectConstraintMergeError - merge policy failed - unable to complete merging due to multiple conflicting constraint violations"
        case NSPersistentStoreInvalidTypeError:
            errorName = "NSPersistentStoreInvalidTypeError - unknown persistent store type/format/version"
        case NSPersistentStoreTypeMismatchError:
            errorName = "NSPersistentStoreTypeMismatchError - returned by persistent store coordinator if a store is accessed that does not match the specified type"
        case NSPersistentStoreIncompatibleSchemaError:
            errorName = "NSPersistentStoreIncompatibleSchemaError - store returned an error for save operation (database level errors ie missing table, no permissions)"
        case NSPersistentStoreSaveError:
            errorName = "NSPersistentStoreSaveError - unclassified save error - something we depend on returned an error"
        case NSPersistentStoreIncompleteSaveError:
            errorName = "NSPersistentStoreIncompleteSaveError - one or more of the stores returned an error during save (stores/objects that failed will be in userInfo)"
        case NSPersistentStoreSaveConflictsError:
            errorName = "NSPersistentStoreSaveConflictsError - an unresolved merge conflict was encountered during a save.  userInfo has NSPersistentStoreSaveConflictsErrorKey"
        case NSCoreDataError:
            errorName = "NSCoreDataError - general Core Data error"
        case NSPersistentStoreOperationError:
            errorName = "NSPersistentStoreOperationError - the persistent store operation failed"
        case NSPersistentStoreOpenError:
            errorName = "NSPersistentStoreOpenError - an error occurred while attempting to open the persistent store"
        case NSPersistentStoreTimeoutError:
            errorName = "NSPersistentStoreTimeoutError - failed to connect to the persistent store within the specified timeout (see NSPersistentStoreTimeoutOption)"
        case NSPersistentStoreUnsupportedRequestTypeError:
            errorName = "NSPersistentStoreUnsupportedRequestTypeError - an NSPersistentStore subclass was passed an NSPersistentStoreRequest that it did not understand"
        case NSPersistentStoreIncompatibleVersionHashError:
            errorName = "NSPersistentStoreIncompatibleVersionHashError - entity version hashes incompatible with data model"
        case NSMigrationError:
            errorName = "NSMigrationError - general migration error"
        case NSMigrationConstraintViolationError:
            errorName = "SMigrationConstraintViolationError - migration failed due to a violated uniqueness constraint"
        case NSMigrationCancelledError:
            errorName = "SMigrationCancelledError - migration failed due to manual cancellation"
        case NSMigrationMissingSourceModelError:
            errorName = "SMigrationMissingSourceModelError - migration failed due to missing source data model"
        case NSMigrationMissingMappingModelError:
            errorName = "SMigrationMissingMappingModelError - migration failed due to missing mapping model"
        case NSMigrationManagerSourceStoreError:
            errorName = "SMigrationManagerSourceStoreError - migration failed due to a problem with the source data store"
        case NSMigrationManagerDestinationStoreError:
            errorName = "SMigrationManagerDestinationStoreError - migration failed due to a problem with the destination data store"
        case NSEntityMigrationPolicyError:
            errorName = "SEntityMigrationPolicyError - migration failed during processing of the entity migration policy"
        case NSSQLiteError:
            errorName = "SSQLiteError - general SQLite error"
        case NSInferredMappingModelError:
            errorName = "SInferredMappingModelError - inferred mapping model creation error"
        case NSExternalRecordImportError:
            errorName = "SExternalRecordImportError - general error encountered while importing external records"
        case NSPersistentHistoryTokenExpiredError:
            errorName = "SPersistentHistoryTokenExpiredError - The history token passed to NSPersistentChangeRequest was invalid"
        default:
            errorName = "Could not determine the error name of error code \(errorCode)"
        }
        os_log("%@", log: log, type: .fault, errorName)
        
    }
    
}


fileprivate extension NSMergePolicyType {
    
    var debugDescription: String {
        switch self {
        case .errorMergePolicyType: return "errorMergePolicyType"
        case .mergeByPropertyStoreTrumpMergePolicyType: return "mergeByPropertyStoreTrumpMergePolicyType"
        case .mergeByPropertyObjectTrumpMergePolicyType: return "mergeByPropertyObjectTrumpMergePolicyType"
        case .overwriteMergePolicyType: return "overwriteMergePolicyType"
        case .rollbackMergePolicyType: return "rollbackMergePolicyType"
        @unknown default:
            assert(false)
            return ""
        }
    }

}


public extension Error {

    /// Whether Core Data refused a save because somebody else moved a row underneath it — added 2026-08-27.
    ///
    /// Lives beside ``NSManagedObjectContext/logsWhatTheConflictActuallyIs(error:log:)``, which reads the very same key, so that
    /// `NSPersistentStoreSaveConflictsErrorKey` is named in one file rather than in two. That one says *what* the conflict is; this one says
    /// *whether it is one*.
    ///
    /// **This is worth asking because the app inherits `NSErrorMergePolicy`.** Nothing in the app layer sets a merge policy — only three
    /// deliberate sites in the engine do — so any conflict fails the whole save, **including a conflict on an object the save never touched**.
    /// The app's own writers cannot collide with one another, `AppCoordinatorsQueue` being serial and every composition taking a fresh
    /// context; what can collide is **another process** on the same store. The one found is Siri's `INSetMessageAttributeIntent`, whose only
    /// supported attribute is `.read`: `IntentCoordinator.handleMarkAsReadForMessageInAppDatabase` runs the very operation the app runs,
    /// against `ObvStack.shared`, in the intents extension. Announce Notifications reaches it without Siri being addressed at all, which is why
    /// it lands while somebody is typing.
    ///
    /// A caller that can safely re-run its work should therefore re-run it rather than treat this as a failure. A caller that cannot must not,
    /// which is why this is a question and not a retry.
    var isASaveConflict: Bool {
        guard let conflicts = (self as NSError).userInfo[NSPersistentStoreSaveConflictsErrorKey] as? [NSMergeConflict] else { return false }
        return !conflicts.isEmpty
    }

}

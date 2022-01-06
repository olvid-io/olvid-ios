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

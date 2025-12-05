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
import CoreData
import OSLog
import ObvAppCoreConstants


final class PersistedObvContactIdentityToPersistedObvContactIdentityV77ToV78: NSEntityMigrationPolicy {

    private static let errorDomain = "MessengerMigrationV77ToV78"
    private static let debugPrintPrefix = "[\(errorDomain)][PersistedObvContactIdentityToPersistedObvContactIdentityV77ToV78]"

    let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "PersistedObvContactIdentityToPersistedObvContactIdentityV77ToV78")
            
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        do {
            
            debugPrint("\(Self.debugPrintPrefix) createDestinationInstances starts")
            defer {
                debugPrint("\(Self.debugPrintPrefix) createDestinationInstances ends")
            }
            
            let dInstance = try initializeDestinationInstance(forEntityName: "PersistedObvContactIdentity",
                                                              forSource: sInstance,
                                                              in: mapping,
                                                              manager: manager,
                                                              errorDomain: Self.errorDomain)
            defer {
                manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
            }
            
            // We compute and set the new `sortInitial` attribute based on the existing `sortDisplayName` attributed
            
            guard let sortDisplayName = sInstance.value(forKey: "sortDisplayName") as? String else {
                assertionFailure()
                throw ObvError.couldNotGetSortDisplayName
            }
            
            let newSortInitial = Self.computeSortInitialFromSortDisplayName(sortDisplayName)
            
            dInstance.setValue(newSortInitial, forKey: "sortInitial")

        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
    
    private static func computeSortInitialFromSortDisplayName(_ newSortDisplayName: String) -> String {
        let listOfAcceptableNameInitial: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ#").map(Character.init)
        let firstCharacter = String(newSortDisplayName.first ?? "#").uppercased()
        guard firstCharacter.count == 1 else {
            assertionFailure()
            return "#"
        }
        if listOfAcceptableNameInitial.contains(firstCharacter) {
            return firstCharacter
        } else {
            return "#"
        }
    }

    
    enum ObvError: Error {
        case couldNotGetSortDisplayName
    }

}



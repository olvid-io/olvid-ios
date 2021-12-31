/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

fileprivate let errorDomain = "MessengerMigrationV28ToV29"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedDiscussionLocalConfigurationToPersistedDiscussionLocalConfigurationV28ToV29]"


final class PersistedDiscussionLocalConfigurationToPersistedDiscussionLocalConfigurationV28ToV29: NSEntityMigrationPolicy {

    /**
     Documentation for next migrations:

     We can call custom functions directly from mapping model with the following syntax

     FUNCTION($entityPolicy, "optionalNSNumberFromBoolSetting:" , $source.NAME_OF_FIELD)

     - entityPolicy corresponds to the NSEntityMigrationPolicy subclass here it's PersistedDiscussionLocalConfigurationToPersistedDiscussionLocalConfigurationV28ToV29 (this class)
     That is declared in custom policy field (don't forget "ObvMessenger." prefix)

     - optionalNSNumberFromBoolSetting is the name that corresponds to the declaration above, to verify the name it you can call:
     print(#selector(ObvMessenger.PersistedDiscussionLocalConfigurationToPersistedDiscussionLocalConfigurationV28ToV29.optionalNSNumberFrom(boolSetting:)))
     that returns "optionalNSNumberFromBoolSetting:" (please don't forget the colon)

     - $source.NAME_OF_FIELD is the field value that you want to give to this function

     - @objc is mandatory

     More information on this blog : https://wojciechkulik.pl/ios/getting-started-with-core-data-using-swift-4
    */
    @objc func optionalNSNumberFrom(boolSetting: NSNumber) -> NSNumber? {
        /// REMARK the source core data model type is Bool, but if we let Bool as argument the function is always called with false, but it's work well with NSNumber (core data bug ?)
        debugPrint("\(debugPrintPrefix) optionalNSNumberFrom called")
        /// The migration is done for autoRead and retainWipedOutboundMessages fields, the global discussion default value for these values is false for both.
        if boolSetting == 1 {
            /// If it's true, we keep the local setting value
            return boolSetting
        } else {
            /// If it's false, we consider that the user has never change this setting, so we return nil to indicate that this setting should uses the global setting instead (that is false since the setting does not exists yet).
            return nil
        }
    }

}

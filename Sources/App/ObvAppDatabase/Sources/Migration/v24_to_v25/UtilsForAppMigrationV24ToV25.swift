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
import ObvAppCoreConstants


fileprivate let errorDomain = "UtilsForAppMigrationV24ToV25"
fileprivate let debugPrintPrefix = "[\(errorDomain)][UtilsForAppMigrationV24ToV25]"


final class UtilsForAppMigrationV24ToV25 {

    static func createDefaultPersistedDiscussionSharedConfiguration(forDiscussion discussion: NSManagedObject, destinationContext: NSManagedObjectContext) throws {
        
        let sharedConfiguration: NSManagedObject
        do {
            let entityName = "PersistedDiscussionSharedConfiguration"
            guard let description = NSEntityDescription.entity(forEntityName: entityName, in: destinationContext) else {
                let message = "Invalid entity name: \(entityName)"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            sharedConfiguration = NSManagedObject(entity: description, insertInto: destinationContext)
        }
        
        // Set all the values of the PersistedDiscussionSharedConfiguration
        
        sharedConfiguration.setValue(nil, forKey: "rawExistenceDuration")
        sharedConfiguration.setValue(nil, forKey: "rawVisibilityDuration")
        sharedConfiguration.setValue(false, forKey: "readOnce")
        sharedConfiguration.setValue(0, forKey: "version")

        sharedConfiguration.setValue(discussion, forKey: "discussion")

    }
    
    
    static func createDefaultPersistedDiscussionLocalConfiguration(forDiscussion discussion: NSManagedObject, destinationContext: NSManagedObjectContext, sDiscussionURL: URL) throws {
        
        let localConfiguration: NSManagedObject
        do {
            let entityName = "PersistedDiscussionLocalConfiguration"
            guard let description = NSEntityDescription.entity(forEntityName: entityName, in: destinationContext) else {
                let message = "Invalid entity name: \(entityName)"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            localConfiguration = NSManagedObject(entity: description, insertInto: destinationContext)
        }

        let previousConfig = recoverPreviousLocalSettings(sDiscussionURL: sDiscussionURL)
        
        localConfiguration.setValue(false, forKey: "autoRead")
        localConfiguration.setValue(previousConfig.rawDoFetchContentRichURLsMetadata, forKey: "rawDoFetchContentRichURLsMetadata")
        localConfiguration.setValue(previousConfig.rawDoSendReadReceipt, forKey: "rawDoSendReadReceipt")
        localConfiguration.setValue(false, forKey: "retainWipedOutboundMessages")

        localConfiguration.setValue(discussion, forKey: "discussion")

    }
    
    
    private static func recoverPreviousLocalSettings(sDiscussionURL: URL) -> (rawDoFetchContentRichURLsMetadata: Int?, rawDoSendReadReceipt: Bool?) {
        
        let rawDoFetchContentRichURLsMetadata: Int?
        do {
            let doFetchContentRichURLsMetadataOverride = getFetchContentRichURLsMetadataOverrideWithinDiscussion(with: sDiscussionURL)
            switch doFetchContentRichURLsMetadataOverride {
            case .none:
                rawDoFetchContentRichURLsMetadata = nil
            case .override(let doFetchContentRichURLsMetadata):
                rawDoFetchContentRichURLsMetadata = doFetchContentRichURLsMetadata.rawValue
            }
        }
        
        let rawDoSendReadReceipt: Bool?
        do {
            let rawDoSendReadReceiptOverride = getSendReadReceiptOverrideWithinDiscussion(with: sDiscussionURL)
            switch rawDoSendReadReceiptOverride {
            case .none:
                rawDoSendReadReceipt = nil
            case .override(value: let value):
                rawDoSendReadReceipt = value
            }
        }
        
        return (rawDoFetchContentRichURLsMetadata, rawDoSendReadReceipt)
        
    }
    
    /// 2024-09-10 Abusively marked as nonisolated(unsafe)
    nonisolated(unsafe) private static let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier)!

    
    private enum FetchContentRichURLsMetadataChoice: Int {
        case never = 0
        case withinSentMessagesOnly = 1
        case always = 2
    }

    
    private enum FetchContentRichURLsMetadataChoiceOverride {
        case none
        case override(value: FetchContentRichURLsMetadataChoice)
    }
    
    
    private enum BoolSettingOverrideType {
        case none
        case override(value: Bool)
    }


    private static func getFetchContentRichURLsMetadataOverrideWithinDiscussion(with url: URL) -> FetchContentRichURLsMetadataChoiceOverride {
        guard let currentValues = userDefaults.dictionary(forKey: "settings.discussions.doFetchContentRichURLsMetadata.withinDiscussion") else {
            return .none
        }
        guard let rawValue = currentValues[url.absoluteString] as? Int else {
            return .none
        }
        guard let doFetchContentRichURLsMetadataForThisDiscussion = FetchContentRichURLsMetadataChoice(rawValue: rawValue) else {
            return .none
        }
        return .override(value: doFetchContentRichURLsMetadataForThisDiscussion)
    }

    
    private static func getSendReadReceiptOverrideWithinDiscussion(with url: URL) -> BoolSettingOverrideType {
        guard let currentValues = userDefaults.dictionary(forKey: "settings.discussions.doSendReadReceipt.withinDiscussion") else {
            return .none
        }
        guard let doSendReadReceiptForThisDiscussion = currentValues[url.absoluteString] as? Bool else {
            return .none
        }
        return .override(value: doSendReadReceiptForThisDiscussion)
    }

}

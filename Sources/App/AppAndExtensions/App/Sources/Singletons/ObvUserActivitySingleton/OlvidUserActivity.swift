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
import ObvTypes
import ObvUICoreData
import ObvAppTypes

/// Represents a user's activity state within the Olvid app.
///
/// Equality for `OlvidUserActivity` is determined by comparing the `ownedCryptoId`, `currentFlow`, and `currentDiscussion` properties.
/// If additional properties are added to this type in the future, ensure both `isEqual(_:)` and `==(lhs:rhs:)` are updated to include them in the comparison.
///
/// - Warning: Custom implementations of `isEqual(_:)` and `==(lhs:rhs:)` are provided to enforce value-based equality.
///   Always update these methods when modifying the properties that define equality.
final class OlvidUserActivity: NSUserActivity {
    
    let ownedCryptoId: ObvCryptoId
    let currentFlow: ObvAppTypes.ObvFlow
    let currentDiscussion: ObvDiscussionIdentifier?
    
    
    init(ownedCryptoId: ObvCryptoId, currentFlow: ObvAppTypes.ObvFlow, currentDiscussion: ObvDiscussionIdentifier?) {
        self.currentFlow = currentFlow
        self.currentDiscussion = currentDiscussion
        self.ownedCryptoId = ownedCryptoId
        super.init(activityType: Self.nsUserActivityType(currentFlow: currentFlow, currentDiscussion: currentDiscussion))
        self.updateNSUserActivityProperties()
    }

    
    /// When receiving an `NSUserActivity`, .e.g, in the ``scene(_:continue:)`` of the scene delegate, we use this initialiser to try to reconstruct an ``OlvidUserActivity``.
    convenience init?(receivedNSUserActivity: NSUserActivity) {
        
        guard DeclaredNSUserActivityType(rawValue: receivedNSUserActivity.activityType) != nil else { return nil }
        
        guard let receivedUserInfo = receivedNSUserActivity.userInfo else { assertionFailure(); return nil }
        guard let rawOwnedCryptoIdHex = receivedUserInfo["ownedCryptoId"] as? String,
              let rawOwnedCryptoId = Data(hexString: rawOwnedCryptoIdHex),
              let rawCurrentFlow = receivedUserInfo["currentFlow"] as? String ?? receivedUserInfo["selectedTab"] as? String else { // 2025-09-17 "selectedTab" kepts for legacy reasons. "currentFlow" used since version 4.0
            assertionFailure()
            return nil
        }
        guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedCryptoId) else { assertionFailure(); return nil }
        guard let currentFlow = ObvFlow(rawValue: rawCurrentFlow) else { assertionFailure(); return nil }
        
        let currentDiscussion: ObvDiscussionIdentifier?
        if let rawCurrentDiscussion = receivedUserInfo["currentDiscussion"] as? String {
            currentDiscussion = ObvDiscussionIdentifier(rawCurrentDiscussion)
        } else {
            currentDiscussion = nil
        }
        
        self.init(ownedCryptoId: ownedCryptoId, currentFlow: currentFlow, currentDiscussion: currentDiscussion)
        
    }
    
    
    func withUpdatedCurrentDiscussion(_ currentDiscussion: ObvDiscussionIdentifier?) -> OlvidUserActivity {
        return OlvidUserActivity(ownedCryptoId: ownedCryptoId, currentFlow: currentFlow, currentDiscussion: currentDiscussion)
    }
    
    
    func withUpdatedOwnedCryptoId(_ newOwnedCryptoId: ObvCryptoId) -> OlvidUserActivity {
        return OlvidUserActivity(ownedCryptoId: newOwnedCryptoId, currentFlow: currentFlow, currentDiscussion: currentDiscussion)
    }
    
    
    func widthUpdatedCurrentFlow(_ newCurrentFlow: ObvFlow) -> OlvidUserActivity {
        return OlvidUserActivity(ownedCryptoId: ownedCryptoId, currentFlow: newCurrentFlow, currentDiscussion: currentDiscussion)
    }
    
    
    override var debugDescription: String {
        return "NewObvUserActivityType<\(ownedCryptoId.debugDescription)|\(currentFlow.debugDescription)|\(currentDiscussion?.debugDescription ?? "None")>"
    }
    
    
    private enum DeclaredNSUserActivityType: String, CaseIterable {
        case continueDiscussion = "io.olvid.messenger.continueDiscussion"
        case displayLatestDiscussions = "io.olvid.messenger.displayLatestDiscussions"
        case displayContacts = "io.olvid.messenger.displayContacts"
        case displayGroups = "io.olvid.messenger.displayGroups"
        case displayInvitations = "io.olvid.messenger.displayInvitations"
    }
    
    
    // NSUserActivityTypes (as declared in info.plist)
    private static func nsUserActivityType(currentFlow: ObvAppTypes.ObvFlow, currentDiscussion: ObvDiscussionIdentifier?) -> String {
        if currentDiscussion != nil {
            return DeclaredNSUserActivityType.continueDiscussion.rawValue
        } else {
            switch currentFlow {
            case .latestDiscussions:
                return DeclaredNSUserActivityType.displayLatestDiscussions.rawValue
            case .contacts:
                return DeclaredNSUserActivityType.displayContacts.rawValue
            case .groups:
                return DeclaredNSUserActivityType.displayGroups.rawValue
            case .invitations:
                return DeclaredNSUserActivityType.displayInvitations.rawValue
            }
        }
    }

    
    // Updating NSUserActivity properties

    private func updateNSUserActivityProperties() {
        self.title = nsUserActivityTitle
        self.userInfo = nsUserActivityTitleUserInfo
    }
    
    
    private var nsUserActivityTitle: String {
        if currentDiscussion != nil {
            return NSLocalizedString("NS_USER_ACTIVITY_TITLE_CONTINUE_DISCUSSION", comment: "NSUserActivity title")
        } else {
            switch currentFlow {
            case .latestDiscussions:
                return NSLocalizedString("NS_USER_ACTIVITY_TITLE_LATEST_DISCUSSIONS", comment: "NSUserActivity title")
            case .contacts:
                return NSLocalizedString("NS_USER_ACTIVITY_TITLE_CONTACTS", comment: "NSUserActivity title")
            case .groups:
                return NSLocalizedString("NS_USER_ACTIVITY_TITLE_GROUPS", comment: "NSUserActivity title")
            case .invitations:
                return NSLocalizedString("NS_USER_ACTIVITY_TITLE_INVITATIONS", comment: "NSUserActivity title")
            }
        }
    }
    
    
    private var nsUserActivityTitleUserInfo: [NSString: NSString] {

        var userInfo = [NSString: NSString]()
        
        userInfo["ownedCryptoId"] = ownedCryptoId.description as NSString
        userInfo["currentFlow"] = currentFlow.rawValue as NSString
        
        if let currentDiscussion {
            userInfo["currentDiscussion"] = currentDiscussion.description as NSString
        }
            
        return userInfo
        
    }

}


extension OlvidUserActivity {
    
    override func isEqual(_ object: Any?) -> Bool {
        guard let otherUserActivity = object as? OlvidUserActivity else { assertionFailure(); return false }
        return self == otherUserActivity
    }
    
    static func == (lhs: OlvidUserActivity, rhs: OlvidUserActivity) -> Bool {
        return lhs.ownedCryptoId == rhs.ownedCryptoId &&
        lhs.currentFlow == rhs.currentFlow &&
        lhs.currentDiscussion == rhs.currentDiscussion
    }
    
}

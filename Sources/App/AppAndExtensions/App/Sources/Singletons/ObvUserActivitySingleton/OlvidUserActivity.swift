/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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


final class OlvidUserActivity: NSUserActivity {
    
    let ownedCryptoId: ObvCryptoId
    let selectedTab: TabType
    let currentDiscussion: ObvDiscussionIdentifier?
    
    
    init(ownedCryptoId: ObvCryptoId, selectedTab: TabType, currentDiscussion: ObvDiscussionIdentifier?) {
        self.selectedTab = selectedTab
        self.currentDiscussion = currentDiscussion
        self.ownedCryptoId = ownedCryptoId
        super.init(activityType: Self.nsUserActivityType(selectedTab: selectedTab, currentDiscussion: currentDiscussion))
        self.updateNSUserActivityProperties()
    }

    
    /// When receiving an `NSUserActivity`, .e.g, in the ``scene(_:continue:)`` of the scene delegate, we use this initialiser to try to reconstruct an ``OlvidUserActivity``.
    convenience init?(receivedNSUserActivity: NSUserActivity) {
        
        guard DeclaredNSUserActivityType(rawValue: receivedNSUserActivity.activityType) != nil else { return nil }
        
        guard let receivedUserInfo = receivedNSUserActivity.userInfo else { assertionFailure(); return nil }
        guard let rawOwnedCryptoIdHex = receivedUserInfo["ownedCryptoId"] as? String,
              let rawOwnedCryptoId = Data(hexString: rawOwnedCryptoIdHex),
              let rawSelectedTab = receivedUserInfo["selectedTab"] as? String else {
            assertionFailure()
            return nil
        }
        guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedCryptoId) else { assertionFailure(); return nil }
        guard let selectedTab = TabType(rawValue: rawSelectedTab) else { assertionFailure(); return nil }
        
        let currentDiscussion: ObvDiscussionIdentifier?
        if let rawCurrentDiscussion = receivedUserInfo["currentDiscussion"] as? String {
            currentDiscussion = ObvDiscussionIdentifier(rawCurrentDiscussion)
        } else {
            currentDiscussion = nil
        }
        
        self.init(ownedCryptoId: ownedCryptoId, selectedTab: selectedTab, currentDiscussion: currentDiscussion)
        
    }
    
    
    func withUpdatedCurrentDiscussion(_ currentDiscussion: ObvDiscussionIdentifier?) -> OlvidUserActivity {
        return OlvidUserActivity(ownedCryptoId: ownedCryptoId, selectedTab: selectedTab, currentDiscussion: currentDiscussion)
    }
    
    
    func withUpdatedOwnedCryptoId(_ newOwnedCryptoId: ObvCryptoId) -> OlvidUserActivity {
        return OlvidUserActivity(ownedCryptoId: newOwnedCryptoId, selectedTab: selectedTab, currentDiscussion: currentDiscussion)
    }
    
    
    override var debugDescription: String {
        return "NewObvUserActivityType<\(ownedCryptoId.debugDescription)|\(selectedTab.debugDescription)|\(currentDiscussion?.debugDescription ?? "None")>"
    }
    
    
    private enum DeclaredNSUserActivityType: String, CaseIterable {
        case continueDiscussion = "io.olvid.messenger.continueDiscussion"
        case displayLatestDiscussions = "io.olvid.messenger.displayLatestDiscussions"
        case displayContacts = "io.olvid.messenger.displayContacts"
        case displayGroups = "io.olvid.messenger.displayGroups"
        case displayInvitations = "io.olvid.messenger.displayInvitations"
    }
    
    
    // NSUserActivityTypes (as declared in info.plist)
    private static func nsUserActivityType(selectedTab: TabType, currentDiscussion: ObvDiscussionIdentifier?) -> String {
        if currentDiscussion != nil {
            return DeclaredNSUserActivityType.continueDiscussion.rawValue
        } else {
            switch selectedTab {
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
            switch selectedTab {
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
        userInfo["selectedTab"] = selectedTab.rawValue as NSString
        
        if let currentDiscussion {
            userInfo["currentDiscussion"] = currentDiscussion.description as NSString
        }
            
        return userInfo
        
    }

}



// MARK: - TabType

extension OlvidUserActivity {
    
    enum TabType: String, Equatable, CustomDebugStringConvertible {
        
        case latestDiscussions = "latestDiscussions"
        case contacts = "contacts"
        case groups = "groups"
        case invitations = "invitations"
        
        var debugDescription: String {
            self.rawValue
        }
        
    }
}


// MARK: - Private helpers

extension PersistedDiscussion {
    
    var discussionIdentifier: ObvDiscussionIdentifier? {
        do {
            switch try self.kind {
            case .oneToOne(withContactIdentity: let contactIdentity):
                if let contactIdentity {
                    let contactId = try contactIdentity.obvContactIdentifier
                    return .oneToOne(id: contactId)
                } else {
                    // This occurs in a locked discussion, if the contact was permanently deleted
                    assert(self.status == .locked)
                    guard let contactId = (self as? PersistedOneToOneDiscussion)?.contactIdentifier else { assertionFailure(); return nil }
                    return .oneToOne(id: contactId)
                }
            case .groupV1(withContactGroup: let groupV1):
                if let groupV1 {
                    let groupId = try groupV1.obvGroupIdentifier
                    return .groupV1(id: groupId)
                } else {
                    // This occurs in a locked discussion (in which case the group is nil)
                    guard let groupId = (self as? PersistedGroupDiscussion)?.groupIdentifier else { assertionFailure(); return nil }
                    return .groupV1(id: groupId)
                }
            case .groupV2(withGroup: let groupV2):
                if let groupV2 {
                    let groupId = try groupV2.obvGroupIdentifier
                    return .groupV2(id: groupId)
                } else {
                    // This occurs in a locked discussion (in which case the group is nil)
                    guard let groupId = (self as? PersistedGroupV2Discussion)?.obvGroupIdentifier else { assertionFailure(); return nil }
                    return .groupV2(id: groupId)
                }
            }
        } catch {
            assertionFailure()
            return nil
        }
    }
    
}

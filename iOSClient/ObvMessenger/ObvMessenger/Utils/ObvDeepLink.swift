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


enum ObvDeepLink {
    case latestDiscussions
    case singleDiscussion(discussionObjectURI: URL)
    case invitations
    case contactGroupDetails(contactGroupURI: URL)
    case contactIdentityDetails(contactIdentityURI: URL)
    case airDrop(fileURL: URL)
    case qrCodeScan
    case myId(ownedIdentityURI: URL)
    case requestRecordPermission
    case settings
    case backupSettings
    
    private static let scheme = "io.olvid.messenger"
    
    private struct Components {
        struct LatestDiscussions {
            static let host = "latestDiscussions"
        }
        struct SingleDiscussion {
            static let host = "singleDiscussion"
            struct QueryItems {
                struct DiscussionObjectURI {
                    static let name = "discussionObjectURI"
                }
            }
        }
        struct Invitations {
            static let host = "invitations"
        }
        struct ContactGroupDetails {
            static let host = "contactGroupDetails"
            struct QueryItems {
                struct ContactGroupURI {
                    static let name = "contactGroupURI"
                }
            }
        }
        struct ContactIdentityDetails {
            static let host = "contactIdentityDetails"
            struct QueryItems {
                struct ContactIdentityURI {
                    static let name = "contactIdentityURI"
                }
            }
        }
        struct AirDrop {
            static let host = "airDrop"
            struct QueryItems {
                struct FileURL {
                    static let name = "fileURL"
                }
            }
        }
        struct QRCodeScan {
            static let host = "qrCodeScan"
        }
        struct MyId {
            static let host = "myId"
            struct QueryItems {
                struct OwnedIdentityURI {
                    static let name = "ownedIdentityURI"
                }
            }
        }
        struct RequestRecordPermission {
            static let host = "requestRecordPermission"
        }
        struct Settings {
            static let host = "settings"
        }
        struct BackupSettings {
            static let host = "backupSettings"
        }
    }
    
    var url: URL {
        var components = URLComponents()
        components.scheme = ObvDeepLink.scheme
        switch self {
        case .backupSettings:
            components.host = Components.BackupSettings.host
        case .settings:
            components.host = Components.Settings.host
        case .latestDiscussions:
            components.host = Components.LatestDiscussions.host
        case .singleDiscussion(discussionObjectURI: let discussionObjectURI):
            components.host = Components.SingleDiscussion.host
            components.queryItems = [
                URLQueryItem(name: Components.SingleDiscussion.QueryItems.DiscussionObjectURI.name, value: discussionObjectURI.absoluteString),
            ]
        case .invitations:
            components.host = Components.Invitations.host
        case .contactGroupDetails(contactGroupURI: let contactGroupURI):
            components.host = Components.ContactGroupDetails.host
            components.queryItems = [
                URLQueryItem(name: Components.ContactGroupDetails.QueryItems.ContactGroupURI.name, value: contactGroupURI.absoluteString)
            ]
        case .contactIdentityDetails(contactIdentityURI: let contactIdentityURI):
            components.host = Components.ContactIdentityDetails.host
            components.queryItems = [
                URLQueryItem(name: Components.ContactIdentityDetails.QueryItems.ContactIdentityURI.name, value: contactIdentityURI.absoluteString)
            ]
        case .airDrop(fileURL: let fileURL):
            components.host = Components.AirDrop.host
            components.queryItems = [
                URLQueryItem(name: Components.AirDrop.QueryItems.FileURL.name, value: fileURL.absoluteString)
            ]
        case .qrCodeScan:
            components.host = Components.QRCodeScan.host
        case .myId(ownedIdentityURI: let ownedIdentityURI):
            components.host = Components.MyId.host
            components.queryItems = [
                URLQueryItem(name: Components.MyId.QueryItems.OwnedIdentityURI.name, value: ownedIdentityURI.absoluteString)
            ]
        case .requestRecordPermission:
            components.host = Components.RequestRecordPermission.host
        }
        assert(components.url != nil)
        let url = components.url!
        assert(ObvDeepLink(url: url) != nil) // Use to never forget a case in following init
        return url
    }
    
    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        guard components.scheme == ObvDeepLink.scheme else { return nil }
        switch components.host {
        case Components.LatestDiscussions.host:
            self = .latestDiscussions
        case Components.SingleDiscussion.host:
            guard let queryItems = components.queryItems else { assertionFailure(); return nil }
            guard Set(queryItems.map({ $0.name })) == Set([Components.SingleDiscussion.QueryItems.DiscussionObjectURI.name]) else { assertionFailure(); return nil }
            var discussionObjectURI: URL?
            for queryItem in queryItems {
                if queryItem.name == Components.SingleDiscussion.QueryItems.DiscussionObjectURI.name, let value = queryItem.value {
                    discussionObjectURI = URL(string: value)
                }
            }
            guard discussionObjectURI != nil else { return nil }
            self = .singleDiscussion(discussionObjectURI: discussionObjectURI!)
        case Components.Invitations.host:
            self = .invitations
        case Components.ContactGroupDetails.host:
            guard let queryItems = components.queryItems else { assertionFailure(); return nil }
            guard Set(queryItems.map({ $0.name })) == Set([Components.SingleDiscussion.QueryItems.DiscussionObjectURI.name]) else { assertionFailure(); return nil }
            var contactGroupURI: URL?
            for queryItem in queryItems {
                if queryItem.name == Components.ContactGroupDetails.QueryItems.ContactGroupURI.name, let value = queryItem.value {
                    contactGroupURI = URL(string: value)
                }
            }
            guard contactGroupURI != nil else { return nil }
            self = .contactGroupDetails(contactGroupURI: contactGroupURI!)
        case Components.ContactIdentityDetails.host:
            guard let queryItems = components.queryItems else { assertionFailure(); return nil }
            guard Set(queryItems.map({ $0.name })) == Set([Components.ContactIdentityDetails.QueryItems.ContactIdentityURI.name]) else { assertionFailure(); return nil }
            var contactIdentityURI: URL?
            for queryItem in queryItems {
                if queryItem.name == Components.ContactIdentityDetails.QueryItems.ContactIdentityURI.name, let value = queryItem.value {
                    contactIdentityURI = URL(string: value)
                }
            }
            guard contactIdentityURI != nil else { return nil }
            self = .contactIdentityDetails(contactIdentityURI: contactIdentityURI!)
        case Components.AirDrop.host:
            guard let queryItems = components.queryItems else { assertionFailure(); return nil }
            var fileURL: URL?
            for queryItem in queryItems {
                if queryItem.name == Components.AirDrop.QueryItems.FileURL.name, let value = queryItem.value {
                    fileURL = URL(string: value)
                }
            }
            guard fileURL != nil else { assertionFailure(); return nil }
            self = .airDrop(fileURL: fileURL!)
        case Components.QRCodeScan.host:
            self = .qrCodeScan
        case Components.MyId.host:
            guard let queryItems = components.queryItems else { assertionFailure(); return nil }
            guard Set(queryItems.map({ $0.name })) == Set([Components.MyId.QueryItems.OwnedIdentityURI.name]) else { assertionFailure(); return nil }
            var ownedIdentityURI: URL?
            for queryItem in queryItems {
                if queryItem.name == Components.MyId.QueryItems.OwnedIdentityURI.name, let value = queryItem.value {
                    ownedIdentityURI = URL(string: value)
                }
            }
            guard ownedIdentityURI != nil else { return nil }
            self = .myId(ownedIdentityURI: ownedIdentityURI!)
        case Components.RequestRecordPermission.host:
            self = .requestRecordPermission
        case Components.Settings.host:
            self = .settings
        case Components.BackupSettings.host:
            self = .backupSettings
        default:
            assertionFailure()
            return nil
        }
    }
    
}

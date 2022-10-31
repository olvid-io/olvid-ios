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

enum ObvDeepLinkHost: CaseIterable {
    case latestDiscussions
    case singleDiscussion
    case invitations
    case contactGroupDetails
    case contactIdentityDetails
    case airDrop
    case qrCodeScan
    case myId
    case requestRecordPermission
    case settings
    case backupSettings
    case message

    var name: String { String(describing: self) }

    init?(name: String) {
        for host in ObvDeepLinkHost.allCases {
            if name == host.name {
                self = host
                return
            }
        }
        return nil
    }

    fileprivate var queryItemsKey: String? {
        switch self {
        case .latestDiscussions: return nil
        case .singleDiscussion: return "discussionObjectURI"
        case .invitations: return nil
        case .contactGroupDetails: return "displayedContactGroupURI"
        case .contactIdentityDetails: return "contactIdentityURI"
        case .airDrop: return "fileURL"
        case .qrCodeScan: return nil
        case .myId: return "ownedIdentityURI"
        case .requestRecordPermission: return nil
        case .settings: return nil
        case .backupSettings: return nil
        case .message: return "messageObjectURI"
        }
    }
}

/// Don't forget to run ObvDeepLinkTests if you made modification to ObvDeepLink ;)
enum ObvDeepLink: Equatable {
    case latestDiscussions
    case singleDiscussion(discussionObjectURI: URL)
    case invitations
    case contactGroupDetails(displayedContactGroupURI: URL)
    case contactIdentityDetails(contactIdentityURI: URL)
    case airDrop(fileURL: URL)
    case qrCodeScan
    case myId(ownedIdentityURI: URL)
    case requestRecordPermission
    case settings
    case backupSettings
    case message(messageObjectURI: URL)

    private static let scheme = "io.olvid.messenger"

    fileprivate var host: ObvDeepLinkHost {
        switch self {
        case .latestDiscussions: return .latestDiscussions
        case .singleDiscussion: return .singleDiscussion
        case .invitations: return .invitations
        case .contactGroupDetails: return .contactGroupDetails
        case .contactIdentityDetails: return .contactIdentityDetails
        case .airDrop: return .airDrop
        case .qrCodeScan: return .qrCodeScan
        case .myId: return .myId
        case .requestRecordPermission: return .requestRecordPermission
        case .settings: return .settings
        case .backupSettings: return .backupSettings
        case .message: return .message
        }
    }

    fileprivate var queryItems: [String: URL] {
        switch self {
        case .latestDiscussions: return [:]
        case .singleDiscussion(let discussionObjectURI):
            guard let queryItemsKey = host.queryItemsKey else { assertionFailure(); return [:] }
            return [queryItemsKey: discussionObjectURI]
        case .invitations: return [:]
        case .contactGroupDetails(displayedContactGroupURI: let displayedContactGroupURI):
            guard let queryItemsKey = host.queryItemsKey else { assertionFailure(); return [:] }
            return [queryItemsKey: displayedContactGroupURI]
        case .contactIdentityDetails(let contactIdentityURI):
            guard let queryItemsKey = host.queryItemsKey else { assertionFailure(); return [:] }
            return [queryItemsKey: contactIdentityURI]
        case .airDrop(let fileURL):
            guard let queryItemsKey = host.queryItemsKey else { assertionFailure(); return [:] }
            return [queryItemsKey: fileURL]
        case .qrCodeScan: return [:]
        case .myId(let ownedIdentityURI):
            guard let queryItemsKey = host.queryItemsKey else { assertionFailure(); return [:] }
            return [queryItemsKey: ownedIdentityURI]
        case .requestRecordPermission: return [:]
        case .settings: return [:]
        case .backupSettings: return [:]
        case .message(messageObjectURI: let messageObjectURI):
            guard let queryItemsKey = host.queryItemsKey else { assertionFailure(); return [:] }
            return [queryItemsKey: messageObjectURI]
        }
    }
    
    var url: URL {
        var components = URLComponents()
        components.scheme = ObvDeepLink.scheme
        components.host = host.name
        components.queryItems = queryItems.map { URLQueryItem(name: $0.key, value: $0.value.absoluteString) }
        assert(components.url != nil)
        let url = components.url!
        assert(ObvDeepLink(url: url) == self)
        return url
    }
    
    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        guard components.scheme == ObvDeepLink.scheme else { return nil }
        guard let hostName = components.host else { return nil }
        guard let host = ObvDeepLinkHost(name: hostName) else { return nil }
        func computeQueryItemValue() -> URL? {
            guard let queryItems = components.queryItems else { return nil }
            guard let queryItemsKey = host.queryItemsKey else { return nil }
            guard Set(queryItems.map({ $0.name })) == Set([queryItemsKey]) else { return nil }
            for queryItem in queryItems {
                if queryItem.name == queryItemsKey, let value = queryItem.value {
                    return URL(string: value)
                }
            }
            return nil
        }
        switch host {
        case .latestDiscussions:
            self = .latestDiscussions
        case .singleDiscussion:
            guard let url = computeQueryItemValue() else { assertionFailure(); return nil }
            self = .singleDiscussion(discussionObjectURI: url)
        case .invitations:
            self = .invitations
        case .contactGroupDetails:
            guard let url = computeQueryItemValue() else { assertionFailure(); return nil }
            self = .contactGroupDetails(displayedContactGroupURI: url)
        case .contactIdentityDetails:
            guard let url = computeQueryItemValue() else { assertionFailure(); return nil }
            self = .contactIdentityDetails(contactIdentityURI: url)
        case .airDrop:
            guard let url = computeQueryItemValue() else { assertionFailure(); return nil }
            self = .airDrop(fileURL: url)
        case .qrCodeScan:
            self = .qrCodeScan
        case .myId:
            guard let url = computeQueryItemValue() else { assertionFailure(); return nil }
            self = .myId(ownedIdentityURI: url)
        case .requestRecordPermission:
            self = .requestRecordPermission
        case .settings:
            self = .settings
        case .backupSettings:
            self = .backupSettings
        case .message:
            guard let url = computeQueryItemValue() else { assertionFailure(); return nil }
            self = .message(messageObjectURI: url)
        }
    }
    
}

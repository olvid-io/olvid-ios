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
    case allGroups

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

}


/// Don't forget to run ObvDeepLinkTests if you made modification to ObvDeepLink ;)
enum ObvDeepLink: Equatable, LosslessStringConvertible {
    
    case latestDiscussions
    case singleDiscussion(objectPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>)
    case invitations
    case contactGroupDetails(objectPermanentID: ObvManagedObjectPermanentID<DisplayedContactGroup>)
    case contactIdentityDetails(objectPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>)
    case airDrop(fileURL: URL)
    case qrCodeScan
    case myId(objectPermanentID: ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>)
    case requestRecordPermission
    case settings
    case backupSettings
    case message(objectPermanentID: ObvManagedObjectPermanentID<PersistedMessage>)
    case allGroups

    var description: String {
        switch self {
        case .latestDiscussions:
            return host.name
        case .singleDiscussion(let objectPermanentID):
            return [host.name, objectPermanentID.description].joined(separator: "/")
        case .invitations:
            return host.name
        case .contactGroupDetails(let objectPermanentID):
            return [host.name, objectPermanentID.description].joined(separator: "/")
        case .contactIdentityDetails(let objectPermanentID):
            return [host.name, objectPermanentID.description].joined(separator: "/")
        case .airDrop(let fileURL):
            return [host.name, fileURL.path].joined(separator: "/")
        case .qrCodeScan:
            return host.name
        case .myId(let objectPermanentID):
            return [host.name, objectPermanentID.description].joined(separator: "/")
        case .requestRecordPermission:
            return host.name
        case .settings:
            return host.name
        case .backupSettings:
            return host.name
        case .message(let objectPermanentID):
            return [host.name, objectPermanentID.description].joined(separator: "/")
        case .allGroups:
            return host.name
        }
    }
    
    
    init?(_ description: String) {
        let splits = description.split(separator: "/", maxSplits: 1).map { String($0) }
        guard let hostAsString = splits.first else { assertionFailure(); return nil }
        guard let host = ObvDeepLinkHost(name: hostAsString) else { assertionFailure(); return nil }
        switch host {
        case .latestDiscussions:
            self = .latestDiscussions
        case .singleDiscussion:
            guard splits.count == 2 else { assertionFailure(); return nil }
            guard let objectPermanentID = ObvManagedObjectPermanentID<PersistedDiscussion>(splits[1]) else { assertionFailure(); return nil }
            self = .singleDiscussion(objectPermanentID: objectPermanentID)
        case .invitations:
            self = .invitations
        case .contactGroupDetails:
            guard splits.count == 2 else { assertionFailure(); return nil }
            guard let objectPermanentID = ObvManagedObjectPermanentID<DisplayedContactGroup>(splits[1]) else { assertionFailure(); return nil }
            self = .contactGroupDetails(objectPermanentID: objectPermanentID)
        case .contactIdentityDetails:
            guard splits.count == 2 else { assertionFailure(); return nil }
            guard let objectPermanentID = ObvManagedObjectPermanentID<PersistedObvContactIdentity>(splits[1]) else { assertionFailure(); return nil }
            self = .contactIdentityDetails(objectPermanentID: objectPermanentID)
        case .airDrop:
            guard splits.count == 2 else { assertionFailure(); return nil }
            guard let fileURL = URL(string: splits[1]) else { assertionFailure(); return nil }
            self = .airDrop(fileURL: fileURL)
        case .qrCodeScan:
            self = .qrCodeScan
        case .myId:
            guard splits.count == 2 else { assertionFailure(); return nil }
            guard let objectPermanentID = ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>(splits[1]) else { assertionFailure(); return nil }
            self = .myId(objectPermanentID: objectPermanentID)
        case .requestRecordPermission:
            self = .requestRecordPermission
        case .settings:
            self = .settings
        case .backupSettings:
            self = .backupSettings
        case .message:
            guard splits.count == 2 else { assertionFailure(); return nil }
            guard let objectPermanentID = ObvManagedObjectPermanentID<PersistedMessage>(splits[1]) else { assertionFailure(); return nil }
            self = .message(objectPermanentID: objectPermanentID)
        case .allGroups:
            self = .allGroups
        }
    }


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
        case .allGroups: return .allGroups
        }
    }

}

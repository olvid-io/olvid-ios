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
import ObvTypes

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
    case privacySettings
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
    
    case latestDiscussions(ownedCryptoId: ObvCryptoId?)
    case singleDiscussion(ownedCryptoId: ObvCryptoId, objectPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>)
    case invitations(ownedCryptoId: ObvCryptoId)
    case contactGroupDetails(ownedCryptoId: ObvCryptoId, objectPermanentID: ObvManagedObjectPermanentID<DisplayedContactGroup>)
    case contactIdentityDetails(ownedCryptoId: ObvCryptoId, objectPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>)
    case airDrop(fileURL: URL)
    case qrCodeScan
    case myId(ownedCryptoId: ObvCryptoId)
    case requestRecordPermission
    case settings
    case backupSettings
    case privacySettings
    case message(ownedCryptoId: ObvCryptoId, objectPermanentID: ObvManagedObjectPermanentID<PersistedMessage>)
    case allGroups(ownedCryptoId: ObvCryptoId)

    var description: String {
        switch self {
        case .latestDiscussions(let ownedCryptoId):
            if let ownedCryptoId {
                return [host.name, ownedCryptoId.description].joined(separator: "|")
            } else {
                return host.name
            }
        case .singleDiscussion(let ownedCryptoId, let objectPermanentID):
            return [host.name, ownedCryptoId.description, objectPermanentID.description].joined(separator: "|")
        case .invitations(let ownedCryptoId):
            return [host.name, ownedCryptoId.description].joined(separator: "|")
        case .contactGroupDetails(let ownedCryptoId, let objectPermanentID):
            return [host.name, ownedCryptoId.description, objectPermanentID.description].joined(separator: "|")
        case .contactIdentityDetails(let ownedCryptoId, let objectPermanentID):
            return [host.name, ownedCryptoId.description, objectPermanentID.description].joined(separator: "|")
        case .airDrop(let fileURL):
            return [host.name, fileURL.path].joined(separator: "|")
        case .qrCodeScan:
            return host.name
        case .myId(let ownedCryptoId):
            return [host.name, ownedCryptoId.description].joined(separator: "|")
        case .requestRecordPermission:
            return host.name
        case .settings:
            return host.name
        case .backupSettings:
            return host.name
        case .privacySettings:
            return host.name
        case .message(let ownedCryptoId, let objectPermanentID):
            return [host.name, ownedCryptoId.description, objectPermanentID.description].joined(separator: "|")
        case .allGroups(let ownedCryptoId):
            return [host.name, ownedCryptoId.description].joined(separator: "|")
        }
    }
    
    
    init?(_ description: String) {
        // For some reason, using
        let splits = description.split(separator: "|", maxSplits: 2).map { String($0) }
        guard let hostAsString = splits.first else { assertionFailure(); return nil }
        guard let host = ObvDeepLinkHost(name: hostAsString) else { assertionFailure(); return nil }
        switch host {
        case .latestDiscussions:
            if splits.count == 1 {
                self = .latestDiscussions(ownedCryptoId: nil)
            } else if splits.count == 2 {
                guard let ownedCryptoId = ObvCryptoId(splits[1]) else { assertionFailure(); return nil }
                self = .latestDiscussions(ownedCryptoId: ownedCryptoId)
            } else {
                assertionFailure()
                return nil
            }
        case .singleDiscussion:
            guard splits.count == 3 else { assertionFailure(); return nil }
            guard let ownedCryptoId = ObvCryptoId(splits[1]) else { assertionFailure(); return nil }
            guard let objectPermanentID = ObvManagedObjectPermanentID<PersistedDiscussion>(splits[2]) else { assertionFailure(); return nil }
            self = .singleDiscussion(ownedCryptoId: ownedCryptoId, objectPermanentID: objectPermanentID)
        case .invitations:
            guard splits.count == 2 else { assertionFailure(); return nil }
            guard let ownedCryptoId = ObvCryptoId(splits[1]) else { assertionFailure(); return nil }
            self = .invitations(ownedCryptoId: ownedCryptoId)
        case .contactGroupDetails:
            guard splits.count == 3 else { assertionFailure(); return nil }
            guard let ownedCryptoId = ObvCryptoId(splits[1]) else { assertionFailure(); return nil }
            guard let objectPermanentID = ObvManagedObjectPermanentID<DisplayedContactGroup>(splits[2]) else { assertionFailure(); return nil }
            self = .contactGroupDetails(ownedCryptoId: ownedCryptoId, objectPermanentID: objectPermanentID)
        case .contactIdentityDetails:
            guard splits.count == 3 else { assertionFailure(); return nil }
            guard let ownedCryptoId = ObvCryptoId(splits[1]) else { assertionFailure(); return nil }
            guard let objectPermanentID = ObvManagedObjectPermanentID<PersistedObvContactIdentity>(splits[2]) else { assertionFailure(); return nil }
            self = .contactIdentityDetails(ownedCryptoId: ownedCryptoId, objectPermanentID: objectPermanentID)
        case .airDrop:
            guard splits.count == 2 else { assertionFailure(); return nil }
            guard let fileURL = URL(string: splits[1]) else { assertionFailure(); return nil }
            self = .airDrop(fileURL: fileURL)
        case .qrCodeScan:
            self = .qrCodeScan
        case .myId:
            guard splits.count == 2 else { assertionFailure(); return nil }
            guard let ownedCryptoId = ObvCryptoId(splits[1]) else { assertionFailure(); return nil }
            self = .myId(ownedCryptoId: ownedCryptoId)
        case .requestRecordPermission:
            self = .requestRecordPermission
        case .settings:
            self = .settings
        case .backupSettings:
            self = .backupSettings
        case .privacySettings:
            self = .privacySettings
        case .message:
            guard splits.count == 3 else { assertionFailure(); return nil }
            guard let ownedCryptoId = ObvCryptoId(splits[1]) else { assertionFailure(); return nil }
            guard let objectPermanentID = ObvManagedObjectPermanentID<PersistedMessage>(splits[2]) else { assertionFailure(); return nil }
            self = .message(ownedCryptoId: ownedCryptoId, objectPermanentID: objectPermanentID)
        case .allGroups:
            guard splits.count == 2 else { assertionFailure(); return nil }
            guard let ownedCryptoId = ObvCryptoId(splits[1]) else { assertionFailure(); return nil }
            self = .allGroups(ownedCryptoId: ownedCryptoId)
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
        case .privacySettings: return .privacySettings
        case .message: return .message
        case .allGroups: return .allGroups
        }
    }

    /// A deeplink usually concerns a particular owned identity. This variable returns the appropriate owned identity if there is one.
    ///
    /// This is typically used when navigating to a deep link: before performing the navigation, we switch the current owned identity to the one returned here.
    var ownedCryptoId: ObvCryptoId? {
        switch self {
        case .latestDiscussions(let ownedCryptoId):
            return ownedCryptoId
        case .singleDiscussion(ownedCryptoId: let ownedCryptoId, objectPermanentID: _):
            return ownedCryptoId
        case .invitations(let ownedCryptoId):
            return ownedCryptoId
        case .contactGroupDetails(let ownedCryptoId, _):
            return ownedCryptoId
        case .contactIdentityDetails(let ownedCryptoId, _):
            return ownedCryptoId
        case .airDrop:
            return nil
        case .qrCodeScan:
            return nil
        case .myId(let ownedCryptoId):
            return ownedCryptoId
        case .requestRecordPermission:
            return nil
        case .settings:
            return nil
        case .backupSettings:
            return nil
        case .privacySettings:
            return nil
        case .message(let ownedCryptoId, _):
            return ownedCryptoId
        case .allGroups(let ownedCryptoId):
            return ownedCryptoId
        }
    }
    
    
}

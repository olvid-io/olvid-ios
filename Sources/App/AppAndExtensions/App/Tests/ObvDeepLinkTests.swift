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
  

import XCTest
import OlvidUtils
import ObvTypes
import ObvEngine

class ObvDeepLinkTests: XCTestCase {

    private static let identityAsURL = URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!

    private static let cryptoId = ObvURLIdentity(urlRepresentation: identityAsURL)!.cryptoId

    func _testLink(link: ObvDeepLink) {
        let description = link.description
        let linkFromDescription = ObvDeepLink(description)
        
        XCTAssertNotNil(linkFromDescription)
        XCTAssertEqual(link, linkFromDescription, "Links are not equals")
    }

    func testLinks() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory

        for host in ObvDeepLinkHost.allCases {
            switch host {
            case .latestDiscussions:
                _testLink(link: ObvDeepLink.latestDiscussions(ownedCryptoId: nil))
                _testLink(link: ObvDeepLink.latestDiscussions(ownedCryptoId: Self.cryptoId))
            case .singleDiscussion:
                let permanentID = ObvManagedObjectPermanentID<PersistedDiscussion>(entityName: "PersistedDiscussion", uuid: UUID())
                _testLink(link: ObvDeepLink.singleDiscussion(ownedCryptoId: Self.cryptoId, objectPermanentID: permanentID))
            case .invitations:
                _testLink(link: ObvDeepLink.invitations)
            case .contactGroupDetails:
                _testLink(link: ObvDeepLink.contactGroupDetails(objectPermanentID: ObvManagedObjectPermanentID<DisplayedContactGroup>(entityName: "DisplayedContactGroup", uuid: UUID())))
            case .contactIdentityDetails:
                _testLink(link: ObvDeepLink.contactIdentityDetails(objectPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>(entityName: "PersistedObvContactIdentity", uuid: UUID())))
            case .airDrop:
                let url = URL(string: temporaryDirectory.appendingPathComponent("ObvDeepLinkTests.txt", isDirectory: false).path)!
                _testLink(link: ObvDeepLink.airDrop(fileURL: url))
            case .qrCodeScan:
                _testLink(link: ObvDeepLink.qrCodeScan)
            case .myId:
                _testLink(link: ObvDeepLink.myId(objectPermanentID: ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>(entityName: "PersistedObvOwnedIdentity", uuid: UUID())))
            case .requestRecordPermission:
                _testLink(link: ObvDeepLink.requestRecordPermission)
            case .settings:
                _testLink(link: ObvDeepLink.settings)
            case .backupSettings:
                _testLink(link: ObvDeepLink.backupSettings)
            case .message:
                _testLink(link: ObvDeepLink.message(objectPermanentID: ObvManagedObjectPermanentID<PersistedMessage>(entityName: "PersistedMessage", uuid: UUID())))
            case .allGroups:
                _testLink(link: ObvDeepLink.allGroups)
            }
        }
    }

}

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

class ObvDeepLinkTests: XCTestCase {

    func _testLink(link: ObvDeepLink) {
        let url = link.url
        let linkFromUrl = ObvDeepLink(url: url)

        XCTAssertNotNil(linkFromUrl)
        XCTAssertEqual(link, linkFromUrl, "Links are not equals")
    }

    func testLinks() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let url = temporaryDirectory.appendingPathComponent("ObvDeepLinkTests", isDirectory: true)

        for host in ObvDeepLinkHost.allCases {
            switch host {
            case .latestDiscussions:
                _testLink(link: ObvDeepLink.latestDiscussions)
            case .singleDiscussion:
                _testLink(link: ObvDeepLink.singleDiscussion(discussionObjectURI: url))
            case .invitations:
                _testLink(link: ObvDeepLink.invitations)
            case .contactGroupDetails:
                _testLink(link: ObvDeepLink.contactGroupDetails(displayedContactGroupURI: url))
            case .contactIdentityDetails:
                _testLink(link: ObvDeepLink.contactIdentityDetails(contactIdentityURI: url))
            case .airDrop:
                _testLink(link: ObvDeepLink.airDrop(fileURL: url))
            case .qrCodeScan:
                _testLink(link: ObvDeepLink.qrCodeScan)
            case .myId:
                _testLink(link: ObvDeepLink.myId(ownedIdentityURI: url))
            case .requestRecordPermission:
                _testLink(link: ObvDeepLink.requestRecordPermission)
            case .settings:
                _testLink(link: ObvDeepLink.settings)
            case .backupSettings:
                _testLink(link: ObvDeepLink.backupSettings)
            case .message:
                _testLink(link: ObvDeepLink.message(messageObjectURI: url))
            }
        }
    }

}

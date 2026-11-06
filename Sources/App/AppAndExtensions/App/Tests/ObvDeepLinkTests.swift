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
  

import XCTest
import OlvidUtils
import ObvTypes
import ObvCrypto
import ObvAppTypes
import ObvUICoreData


/// Round-trips every ``ObvDeepLink`` through its `description` and back.
///
/// The switch below is exhaustive over ``ObvDeepLinkHost`` deliberately: adding a host without adding its link here
/// stops compiling, which is the only thing that keeps this test honest as the type grows. That is also how it was found
/// to be six cases and four signatures out of date — it had not been in any target since it was written, so nothing ever
/// told anybody. See `Target.makeAppUnitTestsTarget(name:sourcesUnderTest:dependencies:)`.
final class ObvDeepLinkTests: XCTestCase {

    private static let identitiesAsURLs: [URL] = [
        URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!,
        URL(string: "https://invitation.olvid.io/#AwAAAHAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAVZx8aqikpCe4h3ayCwgKBf-2nDwz-a6vxUo3-ep5azkBUjimUf3J--GXI8WTc2NIysQbw5fxmsY9TpjnDsZMW-AAAAAACEJvYiBXb3Jr")!,
    ]

    private static let cryptoIds = identitiesAsURLs.map { ObvURLIdentity(urlRepresentation: $0)!.cryptoId }
    private static var ownedCryptoId: ObvCryptoId { cryptoIds[0] }
    private static var contactCryptoId: ObvCryptoId { cryptoIds[1] }

    private static var contactIdentifier: ObvContactIdentifier {
        .init(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
    }

    private static var groupV2Identifier: ObvGroupV2Identifier {
        .init(ownedCryptoId: ownedCryptoId,
              identifier: .init(groupUID: UID.zero, serverURL: URL(string: "https://test.olvid.io")!, category: .server))
    }

    private func assertRoundTrips(_ link: ObvDeepLink, file: StaticString = #filePath, line: UInt = #line) {
        let recovered = ObvDeepLink(link.description)
        XCTAssertNotNil(recovered, "\(link.description) did not parse back", file: file, line: line)
        XCTAssertEqual(link, recovered, "\(link.description) did not survive the round trip", file: file, line: line)
    }

    func testEveryDeepLinkSurvivesItsDescription() throws {

        for host in ObvDeepLinkHost.allCases {
            switch host {

            case .latestDiscussions:
                assertRoundTrips(.latestDiscussions(ownedCryptoId: nil))
                assertRoundTrips(.latestDiscussions(ownedCryptoId: Self.ownedCryptoId))

            case .singleDiscussion:
                assertRoundTrips(.singleDiscussion(discussionIdentifier: .oneToOne(id: Self.contactIdentifier)))
                assertRoundTrips(.singleDiscussion(discussionIdentifier: .groupV2(id: Self.groupV2Identifier)))

            case .invitations:
                assertRoundTrips(.invitations(ownedCryptoId: Self.ownedCryptoId))

            case .groupV1Details:
                /// Built from a description rather than from `init(entityName:uuid:)`, which is internal to ObvUICoreData.
                let entityName = "DisplayedContactGroup"
                let permanentID = try XCTUnwrap(ObvManagedObjectPermanentID<DisplayedContactGroup>("\(entityName)/\(UUID().uuidString)",
                                                                                                  expectedEntityName: entityName))
                assertRoundTrips(.groupV1Details(ownedCryptoId: Self.ownedCryptoId, objectPermanentID: permanentID))

            case .groupV2Details:
                assertRoundTrips(.groupV2Details(groupIdentifier: Self.groupV2Identifier))

            case .contactIdentityDetails:
                assertRoundTrips(.contactIdentityDetails(contactIdentifier: Self.contactIdentifier))

            case .airDrop:
                let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("ObvDeepLinkTests.txt", isDirectory: false)
                assertRoundTrips(.airDrop(fileURL: fileURL))

            case .qrCodeScan:
                assertRoundTrips(.qrCodeScan)

            case .myId:
                assertRoundTrips(.myId(ownedCryptoId: Self.ownedCryptoId))

            case .requestRecordPermission:
                assertRoundTrips(.requestRecordPermission)

            case .settings:
                assertRoundTrips(.settings)

            case .backupSettings:
                assertRoundTrips(.backupSettings)

            case .voipSettings:
                assertRoundTrips(.voipSettings)

            case .discussionsSettings:
                assertRoundTrips(.discussionsSettings)

            case .privacySettings:
                assertRoundTrips(.privacySettings)

            case .interfaceSettings:
                assertRoundTrips(.interfaceSettings)

            case .storageManagementSettings:
                assertRoundTrips(.storageManagementSettings)

            case .message:
                let discussionIdentifier = ObvDiscussionIdentifier.oneToOne(id: Self.contactIdentifier)
                assertRoundTrips(.message(.sent(discussionIdentifier: discussionIdentifier,
                                                senderThreadIdentifier: UUID(),
                                                senderSequenceNumber: 42)))
                assertRoundTrips(.message(.received(discussionIdentifier: discussionIdentifier,
                                                    senderIdentifier: Self.contactCryptoId.getIdentity(),
                                                    senderThreadIdentifier: UUID(),
                                                    senderSequenceNumber: 42)))

            case .allGroups:
                assertRoundTrips(.allGroups(ownedCryptoId: Self.ownedCryptoId))

            case .olvidCallView:
                assertRoundTrips(.olvidCallView)

            case .groupCreation:
                assertRoundTrips(.groupCreation)

            case .webRTCHistoryTransferConfirmation:
                let sourceDeviceIdentifier = ObvOwnedDeviceIdentifier(ownedCryptoId: Self.ownedCryptoId, deviceUID: UID.zero)
                assertRoundTrips(.webRTCHistoryTransferConfirmation(sourceDeviceIdentifier: sourceDeviceIdentifier,
                                                                    transferId: "a-transfer-id"))

            }
        }

    }

}

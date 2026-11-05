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
import ObvCrypto
@testable import ObvTypes

final class ObvTypesTests: XCTestCase {
    
    private static let identitiesAsURLs: [URL] = [
        URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!,
        URL(string: "https://invitation.olvid.io/#AwAAAHAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAVZx8aqikpCe4h3ayCwgKBf-2nDwz-a6vxUo3-ep5azkBUjimUf3J--GXI8WTc2NIysQbw5fxmsY9TpjnDsZMW-AAAAAACEJvYiBXb3Jr")!,
    ]
    
    private static let cryptoIds = identitiesAsURLs.map({ ObvURLIdentity(urlRepresentation: $0)!.cryptoId })

    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // MARK: How long the requests have been unable to reach the server

    private static let aListingTiming: (TimeInterval, ObvServerRequestTiming.Outcome) -> ObvServerRequestTiming = { secondsAgo, outcome in
        ObvServerRequestTiming(date: Date(timeIntervalSince1970: 10_000 - secondsAgo),
                               request: .downloadMessagesAndListAttachments,
                               trigger: .theAppAskedForIt,
                               outcome: outcome,
                               durationOfTheServerSessionTokenRequest: 0,
                               durationOfTheRequest: 0,
                               durationOfTheSaveAndProcess: nil,
                               numberOfMessagesReturned: nil)
    }

    /// `now`, in the frame the helper above counts back from.
    private static let timingsNow = Date(timeIntervalSince1970: 10_000)

    private func howLongUnable(_ timings: [ObvServerRequestTiming], sinceSecondsAgo: TimeInterval = 1_000) -> TimeInterval? {
        ObvServerRequestTiming.howLongTheRequestsHaveBeenUnableToReachTheServer(
            in: timings,
            since: Self.timingsNow.addingTimeInterval(-sinceSecondsAgo),
            now: Self.timingsNow)
    }

    /// Nothing recorded is *nothing known*, which must read as leave to carry on rather than as trouble — it is the state every run is in before its first
    /// attempt comes back, so anything else would stop every run.
    func testNoTimingsMeansNothingIsKnown() {
        XCTAssertNil(howLongUnable([]))
    }

    /// A request that reached the server, whatever it answered. A refusal is the server speaking, so only `couldNotPerformTheRequest` is a failure to reach.
    func testAnAnswerOfAnyKindCountsAsReachingTheServer() {
        for outcome: ObvServerRequestTiming.Outcome in [.ok, .listingTruncated, .invalidSession, .deviceIsNotRegistered, .generalError, .couldNotSaveWhatCameBack] {
            XCTAssertNil(howLongUnable([Self.aListingTiming(10, outcome)]), "\(outcome.rawValue) should count as having reached the server")
        }
        XCTAssertEqual(howLongUnable([Self.aListingTiming(10, .couldNotPerformTheRequest)]), 10)
    }

    /// **Measured from the first failure of the run, not from the last attempt.** By the time a listing has failed a few times its back-off is minutes long,
    /// so the age of the most recent attempt understates the trouble by exactly the interval nobody has waited out yet.
    func testTheDurationIsMeasuredFromTheStartOfTheUnbrokenRunOfFailures() {
        let timings = [Self.aListingTiming(300, .couldNotPerformTheRequest),
                       Self.aListingTiming(180, .couldNotPerformTheRequest),
                       Self.aListingTiming(60, .couldNotPerformTheRequest)]
        XCTAssertEqual(howLongUnable(timings, sinceSecondsAgo: 1_000), 300)
    }

    /// A success in the middle breaks the run: what matters is how long the *current* trouble has lasted, not how many failures there have ever been.
    func testASuccessBreaksTheRun() {
        let timings = [Self.aListingTiming(300, .couldNotPerformTheRequest),
                       Self.aListingTiming(180, .ok),
                       Self.aListingTiming(60, .couldNotPerformTheRequest)]
        XCTAssertEqual(howLongUnable(timings, sinceSecondsAgo: 1_000), 60)
    }

    /// The most recent timing decides whether there is any trouble at all: failures with a success after them are over.
    func testFailuresFollowedByASuccessAreNotTrouble() {
        let timings = [Self.aListingTiming(300, .couldNotPerformTheRequest),
                       Self.aListingTiming(180, .couldNotPerformTheRequest),
                       Self.aListingTiming(60, .ok)]
        XCTAssertNil(howLongUnable(timings, sinceSecondsAgo: 1_000))
    }

    /// **A stale episode is not a current one.** A device offline yesterday still holds those timings, and counting them would condemn a request that has
    /// not yet had its first attempt come back.
    func testFailuresBeforeTheCutOffAreIgnored() {
        let timings = [Self.aListingTiming(5_000, .couldNotPerformTheRequest),
                       Self.aListingTiming(4_000, .couldNotPerformTheRequest)]
        XCTAssertNil(howLongUnable(timings, sinceSecondsAgo: 1_000))
    }

    /// The cut-off truncates the run rather than discarding it: only the part of the trouble this caller is entitled to count is measured.
    func testTheDurationIsMeasuredFromTheCutOffWhenTheRunStartedBeforeIt() {
        let timings = [Self.aListingTiming(5_000, .couldNotPerformTheRequest),
                       Self.aListingTiming(500, .couldNotPerformTheRequest)]
        XCTAssertEqual(howLongUnable(timings, sinceSecondsAgo: 1_000), 500)
    }

    /// Order is not trusted: these are recorded without waiting for them to land, so two made close together can be stored the other way round.
    func testTimingsAreSortedBeforeBeingRead() {
        let timings = [Self.aListingTiming(60, .couldNotPerformTheRequest),
                       Self.aListingTiming(300, .couldNotPerformTheRequest),
                       Self.aListingTiming(180, .couldNotPerformTheRequest)]
        XCTAssertEqual(howLongUnable(timings, sinceSecondsAgo: 1_000), 300)
    }


    func testUID() {
        let uid1 = UID.init(uid: Data(repeating: 0x12, count: 32))
        let uid2 = UID.init(uid: Data(repeating: 0x12, count: 32))
        XCTAssertEqual(uid1!.hashValue, uid2!.hashValue)
    }
    
    
    func testObvContactIdentifierForObvCodable() {
        
        let obvContactIdentifier = ObvContactIdentifier(contactCryptoId: Self.cryptoIds[0], ownedCryptoId: Self.cryptoIds[1])
        let encoded = obvContactIdentifier.obvEncode()
        let recovered = ObvContactIdentifier(encoded)
        XCTAssertEqual(obvContactIdentifier, recovered)
        
    }
    
    
    func testObvContactIdentifierForLosslessStringConvertible() {
        
        let obvContactIdentifier = ObvContactIdentifier(contactCryptoId: Self.cryptoIds[0], ownedCryptoId: Self.cryptoIds[1])
        let description = obvContactIdentifier.description
        let recovered = ObvContactIdentifier(description)
        XCTAssertEqual(obvContactIdentifier, recovered)
        
    }
    
    
    func testObvKeycloakConfigurationCoding() {
        
        do {
            let keycloakServerURL = URL(string: "https://olvid.io/test")!
            let clientId = "clientId"
            let clientSecret = "clientSecret"
            
            let keycloakConfiguration = ObvKeycloakConfiguration(
                keycloakServerURL: keycloakServerURL,
                clientId: clientId,
                clientSecret: clientSecret)
            
            let encoded = try keycloakConfiguration.jsonEncode()
            
            let decodeKeycloakConfiguration = try ObvKeycloakConfiguration.jsonDecode(encoded)
            
            XCTAssert(keycloakConfiguration == decodeKeycloakConfiguration)
            XCTAssert(decodeKeycloakConfiguration.keycloakServerURL == keycloakServerURL)
            XCTAssert(decodeKeycloakConfiguration.clientId == clientId)
            XCTAssert(decodeKeycloakConfiguration.clientSecret == clientSecret)
            
        } catch {
            XCTFail()
        }

    }


    /// The numeric codes of ``OwnedIdentityTransferError`` are shown to the user on the transfer failure screen and sent to the support team
    /// by email: they must never change. They are pinned by the `CustomNSError` conformance: without it, the code is the automatic enum tag,
    /// which numbers cases with an associated value before the other ones (adding an associated value to a case silently shifts the other codes).
    func testOwnedIdentityTransferErrorCodesAreStable() {

        XCTAssertEqual((OwnedIdentityTransferError.couldNotGenerateObvChannelServerQueryMessageToSend as NSError).code, 0)
        XCTAssertEqual((OwnedIdentityTransferError.couldNotDecodeSyncSnapshot as NSError).code, 1)
        XCTAssertEqual((OwnedIdentityTransferError.decryptionFailed as NSError).code, 2)
        XCTAssertEqual((OwnedIdentityTransferError.decodingFailed as NSError).code, 3)
        XCTAssertEqual((OwnedIdentityTransferError.incorrectSAS as NSError).code, 4)
        XCTAssertEqual((OwnedIdentityTransferError.serverRequestFailed as NSError).code, 5)
        XCTAssertEqual((OwnedIdentityTransferError.connectionIdsDoNotMatch as NSError).code, 6)
        XCTAssertEqual((OwnedIdentityTransferError.tryingToTransferAnOwnedIdentityThatAlreadyExistsOnTargetDevice(ownedCryptoId: Self.cryptoIds[0]) as NSError).code, 7)
        XCTAssertEqual((OwnedIdentityTransferError.couldNotOpenCommitment as NSError).code, 8)
        XCTAssertEqual((OwnedIdentityTransferError.couldNotComputeSeed as NSError).code, 9)
        XCTAssertEqual((OwnedIdentityTransferError.couldNotEncryptPayload as NSError).code, 10)
        XCTAssertEqual((OwnedIdentityTransferError.couldNotEncryptDecommitment as NSError).code, 11)
        XCTAssertEqual((OwnedIdentityTransferError.couldNotObtainKeycloakConfiguration as NSError).code, 12)

        XCTAssertEqual((OwnedIdentityTransferError.serverRequestFailed as NSError).domain, "ObvTypes.OwnedIdentityTransferError")

    }

}

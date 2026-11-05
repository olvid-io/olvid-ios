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
@testable import ObvTypes


/// The two pieces of the new diagnostics that are pure functions, and are therefore the two where a mistake would be silent.
///
/// The queries around them cannot be reached from a hostless test target — they need a store, a device and a backlog — but these two can be, and they are
/// where the judgement is: what counts as a shared-settings payload, and what order the protocol figures come out in.
final class ObvEngineDiagnosticsFiguresTests: XCTestCase {

    private func payload(_ string: String) -> Data {
        Data(string.utf8)
    }


    // MARK: Recognising a discussion-shared-settings payload

    /// A payload written by the *Windows* serialiser and taken off a real device's store.
    func testTheRealWindowsPayloadIsRecognised() {
        let real = #"{"settings":{"version":1,"exp":{"vis":157766400},"gid2":"AwAAAFIAAAAAIP7amyLP"}}"#
        XCTAssertTrue(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload(real)))
    }

    /// **The trap the doc warns about.** A substring test would match this, and it is an ordinary text message.
    func testAMessageInWhichSomebodyTypedTheWordIsNotOne() {
        let text = #"{"message":{"body":"have a look at the settings"}}"#
        XCTAssertFalse(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload(text)))
    }

    /// **A settings item carrying a companion is still a settings item.** This was asserted the other way round, on the reasoning that every
    /// `PersistedItemJSON` initialiser sets exactly one field — which `init(messageJSON:returnReceiptJSON:)` disproves. A serialiser we do not control
    /// pairing a return receipt with a shared configuration is well within the format, and dropping those would understate the backlog.
    func testAnObjectCarryingACompanionKeyIsStillOne() {
        let withAReturnReceipt = #"{"settings":{"version":1},"rr":{"nonce":"AA=="}}"#
        XCTAssertTrue(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload(withAReturnReceipt)))
    }

    /// The other item kinds are still refused, which is what the parse is for: a payload that merely *mentions* our key is not one of ours.
    func testAnotherItemKindIsStillRefused() {
        XCTAssertFalse(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload(#"{"qss":{"settings":1}}"#)))
        XCTAssertFalse(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload(#"{"upm":{"body":"settings"}}"#)))
    }

    /// Whitespace is not ours to choose — these bytes come from another implementation. **Key *order* is a known narrowing**: the scan requires ``jsonKey``
    /// first, so `{"rr":…,"settings":…}` would be missed. Nothing observed writes that, and widening it means giving up the anchor that makes this cheap.
    func testTheKeyIsFoundWhateverTheSerialiserDidWithWhitespace() {
        XCTAssertTrue(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload(#"  { "settings" : {"version":1} }"#)))
        XCTAssertTrue(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload("\n\t{\"settings\":{}}")))
    }

    /// Nothing here may trap: these payloads are read in their tens of thousands, and one unreadable row must cost that row and no more.
    func testRubbishIsRefusedRatherThanTrapping() {
        XCTAssertFalse(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(Data()))
        XCTAssertFalse(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload(#"["settings"]"#)))
        XCTAssertFalse(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload("not json at all")))
        XCTAssertFalse(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(Data([0xff, 0xfe, 0x00])))
        XCTAssertFalse(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload(#"{"settings""#)))       // the colon never arrives
        XCTAssertFalse(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload(#"{"settings"}"#)))      // nor is it what arrives
    }

    /// **A truncated settings item is counted.** It was refused only because a `JSONSerialization` pass used to stand here. A payload opening
    /// `{"settings":` was meant to be one of these, and a figure sizing a backlog should say so.
    func testATruncatedSettingsItemIsStillCounted() {
        XCTAssertTrue(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload(#"{"settings":"#)))
    }

    /// The three places JSON allows whitespace before the colon, and the two places it is not whitespace but part of a different key.
    func testWhitespaceIsToleratedWhereverJSONAllowsItAndNowhereElse() {
        XCTAssertTrue(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload(#"{"settings":{}}"#)))      // none at all
        XCTAssertTrue(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload(#" {"settings":{}}"#)))     // before the brace
        XCTAssertTrue(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload(#"{ "settings":{}}"#)))     // after the brace
        XCTAssertTrue(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload(#"{"settings" :{}}"#)))     // before the colon
        XCTAssertTrue(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload("{\n\t\"settings\"\r\n:{}}"))) // and the other three bytes
        // Inside the quotes is not whitespace-between-tokens, it is a different key.
        XCTAssertFalse(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload(#"{" settings":{}}"#)))
        XCTAssertFalse(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload(#"{"settings ":{}}"#)))
    }

    /// A key that merely *starts* with ours is a different key.
    func testAKeyThatOnlyBeginsLikeOursIsNotOne() {
        XCTAssertFalse(ObvDiscussionSharedSettingsPayload.isADiscussionSharedSettingsItem(payload(#"{"settingsOfSomethingElse":{}}"#)))
    }


    // MARK: The order the protocol figures come out in

    private func counts(instances: [ObvCryptoProtocolKind: Int] = [:], unrecognisedInstances: Int = 0, messages: [ObvCryptoProtocolKind: Int] = [:], unrecognisedMessages: Int = 0) -> ObvProtocolCounts {
        .init(protocolInstancesPerKind: instances,
              protocolInstancesWithAnUnrecognisedKind: unrecognisedInstances,
              receivedProtocolMessagesPerKind: messages,
              receivedProtocolMessagesWithAnUnrecognisedKind: unrecognisedMessages)
    }

    /// A total first in each of the two sections, so that a protocol absent from the list reads as nought rather than as a figure nobody asked for.
    func testEachSectionOpensWithItsTotal() {
        let figures = ObvEngineDiagnostic.figures(for: counts(instances: [.groupV2: 3, .fullRatchet: 1], messages: [.groupV2: 2]))
        XCTAssertEqual(figures.first?.section, .protocolInstances)
        XCTAssertEqual(figures.first?.label, "Total")
        XCTAssertEqual(figures.first?.value, "4")
        let firstMessageFigure = figures.first { $0.section == .protocolMessages }
        XCTAssertEqual(firstMessageFigure?.label, "Total")
        XCTAssertEqual(firstMessageFigure?.value, "2")
    }

    /// Both sections are emitted even when there is nothing in them: a section that vanished could not be told apart from a measurement that never ran.
    func testAnEmptyProtocolStoreStillReportsBothTotals() {
        let figures = ObvEngineDiagnostic.figures(for: counts())
        XCTAssertEqual(figures.count, 2)
        XCTAssertEqual(figures.map(\.section), [.protocolInstances, .protocolMessages])
        XCTAssertEqual(figures.map(\.value), ["0", "0"])
    }

    func testProtocolsWithNothingToReportAreLeftOut() {
        let figures = ObvEngineDiagnostic.figures(for: counts(instances: [.groupV2: 3, .fullRatchet: 0]))
        XCTAssertFalse(figures.contains { $0.label == ObvCryptoProtocolKind.fullRatchet.rawValue })
        XCTAssertTrue(figures.contains { $0.label == ObvCryptoProtocolKind.groupV2.rawValue && $0.value == "3" })
    }

    /// The rows follow the enum's own order, so two readings of the same device can be compared line by line.
    func testTheRowsFollowTheDeclaredOrderOfTheProtocols() {
        let figures = ObvEngineDiagnostic.figures(for: counts(instances: [.groupV2: 1, .contactDeviceDiscovery: 1, .synchronization: 1]))
        let labels = figures.filter { $0.section == .protocolInstances && $0.label != "Total" }.map(\.label)
        XCTAssertEqual(labels, [ObvCryptoProtocolKind.contactDeviceDiscovery.rawValue,
                                ObvCryptoProtocolKind.groupV2.rawValue,
                                ObvCryptoProtocolKind.synchronization.rawValue])
    }

    /// Rows we could not name are counted into the total, so the parts and the total still reconcile — and are shown only when there are any, a nought there
    /// inviting a question about a case that does not arise.
    func testUnrecognisedRowsAreCountedInTheTotalAndShownOnlyWhenPresent() {
        let withNone = ObvEngineDiagnostic.figures(for: counts(instances: [.groupV2: 3]))
        XCTAssertFalse(withNone.contains { $0.label == "Unrecognised protocol id" })

        let withSome = ObvEngineDiagnostic.figures(for: counts(instances: [.groupV2: 3], unrecognisedInstances: 2))
        XCTAssertEqual(withSome.first?.value, "5")
        XCTAssertEqual(withSome.last(where: { $0.section == .protocolInstances })?.label, "Unrecognised protocol id")
    }


    // MARK: The shared-settings rows

    /// The three states are a partition of the count above them, so a state that is empty is written out rather than dropped — unlike the figures that go
    /// through the renderer shared with `Outcomes` and `By status`.
    func testTheStateBreakdownKeepsItsZeros() {
        let figure = ObvEngineDiagnostic.discussionSharedSettingsPerState(awaitingTheApp: 81_202, onHold: 358, markedForDeletion: 0)
        XCTAssertEqual(figure.section, .discussionSharedSettings)
        XCTAssertEqual(figure.value, "awaiting the app 81202, on hold 358, marked for deletion 0")
    }

    /// Within one section every label is distinct: the screen identifies its rows by label, so two figures sharing one would collapse into a single row.
    func testLabelsAreUniqueWithinASection() {
        let everyKind = Dictionary(uniqueKeysWithValues: ObvCryptoProtocolKind.allCases.map { ($0, 1) })
        let figures = ObvEngineDiagnostic.figures(for: counts(instances: everyKind, unrecognisedInstances: 1, messages: everyKind, unrecognisedMessages: 1))
            + [.numberOfInboxMessagesThatAreDiscussionSharedSettings(1),
               .numberOfDecryptedPayloadsExamined(1),
               .discussionSharedSettingsPerState(awaitingTheApp: 1, onHold: 0, markedForDeletion: 0),
               .ageOfTheOldestDiscussionSharedSettingsMessage(nil)]
        for section in Set(figures.map(\.section)) {
            let labels = figures.filter { $0.section == section }.map(\.label)
            XCTAssertEqual(labels.count, Set(labels).count, "Two figures share a label in the '\(section.rawValue)' section")
        }
    }

}

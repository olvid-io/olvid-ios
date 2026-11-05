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

import Foundation


/// The status of an attachment in the engine's inbox, as far as anything outside the engine needs to know.
///
/// A mirror of the engine's own status, kept here because this is the only way for a count broken down by status to cross the boundary. `ObvAttachment.Status`
/// cannot serve: its cases carry payloads, so it cannot key a dictionary.
public enum ObvInboxAttachmentStatus: String, Sendable, Codable, CaseIterable {
    case paused
    case resumeRequested
    case downloaded
    case cancelledByServer
    case markedForDeletion
}


/// What the engine can say about the state of its own inbox.
///
/// One case per figure, and each case knows its own label and how to render its value, so that nothing outside this file ever switches over it: a screen
/// appends rows as they arrive and a report joins the same rows into text. Adding a figure is therefore one case and one line of the descriptor below, in
/// one file, which matters because the list of figures is expected to keep changing.
///
/// **The order in which these are emitted is the canonical order.** The engine computes them one at a time, in a fixed order, cheapest first — so a screen
/// that appends in arrival order and a report that joins in arrival order agree by construction, and neither has to sort. Anything that starts computing
/// these concurrently breaks that, and would have to give the cases an explicit rank instead.
///
/// **Two managers contribute to that one order**: the fetch manager streams the inbox, and ``ObvEngine/getAsyncStreamOfEngineDiagnostics()`` appends the
/// protocol manager's figures after it, sequentially — which is what keeps the paragraph above true.
public enum ObvEngineDiagnostic: Sendable, Equatable {

    // Context

    case numberOfProfiles(Int)
    case estimatedClockSkewAgainstTheServer(TimeInterval?)

    // Recent listings. The engine keeps a bounded record of these; see `ObvServerRequestTiming`.

    case numberOfRecordedListings(Int)
    case durationsOfTheListingRequest(median: TimeInterval?, ninetieth: TimeInterval?, worst: TimeInterval?)
    case durationsOfTheSaveAndProcess(median: TimeInterval?, ninetieth: TimeInterval?, worst: TimeInterval?)
    case outcomesOfTheRecordedListings([ObvServerRequestTiming.Outcome: Int])
    case slowestRecordedListings([ObvServerRequestTiming])
    case mostRecentRecordedListings([ObvServerRequestTiming])
    case timeSinceTheLastCompletedListing(TimeInterval?)
    case timeSinceTheLastUntruncatedListing(TimeInterval?)

    // The WebSocket, counted since this process started. Nought again at the next launch, which the labels say so that a small number is not read as a
    // quiet socket when it is really a recent launch.

    case numberOfReturnReceiptsReceivedOnTheWebSocket(Int)
    case numberOfDeleteReturnReceiptRequestsSent(Int)

    // The inbox, by state

    case numberOfInboxMessages(Int)
    case numberOfInboxMessagesNotYetDecrypted(Int)
    case numberOfInboxMessagesAwaitingTheApp(Int)
    case numberOfInboxMessagesOnHold(Int)
    case numberOfInboxMessagesMarkedForDeletion(Int)
    case numberOfInboxMessagesAwaitingAContact(Int)
    case numberOfInboxMessagesMarkedAsListedOnTheServer(Int)
    case numberOfInboxMessagesDeletedFromTheServer(Int)
    case numberOfInboxMessagesWithAtLeastOneAttachment(Int)

    /// How many rows belong to a profile that is no longer active.
    ///
    /// **Here so that the parts and the total can be reconciled.** The four counts of *work* above are restricted to the active profiles — nothing lists,
    /// decrypts, marks or sweeps a message of an inactive one, so counting one as work claims something will move it — while the total counts every row.
    /// Without this figure the two simply disagree, which is what the Inbox-maintenance screen beside this one used to look like.
    case numberOfInboxMessagesBelongingToAnInactiveProfile(Int)

    // Messages whose attachments the reader has not asked for. Ordinary, and the largest population on a device with automatic downloads off — which is why
    // it is broken down rather than reported as one number.

    case numberOfMessagesWaitingForAManualDownload(Int)
    case attachmentsWaitingForAManualDownload(perStatus: [ObvInboxAttachmentStatus: Int])
    case bytesWaitingForAManualDownload(Int64)
    case ageOfTheOldestMessageWaitingForAManualDownload(TimeInterval?)

    // Ages. A large count of recent messages is a device catching up; the same count three weeks old is a device that is stuck.

    case ageOfTheOldestInboxMessageNotYetDecrypted(TimeInterval?)
    case ageOfTheOldestInboxMessageAwaitingTheApp(TimeInterval?)
    case ageOfTheOldestInboxMessageOnHold(TimeInterval?)
    case timeSpentOnTheServerBeforeBeingListed(median: TimeInterval?, worst: TimeInterval?)

    // Attachments

    case numberOfInboxAttachments(perStatus: [ObvInboxAttachmentStatus: Int])
    case numberOfUnmarkedAttachmentsOnAMessageMarkedForDeletion(Int)

    // Disk. An inbox holding no directories while the database holds live messages with attachments is worth seeing.

    case stateOfTheInboxOnDisk(StateOfTheInboxOnDisk)
    case messageDirectoriesOnDisk(onDisk: Int, expected: Int)
    /// The engine's own store, and whatever write-ahead log sits beside it. Nil when we could not measure it rather than zero, which no database is.
    case sizeOfTheEngineDatabase(Int64?)

    // Discussion shared settings sitting in the inbox. A Windows version sends far too many of these, and until now nothing on a device could tell us whether
    // a reader's backlog was made of them or of ordinary traffic. Recognised by the *shape* of the decrypted payload — see `ObvDiscussionSharedSettingsPayload`.

    case numberOfInboxMessagesThatAreDiscussionSharedSettings(Int)
    /// How many decrypted payloads were read in order to find them. **The denominator**: a count of five hundred means one thing out of five hundred and quite
    /// another out of eighty thousand, and the figure above cannot be read without it.
    case numberOfDecryptedPayloadsExamined(Int)
    /// The three states, which here really are a partition of the messages counted above — unlike the inbox populations further up, where they are not.
    case discussionSharedSettingsPerState(awaitingTheApp: Int, onHold: Int, markedForDeletion: Int)
    case ageOfTheOldestDiscussionSharedSettingsMessage(TimeInterval?)

    // The protocol manager. A `Total` is always emitted and only the protocols with a non-zero count follow it, so a protocol that is absent from the list is
    // unambiguously at nought rather than a figure nobody asked for.

    case totalNumberOfProtocolInstances(Int)
    case numberOfProtocolInstancesOfAKind(ObvCryptoProtocolKind, Int)
    case numberOfProtocolInstancesOfAnUnrecognisedKind(Int)
    case totalNumberOfProtocolMessagesAwaitingProcessing(Int)
    case numberOfProtocolMessagesOfAKind(ObvCryptoProtocolKind, Int)
    case numberOfProtocolMessagesOfAnUnrecognisedKind(Int)

    /// A figure we could not compute. Emitted rather than dropped, so that a missing line cannot be mistaken for a line that was never asked for.
    case couldNotCompute(figure: String, reason: String)

    /// Whether the inbox directory can be read at all, kept as three cases because an empty inbox and an unreadable one are different findings and a single
    /// count of zero would say both.
    public enum StateOfTheInboxOnDisk: Sendable, Equatable {
        case holdsEntries(Int)
        case cannotBeRead
        case isMissing
    }

    /// The heading this figure belongs under. Emitted in order, so a screen can start a new group whenever this changes.
    public enum Section: String, Sendable, Equatable {
        case context = "Context"
        case recentListings = "Recent listings"
        case webSocket = "WebSocket, since this launch"
        case inboxMessages = "Inbox messages"
        case waitingForAManualDownload = "Waiting for a manual download"
        case ages = "Ages"
        case inboxAttachments = "Inbox attachments"
        case disk = "Disk"
        case discussionSharedSettings = "Discussion shared settings"
        case protocolInstances = "Protocol instances"
        case protocolMessages = "Protocol messages awaiting processing"
        case failures = "Could not be computed"
    }

}


// MARK: - How each figure describes itself

extension ObvEngineDiagnostic {

    public var section: Section { descriptor.section }
    public var label: String { descriptor.label }
    public var value: String { descriptor.value }

    /// One switch, so that adding a figure means adding one line here and nowhere else.
    private var descriptor: (section: Section, label: String, value: String) {
        switch self {

        case .numberOfProfiles(let count):
            return (.context, "Profiles", "\(count)")
        case .estimatedClockSkewAgainstTheServer(let skew):
            return (.context, "Estimated clock skew against the server", Self.duration(skew))

        case .numberOfRecordedListings(let count):
            return (.recentListings, "Listings recorded", "\(count)")
        case .durationsOfTheListingRequest(let median, let ninetieth, let worst):
            return (.recentListings, "Listing request", Self.spread(median: median, ninetieth: ninetieth, worst: worst))
        case .durationsOfTheSaveAndProcess(let median, let ninetieth, let worst):
            return (.recentListings, "Saving and processing what came back", Self.spread(median: median, ninetieth: ninetieth, worst: worst))
        case .outcomesOfTheRecordedListings(let counts):
            return (.recentListings, "Outcomes", Self.counts(counts.map { ($0.key.rawValue, $0.value) }))
        case .slowestRecordedListings(let timings):
            return (.recentListings, "Slowest", Self.listings(timings))
        case .mostRecentRecordedListings(let timings):
            return (.recentListings, "Most recent", Self.listings(timings))
        case .timeSinceTheLastCompletedListing(let interval):
            return (.recentListings, "Since the last completed listing", Self.age(interval))
        case .timeSinceTheLastUntruncatedListing(let interval):
            return (.recentListings, "Since the last untruncated listing", Self.age(interval))

        case .numberOfReturnReceiptsReceivedOnTheWebSocket(let count):
            return (.webSocket, "Return receipts received", "\(count)")
        case .numberOfDeleteReturnReceiptRequestsSent(let count):
            // Read beside the count above: the two should keep pace, and a shortfall means the server is still holding receipts we took but never released.
            return (.webSocket, "Delete requests sent for them", "\(count)")

        case .numberOfInboxMessages(let count):
            return (.inboxMessages, "Total", "\(count)")
        case .numberOfInboxMessagesNotYetDecrypted(let count):
            return (.inboxMessages, "Not yet decrypted", "\(count)")
        case .numberOfInboxMessagesAwaitingTheApp(let count):
            return (.inboxMessages, "Decrypted, awaiting the app", "\(count)")
        case .numberOfInboxMessagesOnHold(let count):
            return (.inboxMessages, "On hold", "\(count)")
        case .numberOfInboxMessagesMarkedForDeletion(let count):
            return (.inboxMessages, "Marked for deletion", "\(count)")
        case .numberOfInboxMessagesAwaitingAContact(let count):
            return (.inboxMessages, "Awaiting a contact for re-processing", "\(count)")
        case .numberOfInboxMessagesMarkedAsListedOnTheServer(let count):
            return (.inboxMessages, "Marked as listed on the server", "\(count)")
        case .numberOfInboxMessagesDeletedFromTheServer(let count):
            return (.inboxMessages, "Deleted from the server", "\(count)")
        case .numberOfInboxMessagesWithAtLeastOneAttachment(let count):
            return (.inboxMessages, "With at least one attachment", "\(count)")
        case .numberOfInboxMessagesBelongingToAnInactiveProfile(let count):
            return (.inboxMessages, "Belonging to an inactive profile", "\(count)")

        case .numberOfMessagesWaitingForAManualDownload(let count):
            return (.waitingForAManualDownload, "Messages", "\(count)")
        case .attachmentsWaitingForAManualDownload(let counts):
            return (.waitingForAManualDownload, "Their unmarked attachments", Self.counts(counts.map { ($0.key.rawValue, $0.value) }))
        case .bytesWaitingForAManualDownload(let bytes):
            return (.waitingForAManualDownload, "Bytes waiting", Self.bytes(bytes))
        case .ageOfTheOldestMessageWaitingForAManualDownload(let age):
            return (.waitingForAManualDownload, "Age of the oldest", Self.age(age))

        case .ageOfTheOldestInboxMessageNotYetDecrypted(let age):
            return (.ages, "Oldest not yet decrypted", Self.age(age))
        case .ageOfTheOldestInboxMessageAwaitingTheApp(let age):
            return (.ages, "Oldest awaiting the app", Self.age(age))
        case .ageOfTheOldestInboxMessageOnHold(let age):
            return (.ages, "Oldest on hold", Self.age(age))
        case .timeSpentOnTheServerBeforeBeingListed(let median, let worst):
            // Over the rows still in the inbox, which are the ones that did not finish — so this describes the stuck messages rather than ordinary traffic.
            return (.ages, "Waited on the server before being listed (unfinished messages only)", Self.spread(median: median, ninetieth: nil, worst: worst))

        case .numberOfInboxAttachments(let counts):
            return (.inboxAttachments, "By status", Self.counts(counts.map { ($0.key.rawValue, $0.value) }))
        case .numberOfUnmarkedAttachmentsOnAMessageMarkedForDeletion(let count):
            return (.inboxAttachments, "Unmarked, on a message marked for deletion", "\(count)")

        case .stateOfTheInboxOnDisk(let state):
            switch state {
            case .holdsEntries(let count): return (.disk, "The inbox directory", "\(count) entr\(count == 1 ? "y" : "ies")")
            case .cannotBeRead: return (.disk, "The inbox directory", "CANNOT BE READ")
            case .isMissing: return (.disk, "The inbox directory", "IS MISSING")
            }
        case .messageDirectoriesOnDisk(let onDisk, let expected):
            // The two are not meant to be equal to the unit: a directory goes when its message's attachments are all released, and is made when the
            // message is decrypted. What this line is for is the stark case — no directories at all beside a healthy count of messages that should have
            // one, which is the fingerprint of an inbox that has been swept out from under the database.
            return (.disk, "Message directories on disk / decrypted messages with attachments", "\(onDisk) / \(expected)")
        case .sizeOfTheEngineDatabase(let bytes):
            return (.disk, "The engine's database", bytes.map { Self.bytes($0) } ?? "could not be measured")

        case .numberOfInboxMessagesThatAreDiscussionSharedSettings(let count):
            return (.discussionSharedSettings, "Messages that are a shared-settings item", "\(count)")
        case .numberOfDecryptedPayloadsExamined(let count):
            return (.discussionSharedSettings, "Decrypted payloads examined", "\(count)")
        case .discussionSharedSettingsPerState(let awaitingTheApp, let onHold, let markedForDeletion):
            // Written out rather than passed through `counts(_:)`, which drops the zeros: these three add up to the figure above, and a state that is empty is
            // a finding rather than noise.
            return (.discussionSharedSettings, "By state", "awaiting the app \(awaitingTheApp), on hold \(onHold), marked for deletion \(markedForDeletion)")
        case .ageOfTheOldestDiscussionSharedSettingsMessage(let age):
            return (.discussionSharedSettings, "Age of the oldest", Self.age(age))

        case .totalNumberOfProtocolInstances(let count):
            return (.protocolInstances, "Total", "\(count)")
        case .numberOfProtocolInstancesOfAKind(let kind, let count):
            return (.protocolInstances, kind.rawValue, "\(count)")
        case .numberOfProtocolInstancesOfAnUnrecognisedKind(let count):
            return (.protocolInstances, "Unrecognised protocol id", "\(count)")
        case .totalNumberOfProtocolMessagesAwaitingProcessing(let count):
            return (.protocolMessages, "Total", "\(count)")
        case .numberOfProtocolMessagesOfAKind(let kind, let count):
            return (.protocolMessages, kind.rawValue, "\(count)")
        case .numberOfProtocolMessagesOfAnUnrecognisedKind(let count):
            return (.protocolMessages, "Unrecognised protocol id", "\(count)")

        case .couldNotCompute(let figure, let reason):
            return (.failures, figure, reason)

        }
    }

}


// MARK: - The protocol manager's figures, in order

extension ObvEngineDiagnostic {

    /// The rows describing the protocol manager, in the order they are meant to be shown.
    ///
    /// Here rather than at the call site: the order is a property of this file, and a caller free to choose its own is what would break it.
    ///
    /// A `Total` first, so a protocol missing below reads as nought rather than as never asked; then the protocols with something to report, in
    /// ``ObvCryptoProtocolKind``'s own order so two readings agree; then the unrecognised rows, only when there are any.
    public static func figures(for counts: ObvProtocolCounts) -> [ObvEngineDiagnostic] {

        var figures: [ObvEngineDiagnostic] = []

        figures.append(.totalNumberOfProtocolInstances(counts.totalNumberOfProtocolInstances))
        for kind in ObvCryptoProtocolKind.allCases {
            guard let count = counts.protocolInstancesPerKind[kind], count > 0 else { continue }
            figures.append(.numberOfProtocolInstancesOfAKind(kind, count))
        }
        if counts.protocolInstancesWithAnUnrecognisedKind > 0 {
            figures.append(.numberOfProtocolInstancesOfAnUnrecognisedKind(counts.protocolInstancesWithAnUnrecognisedKind))
        }

        figures.append(.totalNumberOfProtocolMessagesAwaitingProcessing(counts.totalNumberOfReceivedProtocolMessages))
        for kind in ObvCryptoProtocolKind.allCases {
            guard let count = counts.receivedProtocolMessagesPerKind[kind], count > 0 else { continue }
            figures.append(.numberOfProtocolMessagesOfAKind(kind, count))
        }
        if counts.receivedProtocolMessagesWithAnUnrecognisedKind > 0 {
            figures.append(.numberOfProtocolMessagesOfAnUnrecognisedKind(counts.receivedProtocolMessagesWithAnUnrecognisedKind))
        }

        return figures

    }

}


// MARK: - Rendering values

extension ObvEngineDiagnostic {

    private static func duration(_ interval: TimeInterval?) -> String {
        guard let interval else { return "unknown" }
        if abs(interval) < 1 { return String(format: "%.0f ms", interval * 1000) }
        return String(format: "%.2f s", interval)
    }

    private static func spread(median: TimeInterval?, ninetieth: TimeInterval?, worst: TimeInterval?) -> String {
        guard median != nil || ninetieth != nil || worst != nil else { return "no measurement" }
        var parts = ["median \(duration(median))"]
        if let ninetieth { parts.append("p90 \(duration(ninetieth))") }
        parts.append("worst \(duration(worst))")
        return parts.joined(separator: ", ")
    }

    /// Ages are reported to the hour or the day rather than to the second: this text is meant to be mailed to us, and a precise moment for every event on a
    /// device is more than we need in order to read a report.
    private static func age(_ interval: TimeInterval?) -> String {
        guard let interval else { return "never" }
        let hours = interval / 3600
        if hours < 1 { return "under an hour" }
        if hours < 48 { return "\(Int(hours.rounded())) h" }
        return "\(Int((hours / 24).rounded())) days"
    }

    private static func bytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func counts(_ counts: [(String, Int)]) -> String {
        let nonZero = counts.filter { $0.1 > 0 }.sorted { $0.0 < $1.0 }
        guard !nonZero.isEmpty else { return "none" }
        return nonZero.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
    }

    private static func listings(_ timings: [ObvServerRequestTiming]) -> String {
        guard !timings.isEmpty else { return "no listing recorded" }
        return timings.map { timing in
            var line = "\(age(Date.now.timeIntervalSince(timing.date))) ago: \(timing.outcome.rawValue), request \(duration(timing.durationOfTheRequest))"
            if let save = timing.durationOfTheSaveAndProcess {
                line += ", then \(duration(save))"
            }
            if let count = timing.numberOfMessagesReturned {
                line += ", \(count) message\(count == 1 ? "" : "s")"
            }
            line += ", on \(timing.trigger.rawValue)"
            return line
        }.joined(separator: "\n")
    }

}

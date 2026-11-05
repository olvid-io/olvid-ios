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
import OSLog
import ObvCrypto
import ObvMetaManager
import ObvTypes
import OlvidUtils


/// Owns everything about the return receipts we owe: we keep them, then we send them.
public actor ObvReturnReceiptSendManager {

    private static let logger = Logger(subsystem: "io.olvid.returnReceiptSend", category: "ObvReturnReceiptSendManager")

    /// Only for `NSManagedObjectContext.save(logOnFailure:)`, which takes an `OSLog` rather than a `Logger`.
    private static let osLog = OSLog(subsystem: "io.olvid.returnReceiptSend", category: "ObvReturnReceiptSendManager")

    /// How many receipts one turn of the cycle takes on, whether they were just posted or read from the store.
    ///
    /// Both paths are bounded by it, and by the same value, so the one on the path of every received message is not
    /// less bounded than the sweep. Everything downstream follows from it: what is encrypted before anything is
    /// uploaded, how many requests go at once, and how large a report is.
    ///
    /// This is not the number of receipts one request may carry, and not the number of identifiers one delete fetch
    /// may name. Three limits that happen to agree on fifty; moving one must not move the others.
    private static let maximumNumberOfReceiptsPerCycle = 50

    /// How old a receipt may get before it is given up on.
    ///
    /// Given up on, not deleted on sight: an over-age receipt is uploaded and then deleted whatever the server said.
    /// The commonest way a row reaches this age is not that it cannot be delivered but that the phone was off, or
    /// abroad, or offline for five weeks — so deleting ahead of the attempt would destroy a backlog that was about
    /// to go out.
    private static let ageAtWhichAReceiptIsGivenUpOn: TimeInterval = 30 * 24 * 60 * 60

    private let appType: AppType

    /// Nil when the store could not be opened. See ``init(appType:containerURL:runningLog:)``.
    private let databaseCoordinator: ReturnReceiptSendDatabaseCoordinator?

    private let uploader: ReturnReceiptUploader

    /// Set by ``finalizeInitialization(delegate:)``. Weak: the engine owns this module.
    private weak var delegate: ObvReturnReceiptSendManagerDelegate?

    /// What this process has taken on and not yet sent, by row.
    ///
    /// Keyed by identifier, so the same receipt posted twice is uploaded once. The rows are the durable copy; this is
    /// only what the current process knows it owes, and it is empty again as soon as a send takes it.
    private var pendingReceipts = [ReturnReceiptIdentifier: ReturnReceiptToUpload]()

    /// The send in flight, if there is one.
    ///
    /// One at a time. Nothing is held back to build a batch: the first receipt leaves at once, and whatever arrives
    /// while that send runs leaves behind it, on the next turn of its loop. No timer and no threshold.
    private var currentSend: Task<Void, Never>?

    /// The sweep in flight, if there is one.
    ///
    /// One at a time. Two callers ask for a sweep — the app coming to the foreground, and the inbox-drain window —
    /// and they overlap, so without this they would page over the same rows twice. A second caller **awaits** this
    /// one rather than being turned away: the window holds a background task and wants the backlog walked, and
    /// telling it a sweep happened when it did not would be worse than making it wait.
    /// The deadline is the earliest any of its callers asked for: a caller that waits for a sweep it did not start may
    /// shorten it, or a window holding a background task for thirty seconds could be held by a sweep a foreground
    /// started with five minutes — being held past a deadline is what the deadline exists to prevent.
    ///
    /// Not private, so that a test can wait for a shortening to have happened rather than for a length of time.
    private(set) var currentDrain: (task: Task<Void, Never>, deadline: Date)?

    /// Never fails. Without a store — no container, or one that will not open — the manager runs degraded: a receipt is
    /// sent at once and is lost if the process dies first, which is what this app did before the store existed. A return
    /// receipt is not worth a failed launch, nor worth a `catch` that one of the engine's three start paths could
    /// forget. Why the store would not open is logged where that is found, in ``ReturnReceiptSendDatabaseCoordinator``.
    ///
    /// - Parameter containerURL: nil when the caller has no directory to give, which is the same degraded mode.
    public init(appType: AppType, containerURL: URL?, runningLog: RunningLogError) {
        self.appType = appType
        self.databaseCoordinator = Self.makeDatabaseCoordinator(appType: appType, containerURL: containerURL, runningLog: runningLog)
        self.uploader = .init()
    }


    /// For the tests, which need the network to answer what they ask it to. An actor cannot delegate to another of its
    /// initializers, hence the repetition.
    init(appType: AppType, containerURL: URL?, runningLog: RunningLogError, uploader: ReturnReceiptUploader) {
        self.appType = appType
        self.databaseCoordinator = Self.makeDatabaseCoordinator(appType: appType, containerURL: containerURL, runningLog: runningLog)
        self.uploader = uploader
    }


    private static func makeDatabaseCoordinator(appType: AppType, containerURL: URL?, runningLog: RunningLogError) -> ReturnReceiptSendDatabaseCoordinator? {
        guard let containerURL else {
            logger.fault("This module was given no container and runs in degraded mode: receipts are sent right away, and are lost if this process dies first.")
            return nil
        }
        do {
            return try ReturnReceiptSendDatabaseCoordinator(appType: appType, containerURL: containerURL, runningLog: runningLog)
        } catch {
            logger.fault("This module has no store and runs in degraded mode: receipts are sent right away, and are lost if this process dies first. \(error)")
            return nil
        }
    }


    /// Gives the module what it needs from the engine. Called once, by the engine, at the end of its own
    /// initialization.
    public func finalizeInitialization(delegate: ObvReturnReceiptSendManagerDelegate) async throws {
        self.delegate = delegate
    }


    /// False when the module runs in the degraded mode described in ``init(appType:containerURL:runningLog:)``.
    var receiptsCanBePersisted: Bool {
        databaseCoordinator != nil
    }

}


// MARK: - Sending the receipts we owe

extension ObvReturnReceiptSendManager {

    /// Takes on these receipts, and returns once they are written down, or once they have been sent.
    ///
    /// Never fails, and reports its own faults. A receipt that could not be written down is still handed to the
    /// sender — never worse than what this app did before there was a store — and what a server answered decides
    /// whether a receipt is sent again, which is this module's business. So there was nothing a caller could have
    /// been told that it could act on.
    ///
    /// - Parameter waitUntilSent: whether to return only once the send has finished, **successfully or not** — there
    ///   being nothing left to wait for either way. False costs a local save rather than a network round trip, and is
    ///   what a process that will still be running wants: a row survives this process dying, so an upload that never
    ///   happens is a retry rather than a lost receipt. True is for a caller that is about to finish and would
    ///   otherwise leave its receipts to be sent by a sweep it will not be there for — only the app sweeps, so for an
    ///   extension that means the reader's next foreground. It does **not** wait for a sweep, which walks rows this
    ///   process may never have posted and which an extension must never wait for.
    public func post(_ returnReceiptsToSend: [ObvReturnReceiptToSend], flowId: FlowIdentifier, waitUntilSent: Bool) async {

        guard !returnReceiptsToSend.isEmpty else { return }

        // One instant for the whole batch. The age cap is measured from it, and it is passed in rather than read
        // again inside the context so that the row and the value in memory cannot disagree.
        let createdAt = Date.now

        // Converted once, and the same values are both written down and sent: a row and the receipt in memory can
        // then disagree about nothing.
        let receipts = returnReceiptsToSend.map { ReturnReceiptToUpload(returnReceiptToSend: $0, createdAt: createdAt) }

        do {
            try await persist(receipts)
        } catch {
            Self.logger.fault("🧾 \(receipts.count) return receipts could not be written down, and are sent without being durable: \(error.localizedDescription, privacy: .public)")
        }

        for receipt in receipts {
            pendingReceipts[receipt.identifier] = receipt
        }

        Self.logger.info("🧾 \(returnReceiptsToSend.count) return receipts taken on, flow \(flowId.debugDescription, privacy: .public)")

        signalTheSender()

        if waitUntilSent {
            await awaitTheCurrentSend()
        }

    }


    /// Writes the rows. Degraded, there is nothing to write and nothing can fail.
    ///
    /// A receipt that cannot be turned into a row does not stop the others: the save happens either way, and the
    /// first failure is reported afterwards.
    private func persist(_ receipts: [ReturnReceiptToUpload]) async throws {

        guard let databaseCoordinator else { return }

        let context = databaseCoordinator.newBackgroundContext()

        try await context.perform {
            var firstError: Error?
            for receipt in receipts {
                do {
                    _ = try PersistedReturnReceiptToSend(returnReceiptToUpload: receipt, within: context)
                } catch {
                    firstError = firstError ?? error
                }
            }
            try context.save(logOnFailure: Self.osLog)
            if let firstError {
                throw firstError
            }
        }

    }

}


// MARK: - The sender

extension ObvReturnReceiptSendManager {

    /// Returns once what this process posted has been sent, or has failed to send.
    ///
    /// The other half of `post(_:flowId:waitUntilSent:)`, for a caller that posts several times and waits once — which
    /// `waitUntilSent` cannot express, coupling as it does the writing down and the sending of one call.
    public func flush() async {
        await awaitTheCurrentSend()
    }


    /// Returns once the send in flight has finished, and once any send it leaves behind it has finished too.
    ///
    /// Returns at once when nothing is being sent.
    private func awaitTheCurrentSend() async {
        while let currentSend {
            await currentSend.value
        }
    }


    private func signalTheSender() {
        guard currentSend == nil else { return }
        currentSend = Task { await self.sendUntilNothingIsPending() }
    }


    private func sendUntilNothingIsPending() async {
        while !pendingReceipts.isEmpty {
            let batch = Array(pendingReceipts.values.prefix(Self.maximumNumberOfReceiptsPerCycle))
            for identifier in batch.map(\.identifier) {
                pendingReceipts.removeValue(forKey: identifier)
            }
            await sendAndSettle(batch)
        }
        currentSend = nil
    }


    /// What one turn of the cycle did to the batch it was handed, and what a sweep is to do next.
    private struct WhatBecameOfTheBatch {

        /// How many of the receipts had their rows deleted. The rest are still there, and a sweep steps over them.
        let numberOfReceiptsSettled: Int

        /// Whether this server's run is to end here rather than read another page.
        ///
        /// True when a request was answered badly or never reached a server — a server that has just refused fifty
        /// receipts should not then be sent the rest of what it is owed — and true when the identity database would
        /// not answer for the batch at all, the next page being certain to meet the same answer.
        let thisServersRunEndsHere: Bool

    }


    /// One turn of the cycle: the contact's devices as they are now, the seeds, the upload, and then the only write
    /// this makes to the store.
    ///
    /// Every direction of failure leaves the row where it is. A row is deleted only when an upload carrying it
    /// succeeded, when the receipt can never be sent — no device, no seed, nothing to encrypt with — or when it is
    /// over-age and has had whatever chance it was ever going to get. Degraded there are no rows, so a failure loses
    /// the receipt, which is what this app did before the store existed.
    @discardableResult
    private func sendAndSettle(_ receipts: [ReturnReceiptToUpload]) async -> WhatBecameOfTheBatch {

        guard let delegate else {
            Self.logger.fault("🧾 This module has no delegate, so it can send nothing")
            return .init(numberOfReceiptsSettled: 0, thisServersRunEndsHere: true)
        }

        // A send batches what several calls to `post` handed over, so it carries no caller's flow and starts one.
        let flowId = FlowIdentifier()

        // Asked once for the whole cycle: the age of a receipt decides two things, and a clock read twice — or a
        // predicate written twice — could answer differently in each.
        let instantBeforeWhichAReceiptIsGivenUpOn = Date.now - Self.ageAtWhichAReceiptIsGivenUpOn
        let identifiersOfOverAgeReceipts = Set(receipts.filter { $0.createdAt < instantBeforeWhichAReceiptIsGivenUpOn }.map { $0.identifier })

        let contactIdentifiers = Set(receipts.map { $0.identifier.contactIdentifier })
        let deviceUIDsOfContacts: [ObvContactIdentifier: Set<UID>]
        do {
            deviceUIDsOfContacts = try await delegate.getDeviceUidsOfContacts(self, contactIdentifiers: contactIdentifiers, flowId: flowId)
        } catch {
            // A throw is about the identity database and not about any receipt in the batch, so nothing is deleted —
            // the over-age ones included. The rows are asked about again by the next drain.
            Self.logger.error("🧾 The devices of \(contactIdentifiers.count) contacts could not be read, so \(receipts.count) return receipts stay where they are: \(error.localizedDescription, privacy: .public)")
            return .init(numberOfReceiptsSettled: 0, thisServersRunEndsHere: true)
        }

        var receiptsWithTheirDevices = [(receipt: ReturnReceiptToUpload, contactDeviceUIDs: Set<UID>)]()
        var identifiersThatCanNeverBeSent = [ReturnReceiptIdentifier]()
        var identifiersGivenUpOnWithoutAnAttempt = [ReturnReceiptIdentifier]()

        for receipt in receipts {
            guard let deviceUIDs = deviceUIDsOfContacts[receipt.identifier.contactIdentifier] else {
                // Not answered for. Kept, and asked about again later — unless it has waited long enough to be given
                // up on. Nothing else would ever delete this row: the cap below is reached only by a receipt that
                // got as far as a request, and one whose contact cannot be looked up never does. A contact deleted
                // while a receipt was owed to it would otherwise be owed that receipt for the life of the install.
                if identifiersOfOverAgeReceipts.contains(receipt.identifier) {
                    identifiersGivenUpOnWithoutAnAttempt.append(receipt.identifier)
                }
                continue
            }
            guard !deviceUIDs.isEmpty else {
                // Answered for, and the contact has no device: this receipt can never be sent. The row goes, or it is
                // read again by every drain from now on.
                identifiersThatCanNeverBeSent.append(receipt.identifier)
                continue
            }
            receiptsWithTheirDevices.append((receipt, deviceUIDs))
        }

        if !identifiersGivenUpOnWithoutAnAttempt.isEmpty {
            Self.logger.error("🧾 \(identifiersGivenUpOnWithoutAnAttempt.count) return receipts are over-age and their contacts cannot be looked up, so they are given up on")
        }

        let seeds: [ReturnReceiptIdentifier: Seed]
        do {
            let seedsOfReceipts = try await delegate.getDeterministicSeedsForReturnReceiptEncryption(self, returnReceiptsToSend: receiptsWithTheirDevices.map { $0.receipt.returnReceiptToSend })
            seeds = Dictionary(seedsOfReceipts.map { (ReturnReceiptIdentifier(returnReceiptToSend: $0.returnReceiptToSend), $0.seed) }, uniquingKeysWith: { first, _ in first })
        } catch {
            Self.logger.error("🧾 The seeds of \(receiptsWithTheirDevices.count) return receipts could not be read, so they stay where they are: \(error.localizedDescription, privacy: .public)")
            // The two sets already decided are still deleted: neither answer depends on this one.
            let identifiersToDelete = identifiersThatCanNeverBeSent + identifiersGivenUpOnWithoutAnAttempt
            let theRowsAreGone = await deleteRows(withIdentifiers: identifiersToDelete)
            return .init(numberOfReceiptsSettled: theRowsAreGone ? Set(identifiersToDelete).count : 0, thisServersRunEndsHere: true)
        }

        var receiptsReadyToUpload = [ReturnReceiptReadyToUpload]()
        for (receipt, contactDeviceUIDs) in receiptsWithTheirDevices {
            guard let seed = seeds[receipt.identifier] else {
                // A receipt the delegate returned no seed for cannot be encrypted, now or ever. Its row goes too.
                Self.logger.fault("🧾 A return receipt has no seed to be encrypted with, and can never be sent")
                identifiersThatCanNeverBeSent.append(receipt.identifier)
                continue
            }
            receiptsReadyToUpload.append(.init(returnReceipt: receipt, contactDeviceUIDs: contactDeviceUIDs, seed: seed))
        }

        let report = await uploader.upload(receiptsReadyToUpload, flowId: flowId)

        var identifiersToDelete = identifiersThatCanNeverBeSent + identifiersGivenUpOnWithoutAnAttempt + report.identifiersThatCanNeverBeSent
        var everyRequestSucceeded = true
        for outcome in report.outcomes {
            let count = outcome.identifiers.count
            let server = outcome.serverURL.absoluteString
            switch outcome.outcome {
            case .theUploadSucceeded:
                Self.logger.info("🧾 \(count) return receipts were taken by \(server, privacy: .public)")
                identifiersToDelete += outcome.identifiers
            case .theRequestNeverLeftTheDevice:
                // Not even the over-age ones. No server saw the request, so no attempt was made, and one launch in
                // airplane mode must not destroy a backlog that was about to go out.
                everyRequestSucceeded = false
                Self.logger.error("🧾 \(count) return receipts for \(server, privacy: .public) never left the device, and stay where they are")
            case .theUploadFailed:
                // A server answered and answered badly, so the over-age ones have had their last chance. Deleting
                // them regardless of the answer is what makes this a cap: a receipt that can never be delivered
                // would otherwise take a last chance on every sweep, for ever.
                everyRequestSucceeded = false
                let overAge = outcome.identifiers.filter { identifiersOfOverAgeReceipts.contains($0) }
                identifiersToDelete += overAge
                Self.logger.error("🧾 \(count) return receipts were refused by \(server, privacy: .public); \(overAge.count) of them were over-age and are given up on, the rest stay where they are")
            }
        }

        // A store that would not take this write will not take the next one either, so the run ends here rather than
        // paging on. Nothing is reported as settled: the rows are all still there.
        let theRowsAreGone = await deleteRows(withIdentifiers: identifiersToDelete)

        return .init(numberOfReceiptsSettled: theRowsAreGone ? Set(identifiersToDelete).count : 0,
                     thisServersRunEndsHere: !everyRequestSucceeded || !theRowsAreGone)

    }


    /// Degraded, there are no rows and this does nothing.
    ///
    /// A row that is not there is not an error: another process may have sent the same receipt and deleted it first.
    ///
    /// - Returns: whether the rows are gone. All or none of them: the deletes are made in one context and committed
    ///   by one save, so a failure anywhere leaves every row where it was. The caller must not report a row it asked
    ///   to delete as one that went — deletion is the only thing that advances a sweep, and a sweep that believes a
    ///   page it could not clear has been cleared reads and uploads that page again on every turn of its loop.
    private func deleteRows(withIdentifiers identifiers: [ReturnReceiptIdentifier]) async -> Bool {

        guard !identifiers.isEmpty, let databaseCoordinator else { return true }

        let context = databaseCoordinator.newBackgroundContext()

        return await context.perform {
            do {
                try PersistedReturnReceiptToSend.deleteReturnReceipts(withIdentifiers: identifiers, within: context)
                try context.save(logOnFailure: Self.osLog)
                return true
            } catch {
                // Whatever became of the receipts, the rows are still here. The next drain settles them again, which
                // costs at worst a duplicate the server ignores.
                Self.logger.fault("🧾 \(identifiers.count) return receipt rows could not be deleted: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }

    }

}


// MARK: - Sweeping the store

extension ObvReturnReceiptSendManager {

    /// Sends every receipt the store still holds, including those a process that died left behind.
    ///
    /// The app only. An extension has thirty seconds and 24MB and must never walk a backlog — it sends what it just
    /// posted, and `flush` is what it waits on. The rule is enforced here rather than left to callers.
    ///
    /// Returns when the sweep has finished, when the deadline has passed, or when a sweep already in flight has
    /// finished — a second caller waits for that one rather than starting another.
    public func drain(until deadline: Date) async {

        guard appType == .mainApp else {
            Self.logger.error("🧾 Only the app sweeps the receipts it owes, and this is the \(self.appType.transactionAuthor, privacy: .public)")
            return
        }

        guard databaseCoordinator != nil else { return }

        // A caller with nothing left to spend takes nothing from the sweep in flight. Shortening below is for a
        // caller that has *some* time and must not be held past it; a deadline already spent is not that, and using
        // it would stop a sweep that still has a budget of its own, for a caller that wanted to return at once.
        guard Date.now < deadline else {
            Self.logger.info("🧾 A sweep was asked for with no time left, so nothing is swept and nothing in flight is shortened")
            return
        }

        if let currentDrain {
            self.currentDrain = (currentDrain.task, min(currentDrain.deadline, deadline))
            await currentDrain.task.value
            return
        }

        let task = Task { await self.sweepEveryServer() }
        currentDrain = (task, deadline)
        await task.value

    }


    /// Whether the sweep in flight still has time. No sweep is no time, so it stops.
    private var theSweepStillHasTime: Bool {
        guard let currentDrain else { return false }
        return Date.now < currentDrain.deadline
    }


    private func sweepEveryServer() async {

        defer { currentDrain = nil }

        guard let servers = await distinctServers() else {
            // Nil is a database that would not answer, which is not the same as no server being owed anything. Zero
            // would be reported below as a sweep that found nothing, which is the one thing this sweep did not do.
            Self.logger.fault("🧾 Nothing is swept: the servers that are owed receipts could not be read")
            return
        }

        // Said unconditionally, zero servers included. A sweep that finds nothing is the common case, and without a
        // line here it cannot be told apart from a sweep that never ran.
        Self.logger.info("🧾 Sweeping the receipts owed to \(servers.count) servers")

        for server in servers {
            guard theSweepStillHasTime else {
                Self.logger.info("🧾 The deadline passed before the sweep reached every server")
                return
            }
            await sweep(server: server)
        }

    }


    /// Pages through one server's receipts, oldest first.
    ///
    /// Deletion is what advances a sweep, so a row it cannot settle stays at the front of every fetch it makes. It
    /// steps over those rather than ending its run on them: a receipt whose contact the identity database will not
    /// answer for is kept for as long as thirty days, and fifty such rows on one server would otherwise be a sweep
    /// that reads one page, settles nothing and stops — for ever, while everything queued behind them waits.
    ///
    /// What does end a run is an answer about the *server*: one that has just refused fifty receipts should not then
    /// be sent the rest of what it is owed, and one this device cannot reach will not be reachable a page later. The
    /// other servers' runs carry on either way.
    private func sweep(server: URL) async {

        var numberOfRowsTheSweepHasLeftBehind = 0

        while theSweepStillHasTime {

            guard let page = await fetchPage(forServer: server, skipping: numberOfRowsTheSweepHasLeftBehind) else {
                // A page that could not be read says nothing about the rest of this server's backlog, so the run ends
                // here rather than on the emptiness it is not. What is left is asked about again by the next drain.
                Self.logger.fault("🧾 A page of the receipts owed to \(server.absoluteString, privacy: .public) could not be read, so this server's run ends here")
                return
            }
            guard !page.isEmpty else { return }

            let whatBecameOfIt = await sendAndSettle(page)
            numberOfRowsTheSweepHasLeftBehind += page.count - whatBecameOfIt.numberOfReceiptsSettled

            guard !whatBecameOfIt.thisServersRunEndsHere else {
                Self.logger.info("🧾 A page of \(page.count) return receipts for \(server.absoluteString, privacy: .public) settled \(whatBecameOfIt.numberOfReceiptsSettled) of them, and this server's run ends here")
                return
            }

        }

    }


    /// Nil when the store could not be read. Degraded there is no store and nothing is owed, which is an empty answer.
    private func distinctServers() async -> Set<URL>? {
        guard let databaseCoordinator else { return [] }
        let context = databaseCoordinator.newBackgroundContext()
        return await context.perform {
            do {
                return try PersistedReturnReceiptToSend.getDistinctServerURLs(within: context)
            } catch {
                Self.logger.fault("🧾 The servers that are owed receipts could not be read: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }


    /// Nil when the store could not be read, which the caller must not take for the end of this server's receipts.
    private func fetchPage(forServer serverURL: URL, skipping numberOfRowsToSkip: Int) async -> [ReturnReceiptToUpload]? {
        guard let databaseCoordinator else { return [] }
        let context = databaseCoordinator.newBackgroundContext()
        return await context.perform {
            do {
                return try PersistedReturnReceiptToSend.getReturnReceiptsToUpload(forServer: serverURL, skipping: numberOfRowsToSkip, fetchLimit: Self.maximumNumberOfReceiptsPerCycle, within: context)
            } catch {
                Self.logger.fault("🧾 A page of return receipts could not be read: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

}


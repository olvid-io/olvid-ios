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


/// How much work the inbox still holds, cheaply enough to ask repeatedly.
///
/// The same numbers appear among ``ObvEngineDiagnostic``'s two dozen figures, but that is the wrong instrument for a loop: a diagnostics pass takes seconds
/// and is not interruptible. This is a handful of SQL counts over one context, materialising nothing, for a caller asking every half second whether anything
/// is still moving.
///
/// **All but one are cheap, and the one that is not is asked for by name.** ``numberOfMessagesWaitingForAManualDownload`` needs a subquery over every
/// message's attachments — 72ms against 12–14ms for each of the others, on a store of 81'210 messages — so the frequent callers leave it out.
///
/// **Several numbers rather than one, because *the messages were processed* and *the rows are gone* are different claims.** A drain finishing with
/// ``numberOfMessagesAwaitingTheApp`` at nought has done everything the app owes and may still leave tens of thousands of rows waiting for a sweep.
///
/// **The three states are not a partition of the inbox**, which is the trap ``numberOfMessagesStillOwed`` closes: a message listed but not yet decrypted is
/// in none of them, nor is one on hold or waiting for a contact. Read three numbers and a hundred thousand freshly-listed messages look like an empty inbox.
public struct ObvInboxCounts: Sendable, Equatable {

    /// Every message in the inbox, whatever its state and **whatever profile it belongs to** — the number that has to reach nought before the inbox is
    /// really empty.
    ///
    /// **Alone among these in not being restricted to the active profiles, and deliberately.** This one is a fact about the store, which a reader can check
    /// against the database and which a report showing anything else would be lying about. The four below are facts about *work*, and work is only work if
    /// something will ever do it. The two therefore need not sum, and ``numberOfMessagesBelongingToAnInactiveOwnedIdentity`` is the difference.
    public let numberOfMessages: Int

    /// Listed, still encrypted, and nothing standing in the way of decrypting it: the work the **channel** still owes.
    ///
    /// Excludes a message on hold and one waiting for a contact to exist, both of which are also undecrypted and neither of which any amount of draining
    /// will move — they are answered by the bootstrap replay at the next launch and by a different background task.
    ///
    /// **And excludes a message of an inactive profile, which is the same kind of exclusion arrived at the same way.** See
    /// ``numberOfMessagesBelongingToAnInactiveOwnedIdentity``.
    public let numberOfMessagesNotYetDecrypted: Int

    /// Decrypted, not on hold, not marked for deletion: the work the **app** still owes.
    public let numberOfMessagesAwaitingTheApp: Int

    /// The app has finished with these and the rows are still here.
    ///
    /// **Not the same as the work the sweep still owes**, which is what this used to be read as: a message the app has finished with keeps its row until
    /// *every* attachment has been released too, and one whose attachment the reader has not asked for is released never. Subtract
    /// ``numberOfMessagesWaitingForAManualDownload`` — or use ``numberOfMessagesStillToBeRemoved``, which is that subtraction.
    public let numberOfMessagesMarkedForDeletion: Int

    /// Of those marked for deletion, the ones whose attachments have not all been released — so the row stays and the server keeps its copy, until the
    /// reader downloads the attachment or deletes the message. Nil when the count was not asked for.
    ///
    /// **This is the ordinary state of an ordinary device, and counting it as outstanding work is why the drain could not say it had finished.** Every
    /// received photograph the reader has not opened is one of these. It is nobody's work: no listing, no sweep and no waiting will move it, and a drain
    /// that treats it as work spends two barren rounds discovering as much and then reports *nothing was moving any more* — a fault-sounding sentence for a
    /// healthy inbox.
    ///
    /// The window is a little wider than *not downloaded*: an attachment being fetched right now, and one whose bytes have arrived but which the app has not
    /// yet released, are both in here. Both are brief. The engine's own diagnostics have called this population *waiting for a manual download* since before
    /// this type existed, and the name is kept so that the two screens read alike.
    public let numberOfMessagesWaitingForAManualDownload: Int?

    /// Messages belonging to a profile that is no longer active — counted by nobody else here, and the difference between ``numberOfMessages`` and the parts.
    ///
    /// **Nothing will ever move these, and counting them as work is a fault that never ends.** A profile deactivates on an ordinary path: the server answers
    /// `anotherDeviceIsAlreadyRegistered` — the reader set Olvid up on a new phone without multi-device — and this device deactivates. That deletes contact
    /// devices and oblivious channels and **leaves the inbox alone**, which is right, because deactivation is reversible and the messages may still be
    /// wanted. But the listing enumerates the *active* identities only, and the batch that processes and the batch that deletes are both per identity, so
    /// those rows are never listed, decrypted, marked or swept.
    ///
    /// Counted among the work owed, they made a drain report ``ObvInboxDrainStopReason/nothingWasMovingAnyMore`` — the one ending that means *something is
    /// wrong* — on every window, for ever, six hours apart, on a device with nothing whatever wrong with it. Measured on a simulator on 2026-09-13: 2'000
    /// such rows, thirty rounds, thirty-one seconds, nothing moved, and no amount of waiting would have changed it.
    ///
    /// **It is reported rather than merely subtracted, because a reader needs to be told what to do.** The remedy is theirs and not ours — reactivate the
    /// profile, or delete it — and a gap between the total and the parts with no figure to explain it would send somebody looking for a bug instead.
    ///
    /// Nil when the count was not asked for, in which case the counts beside it are the unrestricted, pessimistic ones: that errs towards draining on, never
    /// towards standing down early, which is the direction every optional count here errs in.
    public let numberOfMessagesBelongingToAnInactiveOwnedIdentity: Int?

    public init(numberOfMessages: Int, numberOfMessagesNotYetDecrypted: Int, numberOfMessagesAwaitingTheApp: Int, numberOfMessagesMarkedForDeletion: Int, numberOfMessagesWaitingForAManualDownload: Int?, numberOfMessagesBelongingToAnInactiveOwnedIdentity: Int?) {
        self.numberOfMessages = numberOfMessages
        self.numberOfMessagesNotYetDecrypted = numberOfMessagesNotYetDecrypted
        self.numberOfMessagesAwaitingTheApp = numberOfMessagesAwaitingTheApp
        self.numberOfMessagesMarkedForDeletion = numberOfMessagesMarkedForDeletion
        self.numberOfMessagesWaitingForAManualDownload = numberOfMessagesWaitingForAManualDownload
        self.numberOfMessagesBelongingToAnInactiveOwnedIdentity = numberOfMessagesBelongingToAnInactiveOwnedIdentity
    }


    /// What a sweep can actually take: marked for deletion, and not held back by an attachment nobody has released.
    ///
    /// Clamped, because the two counts it subtracts describe one instant but arithmetic does not know that; and answering
    /// ``numberOfMessagesMarkedForDeletion`` when the second count was not asked for, so that a caller who declined to pay for it is told there may be work
    /// rather than told there is none.
    public var numberOfMessagesStillToBeRemoved: Int {
        guard let numberOfMessagesWaitingForAManualDownload else { return numberOfMessagesMarkedForDeletion }
        return max(0, numberOfMessagesMarkedForDeletion - numberOfMessagesWaitingForAManualDownload)
    }

    /// Everything somebody still owes: to be decrypted, to be stored by the app, or to be swept away.
    ///
    /// **Nought here — and not `numberOfMessagesAwaitingTheApp == 0 && numberOfMessagesMarkedForDeletion == 0` — is what means a drain has nothing left to
    /// do.** Rows may well remain when it is nought, and none of them is a drain's to move: a message on hold, one waiting for a contact, one that could
    /// never be decrypted, one whose attachment the reader has not asked for. Leaving the undecrypted out of that test is what let a drain answer *there was
    /// nothing left to do* after a single round, having just listed a hundred thousand messages that nothing had got round to decrypting yet.
    ///
    /// **And counting every marked row is what stopped it ever answering that at all.** A device holding one unopened photograph has a message marked for
    /// deletion for as long as it holds it, so this sum could not reach nought and the *one ending that reads as success* was reachable only on a literally
    /// empty inbox. Measured on a simulator on 2026-09-11: an empty inbox stopped on `thereWasNothingLeftToDo` in one round, and the same inbox one unopened
    /// photograph later took two rounds and four sweep rounds to stop on `nothingWasMovingAnyMore` instead. Hence ``numberOfMessagesStillToBeRemoved`` here
    /// rather than the raw count — with the caveat that a caller who did not ask for the fifth count gets the old, pessimistic sum, which errs towards
    /// draining on and never towards standing down early.
    ///
    /// **The third population it must not count is handled before it gets here, and could not have been handled from here.** A message of an inactive
    /// profile is *"one that could never be decrypted"* in the list above, and the obvious repair — a sixth count, subtracted like the fifth — is wrong:
    /// this is a **sum of three populations that overlap**, and one stranded row can be both undecrypted and marked for deletion, so a single aggregate
    /// taken off the total over- or under-counts. The fifth count gets away with being subtracted only because it is a subset of the one population it is
    /// taken from. So the restriction is applied to each count as it is made, and what arrives here is already the work of live profiles alone.
    public var numberOfMessagesStillOwed: Int {
        numberOfMessagesNotYetDecrypted + numberOfMessagesAwaitingTheApp + numberOfMessagesStillToBeRemoved
    }


    /// Whether nothing at all has changed since `other`, in **either** direction.
    ///
    /// Growth is movement. A round that *added* five hundred messages is a listing doing its job, and the two differences a drain shows its reader —
    /// `max(0, before - after)`, clamped because a reader is owed a count and not a negative number — cannot tell that from a round that achieved nothing.
    /// Two rounds that achieve nothing end a drain, so reading progress off the clamped pair means an inbox filling up from the server is called barren and
    /// the drain stops on the one case it exists for.
    ///
    /// **Compare only readings that asked the same questions.** Being an equality over the whole struct, this calls a round barren or busy on the strength of
    /// ``numberOfMessagesWaitingForAManualDownload`` too — so a reading that asked for it and one that did not always differ, whatever the inbox did. The
    /// drain compares round boundaries with round boundaries, which are asked alike.
    public func nothingMovedSince(_ other: ObvInboxCounts) -> Bool {
        self == other
    }


    /// All of them for a log line, always in the same order, so a column can be read down a log without parsing.
    public var descriptionForLogs: String {
        // The fifth says `unasked` rather than being left out, so that a column can still be read down a log — and so that *nobody counted this* cannot be
        // mistaken for *there are none*, which is the whole distinction the count was added to make.
        let waiting = numberOfMessagesWaitingForAManualDownload.map(String.init) ?? "unasked"
        let stranded = numberOfMessagesBelongingToAnInactiveOwnedIdentity.map(String.init) ?? "unasked"
        return "total=\(numberOfMessages) notYetDecrypted=\(numberOfMessagesNotYetDecrypted) awaitingTheApp=\(numberOfMessagesAwaitingTheApp) markedForDeletion=\(numberOfMessagesMarkedForDeletion) waitingForAManualDownload=\(waiting) stillToBeRemoved=\(numberOfMessagesStillToBeRemoved) ofAnInactiveProfile=\(stranded)"
    }

}

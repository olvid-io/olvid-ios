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
import CoreData
import CoreGraphics
import UniformTypeIdentifiers


/// One file attached to a message, as far as this screen is concerned.
///
/// It carries only what barely changes. The image itself is **not** here: it is asked for from the data source, by ``sha256`` and by the size it is wanted at.
/// The line this draws is what keeps a discussion of thousands of messages affordable — a message's model says *what an attachment is and roughly where it
/// stands*, and anything that moves continuously is asked for separately. A model change costs a pass over every row of the discussion, which is nothing three
/// or four times in an attachment's life and ruinous many times a second.
public struct MessageAttachment: Hashable, Sendable, Identifiable {

    /// Identifies **this attachment of this message**, which is what has to be watched to learn that its file has arrived.
    ///
    /// Distinct from ``sha256``, and both are needed: the file is shared by every message it is attached to, whereas its arrival, its progress and the small
    /// blob that stands in for it while it is on its way all belong to one attachment of one message.
    public let identifier: Identifier

    /// Identifies one attachment of one message.
    public enum Identifier: Hashable, Sendable {
        /// The object ID of a `FyleMessageJoinWithStatus`, enforced by the data source — this module knows nothing of the persistence layer. Object IDs must
        /// not escape into anything persisted or crossing a process boundary.
        case objectID(_ objectID: NSManagedObjectID)
        case forPreview(_ uuid: UUID)
    }

    /// Identifies the file itself, and is the key its image is asked for by. Known from the moment the message is — a received message's join is created with
    /// the sha256 the metadata announced, long before any byte is on disk — so it identifies an attachment that has not been downloaded just as well as one
    /// that has.
    ///
    /// Keeps its own role even now that ``identifier`` exists: keyed on the file, a photograph attached to two messages is decoded once for both.
    public let sha256: Data

    /// Where this attachment sits among the attachments of its message, and so the order they are shown in.
    public let index: Int

    public let fileName: String?
    public let fileSize: Int

    /// What kind of file this is, which is what decides how it is drawn — an image, a card, a document preview, an audio player.
    ///
    /// The one thing here that looks like state and is not: the choice it drives is made when the message's model is built, since it is what puts an attachment
    /// among the images of a message rather than among its cards.
    public let uti: String

    /// The join identifies this attachment on its own, being one row for one file of one message — so two identical photographs attached to one message do not
    /// collide, which the file alone would.
    public var id: Identifier { identifier }

    public init(identifier: Identifier, sha256: Data, index: Int, fileName: String?, fileSize: Int, uti: String) {
        self.identifier = identifier
        self.sha256 = sha256
        self.index = index
        self.fileName = fileName
        self.fileSize = fileSize
        self.uti = uti
    }

}


// MARK: - What this attachment is, and what to call it once it has left

extension MessageAttachment {

    /// What kind of file this is, for handing to another application.
    ///
    /// **The stored ``uti`` first, and the name's extension only where that cannot answer.** A name is whatever the sender, or the application a file was
    /// brought in from, chose to call it, and it may carry no extension at all; the type is what a MIME type resolved to when the file arrived, so it is
    /// right in exactly the cases the name is not. `FyleMessageJoinWithStatus.contentType` is the same expression, `UTType(uti) ?? .data`.
    ///
    /// The name is consulted for the two answers no receiving application can read: a **dynamic** identifier, which is what an unrecognised MIME type
    /// resolves to and which does occur in this database, and an **empty** ``uti``, which is what wiping an attachment leaves behind.
    ///
    /// **And it wins outright for an `m4a`**, which is the exception the app already makes where it names the file it puts on disk to be given away:
    /// Android sends `audio/mpeg` as the MIME type of an `.m4a`, so there the name is the truthful half and the database is not.
    ///
    /// Deciding this here rather than beside the name is what keeps the two from disagreeing — see ``nameForAnotherApplication``, which is the same
    /// question asked of the name.
    var contentType: UTType {
        let fromTheName = fileName
            .flatMap { UTType(filenameExtension: ($0 as NSString).pathExtension) }
            .flatMap { $0.isDeclared ? $0 : nil }
        if let fromTheName, fromTheName.conforms(to: .mpeg4Audio) { return fromTheName }
        if let fromTheDatabase = UTType(uti), fromTheDatabase.isDeclared { return fromTheDatabase }
        if let fromTheName { return fromTheName }
        return UTType(uti) ?? .data
    }


    /// The name this file should carry when it is handed to another application.
    ///
    /// **An extension that matches ``contentType``, whatever the stored name has.** A name with none — a bare UUID being the case this was found on — leaves
    /// the receiving application nothing to go on, and once a file has left, its name is the only thing that says what it is. So the rule the app already
    /// applies to the file it puts on disk to be given away is applied to the name handed over with it, the two not being allowed to disagree.
    ///
    /// The name is kept as it is wherever it already says the same thing as the type, so `photo.png` does not become `photo.png.png`.
    ///
    /// A nameless attachment is given a name to put the extension **on**, rather than being excused the rule: measured, the first version of this returned
    /// early and handed over a bare `File` for a photograph, which is the very fault it was written for.
    var nameForAnotherApplication: String {
        let name = fileName.flatMap { $0.isEmpty ? nil : $0 } ?? Self.whatANamelessFileIsCalled
        let contentType = self.contentType
        if UTType(filenameExtension: (name as NSString).pathExtension) == contentType { return name }
        guard let extensionToAdd = contentType.preferredFilenameExtension else { return name }
        return [name, extensionToAdd].joined(separator: ".")
    }


    /// What an attachment with no name of its own is called, rather than nothing at all — appending an extension to an empty name gives `.png`, which is a
    /// hidden file.
    private static let whatANamelessFileIsCalled = "File"

}


/// Where an attachment stands: whether its file is here, on its way, waiting to be asked for, or never coming.
///
/// **Streamed, and deliberately not part of ``MessageAttachment``.** A status carried in a message's model is right at the instant that model is built and stale
/// for ever after, Core Data not reporting a message as changed when one of its joins changes. Everything that changes about an attachment comes from the
/// stream that watches its join.
///
/// There is no `paused` case, because there is no such status: a paused attachment reads as ``downloadable``, and what tells the two apart is how much of the
/// file exists. Which is exactly what the control shows — the arc follows the bytes, and the glyph follows whether a download is in flight — so "paused at 30%"
/// needs no case of its own.
public struct AttachmentState: Sendable, Equatable {

    public let phase: Phase

    /// The best picture there is so far, which is not the same question as the phase: a message carries a small blurred stand-in for a file it does not have,
    /// and that stand-in is what the control is drawn *on*. So an attachment waiting to be asked for may perfectly well have an image, and one whose file has
    /// arrived may not have been decoded yet.
    public let image: CGImage?

    public init(phase: Phase, image: CGImage?) {
        self.phase = phase
        self.image = image
    }

    public enum Phase: Sendable, Equatable {

        /// Waiting to be asked for, or paused. An attachment is not fetched automatically when it is larger than the size the reader has set — 10MB by default
        /// — which is why a photograph usually arrives by itself and a video usually does not.
        case downloadable

        /// The reader has asked for it and the engine has not answered yet. Entered on the tap itself, so that the control acknowledges at once rather than
        /// after a round trip, which is what the legacy screen makes the reader wait for.
        case askedToDownload

        /// Bytes are moving.
        case downloading

        /// The file is here, and its bytes are still going **out**.
        ///
        /// **An upload is not a download in reverse, and this phase says so.** A sent attachment's file is on this device from the
        /// start — it is what the reader chose — so the picture is available at once and only the *transfer* is pending. That is why
        /// this phase carries a thumbnail like ``available`` and unlike ``downloading``, and why it takes **no tap**: there is nothing
        /// to ask for and, by decision, nothing to pause. Deleting the message is how an upload is stopped, which the app already does
        /// through `CancelUploadOrDownloadOfPersistedMessagesOperation`.
        ///
        /// Covers the legacy `uploadable` *and* `uploading` statuses, which `SentMessageCell` also treats as one — an attachment
        /// waiting its turn shows an empty arc rather than nothing.
        case uploading

        /// The file is here.
        case available

        /// It is never coming.
        case cancelledByServer

        /// The message came from a history transfer and the reader chose **not** to bring this file over — the legacy `untransferred`.
        ///
        /// There is nothing to download, ever, and no server that has it: this is not an attachment that has failed to arrive but one that was deliberately left
        /// behind. So the control draws a glyph and takes no tap at all, which is `isUserInteractionEnabled = false` on the legacy screen. Offering a download here
        /// offers something that can only fail, and that is what Step 30 exists to stop.
        case leftBehindByAHistoryTransfer

        /// The attachment is known only because a notification created its join, ahead of the message itself — the legacy
        /// `notYetDownloadableAsReceivedByUserNotification`.
        ///
        /// **Premature rather than wrong**: it becomes downloadable on its own once the message arrives, without being asked. So the control says so and takes no
        /// tap, rather than offering a download that would do nothing useful yet.
        case knownOnlyFromANotification

    }

}


/// What the reader can ask of an attachment.
///
/// Each case names what it does, and nothing names the undoing of something else: a control whose meaning depends on remembering which state it was in cannot
/// be reasoned about, on the screen or in the code.
///
/// Starting a download and continuing one are the same case, deliberately. They are one call to the engine, which names it `resumeDownloadOfAttachment` even
/// for a download that has never begun — and a view could not choose between two names anyway, an attachment waiting to be asked for and one paused at nought
/// per cent being the same attachment.
public enum AttachmentAction: Sendable {
    case resumeDownload
    case pauseDownload
}


/// What the reader can ask of a recording.
///
/// Apart from ``AttachmentAction`` because it is a different question about a different thing: one is about getting hold of a file, the other about listening to it,
/// and an attachment can be in the middle of both at once.
///
/// `play` covers starting and continuing, as `resumeDownload` does — a recording paused half-way and one never started are the same recording, and a view cannot be
/// asked to remember which.
public enum AudioAction: Sendable {

    /// Play, from a stated place in the recording between 0 and 1.
    ///
    /// **The place comes from the view, and that is the whole of how scrubbing works.** A recording the player has never held has no position anywhere else: the app
    /// keeps one position, for one recording, and knows nothing of where a reader dragged to on a recording that has never sounded. So the view holds the position it
    /// is *showing* and says where to start, exactly as on the legacy screen, where a drag moves a local `progress` and the play button computes its time from it.
    case play(fromFraction: Double)

    case pause

    /// Where the recording now stands, with no sound made — a reader dragging along a recording that is paused, or one that has never sounded at all.
    ///
    /// The position would otherwise live only in the view showing it, and be lost with the row when a scroll recycles it.
    ///
    /// **The length comes with it because the view is the one that knows it.** A recording the player is not holding has nobody to ask, and the view has already
    /// measured the file to draw its waveform. Where the player *is* holding it, its own length is used instead and this one is ignored: a position is drawn as a
    /// fraction of the length reported beside it, so the two must be the same length.
    case standsAt(fraction: Double, ofRecordingLasting: TimeInterval)

    /// How fast to play, which the reader changes by tapping the capsule beside the waveform.
    ///
    /// The rate asked for, and not "the next one": what a button does should be legible from the action it sends. That the capsule cycles is the *view's* business,
    /// which is why the order lives on ``AudioPlaybackRate`` rather than in whatever carries this out.
    case setRate(AudioPlaybackRate)

}


/// How fast a recording is played. `ObvAudioPlayer.PlayRate` on the app side.
public enum AudioPlaybackRate: Double, Sendable, CaseIterable {

    case ordinary = 1
    case oneAndAHalf = 1.5
    case double = 2

    /// What tapping the capsule asks for, ordinary following double.
    public var next: Self {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return .ordinary }
        return all[(index + 1) % all.count]
    }

    /// "1 x", as `ObvAudioPlayer.PlayRate.title` composes it: the number as the reader's locale writes it, and a suffix.
    public var title: String {
        "\(rawValue.formatted(.number)) x"
    }

}

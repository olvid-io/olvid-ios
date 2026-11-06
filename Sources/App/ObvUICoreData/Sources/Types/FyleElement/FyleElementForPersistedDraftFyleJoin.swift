/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import UniformTypeIdentifiers
import ObvAppTypes
import ObvSettings


public struct FyleElementForPersistedDraftFyleJoin: FyleElement, Sendable {

    public let fyleURL: URL
    public let fileName: String
    public let contentType: UTType
    //public let uti: String
    public let sha256: Data
    public let fullFileIsAvailable: Bool

    let discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>
    let draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>
    let draftFyleJoinPermanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin>

    /// Which of an attachment's files this element names, the two differing for a photograph as soon as the reader picks a size that had
    /// to be re-encoded.
    public enum WhichFile {

        /// The file exactly as it was attached.
        ///
        /// **What the thumbnail in the composition bar is drawn from, and that is not a preference.** The caches that hold those
        /// hardlinks — `AttachmentThumbnailManager.hardlinkForDraftFyleObjectID` and its audio sibling — are keyed by the join's object
        /// ID, are never invalidated, and check only that the file they remember is still on disk. A hardlink that followed the chosen
        /// size would move underneath them and they would go on serving the first one for ever. Naming the attached file instead makes
        /// the hardlink a fact about the attachment rather than about the current choice, so there is nothing to invalidate.
        case asAttached

        /// The file that will actually leave the device — for a photograph, whichever size is chosen.
        ///
        /// What QuickLook is given, so that opening an attachment shows what the recipient will get rather than what the camera
        /// produced. Safe to follow the choice because `FilesViewer` is built afresh on each tap and caches hardlinks only for its own
        /// lifetime, where the thumbnail caches are static and live as long as the process.
        case asItWillBeSent

    }


    init?(_ persistedDraftFyleJoin: PersistedDraftFyleJoin, _ whichFile: WhichFile) {

        guard let draft = persistedDraftFyleJoin.draft else { return nil }
        guard let draftObjectPermanentID = try? draft.objectPermanentID else { return nil }
        guard let persistedDraftFyleJoinObjectPermanentID = try? persistedDraftFyleJoin.objectPermanentID else { return nil }

        let fyle: Fyle
        switch whichFile {
        case .asAttached:
            guard let originalFyle = persistedDraftFyleJoin.originalFyle else { return nil }
            fyle = originalFyle
            // The `max` variant carries the name and type the file was attached under; the join's own have moved if a size has been
            // chosen. Falling back to the join is right for everything with no variants at all — anything that is not a photograph, and
            // a photograph attached before sizes existed — since nothing has moved there either.
            let original = persistedDraftFyleJoin.variant(for: .max)
            self.fileName = original?.fileName ?? persistedDraftFyleJoin.fileName
            self.contentType = original?.contentType ?? persistedDraftFyleJoin.contentType
        case .asItWillBeSent:
            guard let fyleToSend = persistedDraftFyleJoin.fyle else { return nil }
            fyle = fyleToSend
            // The join's own three properties mean *what will be sent*, which is the whole invariant this feature rests on.
            self.fileName = persistedDraftFyleJoin.fileName
            self.contentType = persistedDraftFyleJoin.contentType
        }

        self.fyleURL = fyle.url
        self.sha256 = fyle.sha256
        self.discussionPermanentID = draft.discussion.discussionPermanentID
        self.draftPermanentID = draftObjectPermanentID
        self.draftFyleJoinPermanentID = persistedDraftFyleJoinObjectPermanentID
        self.fullFileIsAvailable = true

    }


    private init(fyleURL: URL, fileName: String, contentType: UTType, sha256: Data, fullFileIsAvailable: Bool, discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, draftFyleJoinPermanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin>) {
        self.fyleURL = fyleURL
        self.fileName = fileName
        self.contentType = contentType
        self.sha256 = sha256
        self.fullFileIsAvailable = fullFileIsAvailable
        self.discussionPermanentID = discussionPermanentID
        self.draftPermanentID = draftPermanentID
        self.draftFyleJoinPermanentID = draftFyleJoinPermanentID
    }


    public func replacingFullFileIsAvailable(with newFullFileIsAvailable: Bool) -> FyleElement {
        Self.init(fyleURL: fyleURL,
                  fileName: fileName,
                  contentType: contentType,
                  sha256: sha256,
                  fullFileIsAvailable: newFullFileIsAvailable,
                  discussionPermanentID: discussionPermanentID,
                  draftPermanentID: draftPermanentID,
                  draftFyleJoinPermanentID: draftFyleJoinPermanentID)
    }


    public static func makeError(message: String) -> Error { NSError(domain: "FyleElementForPersistedDraftFyleJoin", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    private static func discussionDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, in currentSessionDirectoryForHardlinks: URL) -> URL {
        FyleElementForFyleMessageJoinWithStatus.discussionDirectory(discussionPermanentID: discussionPermanentID, in: currentSessionDirectoryForHardlinks)
    }

    private static func draftDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, in currentSessionDirectoryForHardlinks: URL) -> URL {
        let directory = draftPermanentID.description.escapedStringForFyleElementDirectoryOrFilename()
        return discussionDirectory(discussionPermanentID: discussionPermanentID, in: currentSessionDirectoryForHardlinks)
            .appendingPathComponent(directory, isDirectory: true)
    }

    private static func fyleMessageJoinWithStatusDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, draftFyleJoinPermanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin>, in currentSessionDirectoryForHardlinks: URL) -> URL {
        let directory = draftFyleJoinPermanentID.description.escapedStringForFyleElementDirectoryOrFilename()
        return draftDirectory(discussionPermanentID: discussionPermanentID, draftPermanentID: draftPermanentID, in: currentSessionDirectoryForHardlinks)
            .appendingPathComponent(directory, isDirectory: true)
    }

    /// Where this attachment's hardlink goes: a directory per join, and **within it a directory per file**.
    ///
    /// The per-file directory keeps the sizes apart: Low, Med and Hi share one name (`IMG_4021.jpeg`), and `HardLinkToFyle` does nothing
    /// when the path exists, so the first size opened would otherwise be shown for all of them. Keyed on the file, so sizes sharing a file
    /// share a hardlink. Everything stays under the join's directory, which is trashed with the attachment or the draft.
    public func directoryForHardLink(in currentSessionDirectoryForHardlinks: URL) -> URL {
        FyleElementForPersistedDraftFyleJoin.fyleMessageJoinWithStatusDirectory(
            discussionPermanentID: discussionPermanentID,
            draftPermanentID: draftPermanentID,
            draftFyleJoinPermanentID: draftFyleJoinPermanentID,
            in: currentSessionDirectoryForHardlinks)
        .appendingPathComponent(sha256.hexString(), isDirectory: true)
    }

    public static func trashDraftDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrash = draftDirectory(discussionPermanentID: discussionPermanentID, draftPermanentID: draftPermanentID, in: currentSessionDirectoryForHardlinks)
        let trashURL = ObvUICoreDataConstants.ContainerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrash.path) else { return }
        try FileManager.default.moveItem(at: urlToTrash, to: trashURL)
    }

    public static func trashDraftFyleJoinDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, draftFyleJoinPermanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin>, in currentSessionDirectoryForHardlinks: URL) throws {
        let directory = draftFyleJoinPermanentID.description.escapedStringForFyleElementDirectoryOrFilename()
        let urlToTrash = draftDirectory(discussionPermanentID: discussionPermanentID, draftPermanentID: draftPermanentID, in: currentSessionDirectoryForHardlinks)
            .appendingPathComponent(directory, isDirectory: true)
        let trashURL = ObvUICoreDataConstants.ContainerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrash.path) else { return }
        try FileManager.default.moveItem(at: urlToTrash, to: trashURL)
    }
}



// MARK: - FyleElement from a PersistedDraftFyleJoin

public extension PersistedDraftFyleJoin {

    /// The attachment as it was added to the draft. See ``FyleElementForPersistedDraftFyleJoin/WhichFile/asAttached``.
    var fyleElement: FyleElement? {
        FyleElementForPersistedDraftFyleJoin(self, .asAttached)
    }

    /// The attachment as it will leave the device. See ``FyleElementForPersistedDraftFyleJoin/WhichFile/asItWillBeSent``.
    var fyleElementOfTheFileThatWillBeSent: FyleElement? {
        FyleElementForPersistedDraftFyleJoin(self, .asItWillBeSent)
    }

}

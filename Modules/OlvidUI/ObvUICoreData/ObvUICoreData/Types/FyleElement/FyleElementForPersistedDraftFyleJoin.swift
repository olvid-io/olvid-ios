/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvSettings


public struct FyleElementForPersistedDraftFyleJoin: FyleElement {

    public let fyleURL: URL
    public let fileName: String
    public let contentType: UTType
    //public let uti: String
    public let sha256: Data
    public let fullFileIsAvailable: Bool

    let discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>
    let draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>
    let draftFyleJoinPermanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin>

    init?(_ persistedDraftFyleJoin: PersistedDraftFyleJoin) {
        guard let fyle = persistedDraftFyleJoin.fyle else { return nil }
        guard let draft = persistedDraftFyleJoin.draft else { return nil }
        self.fyleURL = fyle.url
        self.fileName = persistedDraftFyleJoin.fileName
        self.contentType = persistedDraftFyleJoin.contentType
        self.sha256 = fyle.sha256
        self.discussionPermanentID = draft.discussion.discussionPermanentID
        self.draftPermanentID = draft.objectPermanentID
        self.draftFyleJoinPermanentID = persistedDraftFyleJoin.objectPermanentID
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
        let directory = draftPermanentID.description.replacingOccurrences(of: "/", with: "_")
        return discussionDirectory(discussionPermanentID: discussionPermanentID, in: currentSessionDirectoryForHardlinks)
            .appendingPathComponent(directory, isDirectory: true)
    }

    private static func fyleMessageJoinWithStatusDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, draftFyleJoinPermanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin>, in currentSessionDirectoryForHardlinks: URL) -> URL {
        let directory = draftFyleJoinPermanentID.description.replacingOccurrences(of: "/", with: "_")
        return draftDirectory(discussionPermanentID: discussionPermanentID, draftPermanentID: draftPermanentID, in: currentSessionDirectoryForHardlinks)
            .appendingPathComponent(directory, isDirectory: true)
    }

    public func directoryForHardLink(in currentSessionDirectoryForHardlinks: URL) -> URL {
        FyleElementForPersistedDraftFyleJoin.fyleMessageJoinWithStatusDirectory(
            discussionPermanentID: discussionPermanentID,
            draftPermanentID: draftPermanentID,
            draftFyleJoinPermanentID: draftFyleJoinPermanentID,
            in: currentSessionDirectoryForHardlinks)
    }

    public static func trashDraftDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrash = draftDirectory(discussionPermanentID: discussionPermanentID, draftPermanentID: draftPermanentID, in: currentSessionDirectoryForHardlinks)
        let trashURL = ObvUICoreDataConstants.ContainerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrash.path) else { return }
        try FileManager.default.moveItem(at: urlToTrash, to: trashURL)
    }

    public static func trashDraftFyleJoinDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, draftFyleJoinPermanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin>, in currentSessionDirectoryForHardlinks: URL) throws {
        let directory = draftFyleJoinPermanentID.description.replacingOccurrences(of: "/", with: "_")
        let urlToTrash = draftDirectory(discussionPermanentID: discussionPermanentID, draftPermanentID: draftPermanentID, in: currentSessionDirectoryForHardlinks)
            .appendingPathComponent(directory, isDirectory: true)
        let trashURL = ObvUICoreDataConstants.ContainerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrash.path) else { return }
        try FileManager.default.moveItem(at: urlToTrash, to: trashURL)
    }
}



// MARK: - FyleElement from a PersistedDraftFyleJoin

public extension PersistedDraftFyleJoin {
    
    var fyleElement: FyleElement? {
        FyleElementForPersistedDraftFyleJoin(self)
    }
    
}

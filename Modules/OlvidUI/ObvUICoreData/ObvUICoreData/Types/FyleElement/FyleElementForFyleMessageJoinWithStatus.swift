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


public struct FyleElementForFyleMessageJoinWithStatus: FyleElement {

    public let fyleURL: URL
    public let fileName: String
    //public let uti: String
    public let contentType: UTType
    public let sha256: Data
    public let fullFileIsAvailable: Bool

    let discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>
    let messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>
    let fyleMessageJoinPermanentID: ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>

    public init(fyleURL: URL, fileName: String, contentType: UTType, sha256: Data, fullFileIsAvailable: Bool, discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, fyleMessageJoinPermanentID: ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>) {
        self.fyleURL = fyleURL
        self.fileName = fileName
        self.contentType = contentType
        self.sha256 = sha256
        self.fullFileIsAvailable = fullFileIsAvailable
        self.discussionPermanentID = discussionPermanentID
        self.messagePermanentID = messagePermanentID
        self.fyleMessageJoinPermanentID = fyleMessageJoinPermanentID
    }

    init?(_ fyleMessageJoinWithStatus: FyleMessageJoinWithStatus) throws {
        
        guard let fyle = fyleMessageJoinWithStatus.fyle else { return nil }
        guard let message = fyleMessageJoinWithStatus.message else { return nil }
        let fyleURL = fyle.url
        
        guard let discussionPermanentID = message.discussion?.discussionPermanentID else {
            throw Self.makeError(message: "Could not find discussion")
        }

        self.init(fyleURL: fyleURL,
                  fileName: fyleMessageJoinWithStatus.fileName,
                  contentType: fyleMessageJoinWithStatus.contentType,
                  sha256: fyle.sha256,
                  fullFileIsAvailable: fyleMessageJoinWithStatus.fullFileIsAvailable,
                  discussionPermanentID: discussionPermanentID,
                  messagePermanentID: message.messagePermanentID,
                  fyleMessageJoinPermanentID: fyleMessageJoinWithStatus.fyleMessageJoinPermanentID)
    }

    public func replacingFullFileIsAvailable(with newFullFileIsAvailable: Bool) -> FyleElement {
        Self.init(fyleURL: fyleURL,
                  fileName: fileName,
                  contentType: contentType,
                  sha256: sha256,
                  fullFileIsAvailable: newFullFileIsAvailable,
                  discussionPermanentID: discussionPermanentID,
                  messagePermanentID: messagePermanentID,
                  fyleMessageJoinPermanentID: fyleMessageJoinPermanentID)
    }

    public static func makeError(message: String) -> Error { NSError(domain: "FyleElementForFyleMessageJoinWithStatus", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    public static func discussionDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, in currentSessionDirectoryForHardlinks: URL) -> URL {
        let directory = discussionPermanentID.description.replacingOccurrences(of: "/", with: "_")
        return currentSessionDirectoryForHardlinks
            .appendingPathComponent(directory, isDirectory: true)
    }


    public static func messageDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, in currentSessionDirectoryForHardlinks: URL) -> URL {
        let directory = messagePermanentID.description.replacingOccurrences(of: "/", with: "_")
        return discussionDirectory(discussionPermanentID: discussionPermanentID, in: currentSessionDirectoryForHardlinks)
            .appendingPathComponent(directory, isDirectory: true)
    }


    public static func fyleMessageJoinWithStatusDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, fyleMessageJoinPermanentID: ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>, in currentSessionDirectoryForHardlinks: URL) -> URL {
        let directory = fyleMessageJoinPermanentID.description.replacingOccurrences(of: "/", with: "_")
        return messageDirectory(discussionPermanentID: discussionPermanentID, messagePermanentID: messagePermanentID, in: currentSessionDirectoryForHardlinks)
            .appendingPathComponent(directory, isDirectory: true)
    }
    

    public func directoryForHardLink(in currentSessionDirectoryForHardlinks: URL) -> URL {
        FyleElementForFyleMessageJoinWithStatus.fyleMessageJoinWithStatusDirectory(
            discussionPermanentID: discussionPermanentID,
            messagePermanentID: messagePermanentID,
            fyleMessageJoinPermanentID: fyleMessageJoinPermanentID,
            in: currentSessionDirectoryForHardlinks)
    }
}


extension FyleElementForFyleMessageJoinWithStatus {

    public static func trashDiscussionDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrash = discussionDirectory(discussionPermanentID: discussionPermanentID, in: currentSessionDirectoryForHardlinks)
        let trashURL = ObvUICoreDataConstants.ContainerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrash.path) else { return }
        try FileManager.default.moveItem(at: urlToTrash, to: trashURL)
    }

    public static func trashDiscussionDirectoryIfEmpty(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrashIfEmpty = discussionDirectory(discussionPermanentID: discussionPermanentID, in: currentSessionDirectoryForHardlinks)
        guard FileManager.default.isDirectory(url: urlToTrashIfEmpty) else { return }
        let contents = try FileManager.default.contentsOfDirectory(at: urlToTrashIfEmpty, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        guard contents.isEmpty else { return }
        let trashURL = ObvUICoreDataConstants.ContainerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrashIfEmpty.path) else { return }
        try FileManager.default.moveItem(at: urlToTrashIfEmpty, to: trashURL)
    }

    public static func trashMessageDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrash = messageDirectory(discussionPermanentID: discussionPermanentID, messagePermanentID: messagePermanentID, in: currentSessionDirectoryForHardlinks)
        let trashURL = ObvUICoreDataConstants.ContainerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrash.path) else { return }
        try FileManager.default.moveItem(at: urlToTrash, to: trashURL)
    }

    public static func trashMessageDirectoryIfEmpty(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrashIfEmpty = messageDirectory(discussionPermanentID: discussionPermanentID, messagePermanentID: messagePermanentID, in: currentSessionDirectoryForHardlinks)
        guard FileManager.default.isDirectory(url: urlToTrashIfEmpty) else { return }
        try trashMessageDirectory(discussionPermanentID: discussionPermanentID, messagePermanentID: messagePermanentID, in: currentSessionDirectoryForHardlinks)
    }

    public static func trashFyleMessageJoinWithStatusDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, fyleMessageJoinPermanentID: ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrash = fyleMessageJoinWithStatusDirectory(discussionPermanentID: discussionPermanentID, messagePermanentID: messagePermanentID, fyleMessageJoinPermanentID: fyleMessageJoinPermanentID, in: currentSessionDirectoryForHardlinks)
        let trashURL = ObvUICoreDataConstants.ContainerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrash.path) else { return }
        try FileManager.default.moveItem(at: urlToTrash, to: trashURL)
    }
}


fileprivate extension FileManager {

    func isDirectory(url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = self.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else { return false }
        return isDirectory.boolValue
    }

}

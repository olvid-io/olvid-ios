/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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


protocol FyleElement {
    var fileName: String { get }
    var uti: String { get }
    var fullFileIsAvailable: Bool { get }
    var fyleURL: URL { get }
    var sha256: Data { get }
    func directoryForHardLink(in currentSessionDirectoryForHardlinks: URL) -> URL
    func replacingFullFileIsAvailable(with newFullFileIsAvailable: Bool) -> FyleElement
    static func makeError(message: String) -> Error
}

extension FyleElement {

    /// Used by subclasses to determine an appropraite filename
    fileprivate static func appropriateFilenameForFilename(fileName: String, uti: String) throws -> String {
        let appropriateFileName: String
        if ObvUTIUtils.utiOfFile(withName: fileName) != nil {
            appropriateFileName = fileName
        } else {
            guard let filenameExtension = ObvUTIUtils.preferredTagWithClass(inUTI: uti, inTagClass: .FilenameExtension) else { assertionFailure(); throw makeError(message: "Could not determine UTI") }
            appropriateFileName = [fileName, filenameExtension].joined(separator: ".")
        }
        assert(ObvUTIUtils.utiOfFile(withName: appropriateFileName) != nil)
        return appropriateFileName
    }

}

struct FyleElementForPersistedDraftFyleJoin: FyleElement {

    let fyleURL: URL
    let fileName: String
    let uti: String
    let sha256: Data
    let fullFileIsAvailable: Bool

    let discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>
    let draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>
    let draftFyleJoinPermanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin>

    init?(_ persistedDraftFyleJoin: PersistedDraftFyleJoin) {
        guard let fyle = persistedDraftFyleJoin.fyle else { return nil }
        guard let draft = persistedDraftFyleJoin.draft else { return nil }
        self.fyleURL = fyle.url
        self.fileName = persistedDraftFyleJoin.fileName
        self.uti = persistedDraftFyleJoin.uti
        self.sha256 = fyle.sha256
        self.discussionPermanentID = draft.discussion.discussionPermanentID
        self.draftPermanentID = draft.objectPermanentID
        self.draftFyleJoinPermanentID = persistedDraftFyleJoin.objectPermanentID
        self.fullFileIsAvailable = true
    }


    private init(fyleURL: URL, fileName: String, uti: String, sha256: Data, fullFileIsAvailable: Bool, discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, draftFyleJoinPermanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin>) {
        self.fyleURL = fyleURL
        self.fileName = fileName
        self.uti = uti
        self.sha256 = sha256
        self.fullFileIsAvailable = fullFileIsAvailable
        self.discussionPermanentID = discussionPermanentID
        self.draftPermanentID = draftPermanentID
        self.draftFyleJoinPermanentID = draftFyleJoinPermanentID
    }


    func replacingFullFileIsAvailable(with newFullFileIsAvailable: Bool) -> FyleElement {
        FyleElementForPersistedDraftFyleJoin(fyleURL: fyleURL,
                                             fileName: fileName,
                                             uti: uti,
                                             sha256: sha256,
                                             fullFileIsAvailable: newFullFileIsAvailable,
                                             discussionPermanentID: discussionPermanentID,
                                             draftPermanentID: draftPermanentID,
                                             draftFyleJoinPermanentID: draftFyleJoinPermanentID)
    }


    static func makeError(message: String) -> Error { NSError(domain: "FyleElementForPersistedDraftFyleJoin", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

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

    func directoryForHardLink(in currentSessionDirectoryForHardlinks: URL) -> URL {
        FyleElementForPersistedDraftFyleJoin.fyleMessageJoinWithStatusDirectory(
            discussionPermanentID: discussionPermanentID,
            draftPermanentID: draftPermanentID,
            draftFyleJoinPermanentID: draftFyleJoinPermanentID,
            in: currentSessionDirectoryForHardlinks)
    }

    static func trashDraftDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrash = draftDirectory(discussionPermanentID: discussionPermanentID, draftPermanentID: draftPermanentID, in: currentSessionDirectoryForHardlinks)
        let trashURL = ObvMessengerConstants.containerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrash.path) else { return }
        try FileManager.default.moveItem(at: urlToTrash, to: trashURL)
    }

    static func trashDraftFyleJoinDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, draftFyleJoinPermanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin>, in currentSessionDirectoryForHardlinks: URL) throws {
        let directory = draftFyleJoinPermanentID.description.replacingOccurrences(of: "/", with: "_")
        let urlToTrash = draftDirectory(discussionPermanentID: discussionPermanentID, draftPermanentID: draftPermanentID, in: currentSessionDirectoryForHardlinks)
            .appendingPathComponent(directory, isDirectory: true)
        let trashURL = ObvMessengerConstants.containerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrash.path) else { return }
        try FileManager.default.moveItem(at: urlToTrash, to: trashURL)
    }
}


struct FyleElementForFyleMessageJoinWithStatus: FyleElement {

    let fyleURL: URL
    let fileName: String
    let uti: String
    let sha256: Data
    let fullFileIsAvailable: Bool

    let discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>
    let messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>
    let fyleMessageJoinPermanentID: ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>

    init?(_ fyleMessageJoinWithStatus: FyleMessageJoinWithStatus) throws {
        guard let fyle = fyleMessageJoinWithStatus.fyle else { return nil }
        guard let message = fyleMessageJoinWithStatus.message else { return nil }
        self.fyleURL = fyle.url
        self.fileName = fyleMessageJoinWithStatus.fileName
        self.uti = fyleMessageJoinWithStatus.uti
        self.sha256 = fyle.sha256
        self.discussionPermanentID = message.discussion.discussionPermanentID
        self.messagePermanentID = message.messagePermanentID
        self.fyleMessageJoinPermanentID = fyleMessageJoinWithStatus.fyleMessageJoinPermanentID
        self.fullFileIsAvailable = fyleMessageJoinWithStatus.fullFileIsAvailable
    }

    private init(fyleURL: URL, fileName: String, uti: String, sha256: Data, fullFileIsAvailable: Bool, discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, fyleMessageJoinPermanentID: ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>) {
        self.fyleURL = fyleURL
        self.fileName = fileName
        self.uti = uti
        self.sha256 = sha256
        self.fullFileIsAvailable = fullFileIsAvailable
        self.discussionPermanentID = discussionPermanentID
        self.messagePermanentID = messagePermanentID
        self.fyleMessageJoinPermanentID = fyleMessageJoinPermanentID
    }


    func replacingFullFileIsAvailable(with newFullFileIsAvailable: Bool) -> FyleElement {
        FyleElementForFyleMessageJoinWithStatus(fyleURL: fyleURL,
                                                fileName: fileName,
                                                uti: uti,
                                                sha256: sha256,
                                                fullFileIsAvailable: newFullFileIsAvailable,
                                                discussionPermanentID: discussionPermanentID,
                                                messagePermanentID: messagePermanentID,
                                                fyleMessageJoinPermanentID: fyleMessageJoinPermanentID)
    }

    static func makeError(message: String) -> Error { NSError(domain: "FyleElementForFyleMessageJoinWithStatus", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    fileprivate static func discussionDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, in currentSessionDirectoryForHardlinks: URL) -> URL {
        let directory = discussionPermanentID.description.replacingOccurrences(of: "/", with: "_")
        return currentSessionDirectoryForHardlinks
            .appendingPathComponent(directory, isDirectory: true)
    }


    private static func messageDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, in currentSessionDirectoryForHardlinks: URL) -> URL {
        let directory = messagePermanentID.description.replacingOccurrences(of: "/", with: "_")
        return discussionDirectory(discussionPermanentID: discussionPermanentID, in: currentSessionDirectoryForHardlinks)
            .appendingPathComponent(directory, isDirectory: true)
    }


    private static func fyleMessageJoinWithStatusDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, fyleMessageJoinPermanentID: ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>, in currentSessionDirectoryForHardlinks: URL) -> URL {
        let directory = fyleMessageJoinPermanentID.description.replacingOccurrences(of: "/", with: "_")
        return messageDirectory(discussionPermanentID: discussionPermanentID, messagePermanentID: messagePermanentID, in: currentSessionDirectoryForHardlinks)
            .appendingPathComponent(directory, isDirectory: true)
    }
    

    func directoryForHardLink(in currentSessionDirectoryForHardlinks: URL) -> URL {
        FyleElementForFyleMessageJoinWithStatus.fyleMessageJoinWithStatusDirectory(
            discussionPermanentID: discussionPermanentID,
            messagePermanentID: messagePermanentID,
            fyleMessageJoinPermanentID: fyleMessageJoinPermanentID,
            in: currentSessionDirectoryForHardlinks)
    }

    static func trashDiscussionDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrash = discussionDirectory(discussionPermanentID: discussionPermanentID, in: currentSessionDirectoryForHardlinks)
        let trashURL = ObvMessengerConstants.containerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrash.path) else { return }
        try FileManager.default.moveItem(at: urlToTrash, to: trashURL)
    }

    static func trashDiscussionDirectoryIfEmpty(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrashIfEmpty = discussionDirectory(discussionPermanentID: discussionPermanentID, in: currentSessionDirectoryForHardlinks)
        guard FileManager.default.isDirectory(url: urlToTrashIfEmpty) else { return }
        let contents = try FileManager.default.contentsOfDirectory(at: urlToTrashIfEmpty, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        guard contents.isEmpty else { return }
        let trashURL = ObvMessengerConstants.containerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrashIfEmpty.path) else { return }
        try FileManager.default.moveItem(at: urlToTrashIfEmpty, to: trashURL)
    }

    static func trashMessageDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrash = messageDirectory(discussionPermanentID: discussionPermanentID, messagePermanentID: messagePermanentID, in: currentSessionDirectoryForHardlinks)
        let trashURL = ObvMessengerConstants.containerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrash.path) else { return }
        try FileManager.default.moveItem(at: urlToTrash, to: trashURL)
    }

    
    static func trashMessageDirectoryIfEmpty(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrashIfEmpty = messageDirectory(discussionPermanentID: discussionPermanentID, messagePermanentID: messagePermanentID, in: currentSessionDirectoryForHardlinks)
        guard FileManager.default.isDirectory(url: urlToTrashIfEmpty) else { return }
        try trashMessageDirectory(discussionPermanentID: discussionPermanentID, messagePermanentID: messagePermanentID, in: currentSessionDirectoryForHardlinks)
    }

    
    static func trashFyleMessageJoinWithStatusDirectory(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, fyleMessageJoinPermanentID: ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrash = fyleMessageJoinWithStatusDirectory(discussionPermanentID: discussionPermanentID, messagePermanentID: messagePermanentID, fyleMessageJoinPermanentID: fyleMessageJoinPermanentID, in: currentSessionDirectoryForHardlinks)
        let trashURL = ObvMessengerConstants.containerURL.forTrash.appendingPathComponent(UUID().uuidString)
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

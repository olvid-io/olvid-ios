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

    let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
    let draftObjectID: TypeSafeManagedObjectID<PersistedDraft>
    let persistedDraftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>

    init?(_ persistedDraftFyleJoin: PersistedDraftFyleJoin) {
        guard let fyle = persistedDraftFyleJoin.fyle else { return nil }
        self.fyleURL = fyle.url
        self.fileName = persistedDraftFyleJoin.fileName
        self.uti = persistedDraftFyleJoin.uti
        self.sha256 = fyle.sha256
        self.discussionObjectID = persistedDraftFyleJoin.draft.discussion.typedObjectID
        self.draftObjectID = persistedDraftFyleJoin.draft.typedObjectID
        self.persistedDraftFyleJoinObjectID = persistedDraftFyleJoin.typedObjectID
        self.fullFileIsAvailable = true
    }


    private init(fyleURL: URL, fileName: String, uti: String, sha256: Data, fullFileIsAvailable: Bool, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, persistedDraftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>) {
        self.fyleURL = fyleURL
        self.fileName = fileName
        self.uti = uti
        self.sha256 = sha256
        self.fullFileIsAvailable = fullFileIsAvailable
        self.discussionObjectID = discussionObjectID
        self.draftObjectID = draftObjectID
        self.persistedDraftFyleJoinObjectID = persistedDraftFyleJoinObjectID
    }


    func replacingFullFileIsAvailable(with newFullFileIsAvailable: Bool) -> FyleElement {
        FyleElementForPersistedDraftFyleJoin(fyleURL: fyleURL,
                                             fileName: fileName,
                                             uti: uti,
                                             sha256: sha256,
                                             fullFileIsAvailable: newFullFileIsAvailable,
                                             discussionObjectID: discussionObjectID,
                                             draftObjectID: draftObjectID,
                                             persistedDraftFyleJoinObjectID: persistedDraftFyleJoinObjectID)
    }


    static func makeError(message: String) -> Error { NSError(domain: "FyleElementForPersistedDraftFyleJoin", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    private static func discussionDirectory(discussionURIRepresentation: TypeSafeURL<PersistedDiscussion>, in currentSessionDirectoryForHardlinks: URL) -> URL {
        FyleElementForFyleMessageJoinWithStatus.discussionDirectory(discussionURIRepresentation: discussionURIRepresentation, in: currentSessionDirectoryForHardlinks)
    }

    private static func draftDirectory(discussionURIRepresentation: TypeSafeURL<PersistedDiscussion>, draftURIRepresentation: TypeSafeURL<PersistedDraft>, in currentSessionDirectoryForHardlinks: URL) -> URL {
        let directory = draftURIRepresentation.path.replacingOccurrences(of: "/", with: "_")
        return discussionDirectory(discussionURIRepresentation: discussionURIRepresentation, in: currentSessionDirectoryForHardlinks)
            .appendingPathComponent(directory, isDirectory: true)
    }

    private static func fyleMessageJoinWithStatusDirectory(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, persistedDraftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>, in currentSessionDirectoryForHardlinks: URL) -> URL {
        let directory = persistedDraftFyleJoinObjectID.uriRepresentation().path.replacingOccurrences(of: "/", with: "_")
        return draftDirectory(discussionURIRepresentation: discussionObjectID.uriRepresentation(), draftURIRepresentation: draftObjectID.uriRepresentation(), in: currentSessionDirectoryForHardlinks)
            .appendingPathComponent(directory, isDirectory: true)
    }

    func directoryForHardLink(in currentSessionDirectoryForHardlinks: URL) -> URL {
        FyleElementForPersistedDraftFyleJoin.fyleMessageJoinWithStatusDirectory(
            discussionObjectID: discussionObjectID,
            draftObjectID: draftObjectID,
            persistedDraftFyleJoinObjectID: persistedDraftFyleJoinObjectID,
            in: currentSessionDirectoryForHardlinks)
    }

    static func trashDraftDirectory(discussionURIRepresentation: TypeSafeURL<PersistedDiscussion>, draftURIRepresentation: TypeSafeURL<PersistedDraft>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrash = draftDirectory(discussionURIRepresentation: discussionURIRepresentation, draftURIRepresentation: draftURIRepresentation, in: currentSessionDirectoryForHardlinks)
        let trashURL = ObvMessengerConstants.containerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrash.path) else { return }
        try FileManager.default.moveItem(at: urlToTrash, to: trashURL)
    }

    static func trashDraftFyleJoinDirectory(discussionURIRepresentation: TypeSafeURL<PersistedDiscussion>, draftURIRepresentation: TypeSafeURL<PersistedDraft>, draftFyleJoinURIRepresentation: TypeSafeURL<PersistedDraftFyleJoin>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrash = draftDirectory(discussionURIRepresentation: discussionURIRepresentation, draftURIRepresentation: draftURIRepresentation, in: currentSessionDirectoryForHardlinks)
            .appendingPathComponent(draftFyleJoinURIRepresentation.path, isDirectory: true)
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

    let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
    let messageObjectID: TypeSafeManagedObjectID<PersistedMessage>
    let fyleMessageJoinWithStatusObjectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>

    init?(_ fyleMessageJoinWithStatus: FyleMessageJoinWithStatus) throws {
        guard let fyle = fyleMessageJoinWithStatus.fyle else { return nil }
        guard let message = fyleMessageJoinWithStatus.message else { return nil }
        self.fyleURL = fyle.url
        self.fileName = fyleMessageJoinWithStatus.fileName
        self.uti = fyleMessageJoinWithStatus.uti
        self.sha256 = fyle.sha256
        self.discussionObjectID = message.discussion.typedObjectID
        self.messageObjectID = message.typedObjectID
        self.fyleMessageJoinWithStatusObjectID = fyleMessageJoinWithStatus.typedObjectID
        self.fullFileIsAvailable = fyleMessageJoinWithStatus.fullFileIsAvailable
    }

    private init(fyleURL: URL, fileName: String, uti: String, sha256: Data, fullFileIsAvailable: Bool, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, fyleMessageJoinWithStatusObjectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) {
        self.fyleURL = fyleURL
        self.fileName = fileName
        self.uti = uti
        self.sha256 = sha256
        self.fullFileIsAvailable = fullFileIsAvailable
        self.discussionObjectID = discussionObjectID
        self.messageObjectID = messageObjectID
        self.fyleMessageJoinWithStatusObjectID = fyleMessageJoinWithStatusObjectID
    }


    func replacingFullFileIsAvailable(with newFullFileIsAvailable: Bool) -> FyleElement {
        FyleElementForFyleMessageJoinWithStatus(fyleURL: fyleURL,
                                                fileName: fileName,
                                                uti: uti,
                                                sha256: sha256,
                                                fullFileIsAvailable: newFullFileIsAvailable,
                                                discussionObjectID: discussionObjectID,
                                                messageObjectID: messageObjectID,
                                                fyleMessageJoinWithStatusObjectID: fyleMessageJoinWithStatusObjectID)
    }

    static func makeError(message: String) -> Error { NSError(domain: "FyleElementForFyleMessageJoinWithStatus", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    fileprivate static func discussionDirectory(discussionURIRepresentation: TypeSafeURL<PersistedDiscussion>, in currentSessionDirectoryForHardlinks: URL) -> URL {
        let directory = discussionURIRepresentation.path.replacingOccurrences(of: "/", with: "_")
        return currentSessionDirectoryForHardlinks
            .appendingPathComponent(directory, isDirectory: true)
    }


    private static func messageDirectory(discussionURIRepresentation: TypeSafeURL<PersistedDiscussion>, messageURIRepresentation: TypeSafeURL<PersistedMessage>, in currentSessionDirectoryForHardlinks: URL) -> URL {
        let directory = messageURIRepresentation.path.replacingOccurrences(of: "/", with: "_")
        return discussionDirectory(discussionURIRepresentation: discussionURIRepresentation, in: currentSessionDirectoryForHardlinks)
            .appendingPathComponent(directory, isDirectory: true)
    }


    private static func fyleMessageJoinWithStatusDirectory(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, fyleMessageJoinWithStatusObjectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>, in currentSessionDirectoryForHardlinks: URL) -> URL {
        return fyleMessageJoinWithStatusDirectory(discussionURIRepresentation: discussionObjectID.uriRepresentation(), messageURIRepresentation: messageObjectID.uriRepresentation(), fyleMessageJoinWithStatusURIRepresentation: fyleMessageJoinWithStatusObjectID.uriRepresentation(), in: currentSessionDirectoryForHardlinks)
    }
    
    
    private static func fyleMessageJoinWithStatusDirectory(discussionURIRepresentation: TypeSafeURL<PersistedDiscussion>, messageURIRepresentation: TypeSafeURL<PersistedMessage>, fyleMessageJoinWithStatusURIRepresentation: TypeSafeURL<FyleMessageJoinWithStatus>, in currentSessionDirectoryForHardlinks: URL) -> URL {
        let directory = fyleMessageJoinWithStatusURIRepresentation.path.replacingOccurrences(of: "/", with: "_")
        return messageDirectory(discussionURIRepresentation: discussionURIRepresentation, messageURIRepresentation: messageURIRepresentation, in: currentSessionDirectoryForHardlinks)
            .appendingPathComponent(directory, isDirectory: true)
    }
    

    func directoryForHardLink(in currentSessionDirectoryForHardlinks: URL) -> URL {
        FyleElementForFyleMessageJoinWithStatus.fyleMessageJoinWithStatusDirectory(
            discussionObjectID: discussionObjectID,
            messageObjectID: messageObjectID,
            fyleMessageJoinWithStatusObjectID: fyleMessageJoinWithStatusObjectID,
            in: currentSessionDirectoryForHardlinks)
    }

    static func trashDiscussionDirectory(discussionURIRepresentation: TypeSafeURL<PersistedDiscussion>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrash = discussionDirectory(discussionURIRepresentation: discussionURIRepresentation, in: currentSessionDirectoryForHardlinks)
        let trashURL = ObvMessengerConstants.containerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrash.path) else { return }
        try FileManager.default.moveItem(at: urlToTrash, to: trashURL)
    }

    static func trashDiscussionDirectoryIfEmpty(discussionURIRepresentation: TypeSafeURL<PersistedDiscussion>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrashIfEmpty = discussionDirectory(discussionURIRepresentation: discussionURIRepresentation, in: currentSessionDirectoryForHardlinks)
        guard FileManager.default.isDirectory(url: urlToTrashIfEmpty) else { return }
        let contents = try FileManager.default.contentsOfDirectory(at: urlToTrashIfEmpty, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        guard contents.isEmpty else { return }
        let trashURL = ObvMessengerConstants.containerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrashIfEmpty.path) else { return }
        try FileManager.default.moveItem(at: urlToTrashIfEmpty, to: trashURL)
    }

    static func trashMessageDirectory(discussionURIRepresentation: TypeSafeURL<PersistedDiscussion>, messageURIRepresentation: TypeSafeURL<PersistedMessage>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrash = messageDirectory(discussionURIRepresentation: discussionURIRepresentation, messageURIRepresentation: messageURIRepresentation, in: currentSessionDirectoryForHardlinks)
        let trashURL = ObvMessengerConstants.containerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrash.path) else { return }
        try FileManager.default.moveItem(at: urlToTrash, to: trashURL)
    }

    
    static func trashMessageDirectoryIfEmpty(discussionURIRepresentation: TypeSafeURL<PersistedDiscussion>, messageURIRepresentation: TypeSafeURL<PersistedMessage>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrashIfEmpty = messageDirectory(discussionURIRepresentation: discussionURIRepresentation, messageURIRepresentation: messageURIRepresentation, in: currentSessionDirectoryForHardlinks)
        guard FileManager.default.isDirectory(url: urlToTrashIfEmpty) else { return }
        try trashMessageDirectory(discussionURIRepresentation: discussionURIRepresentation, messageURIRepresentation: messageURIRepresentation, in: currentSessionDirectoryForHardlinks)
    }

    
    static func trashFyleMessageJoinWithStatusDirectory(discussionURIRepresentation: TypeSafeURL<PersistedDiscussion>, messageURIRepresentation: TypeSafeURL<PersistedMessage>, fyleMessageJoinWithStatusURIRepresentation: TypeSafeURL<FyleMessageJoinWithStatus>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrash = fyleMessageJoinWithStatusDirectory(discussionURIRepresentation: discussionURIRepresentation, messageURIRepresentation: messageURIRepresentation, fyleMessageJoinWithStatusURIRepresentation: fyleMessageJoinWithStatusURIRepresentation, in: currentSessionDirectoryForHardlinks)
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

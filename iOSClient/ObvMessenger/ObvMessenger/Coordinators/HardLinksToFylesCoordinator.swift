/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import os.log
import QuickLook
import MobileCoreServices
import CoreData



/// The purpose of this coordinator is to manage all the hard links to fyles within Olvid. It subscribes to `RequestHardLinkToFyle` notifications.
/// These notifications provide a completion handler that this coordinator calls on a background thread as soon as a hard link is avaible for the requested
/// fyle.
///
/// At launch, this coordinator also cleans any hard link created during past launch of the App.
final class HardLinksToFylesCoordinator {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: HardLinksToFylesCoordinator.self))
    
    /// This directory will contain all the hardlinks
    private let currentSessionDirectoryForHardlinks: URL
    
    /// Directories created in previous sessions. We delete all these directories in a background thread.
    private let previousDirectories: [URL]
    
    private let queueForDeletingPreviousDirectories = DispatchQueue(label: "Queue for deleting previous directories containing hard links")
    
    private let queueForNotifications: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    
    private var observationTokens = [NSObjectProtocol]()

    private var appType: ObvMessengerConstants.AppType
    
    init(appType: ObvMessengerConstants.AppType) {
        self.appType = appType
        let url = ObvMessengerConstants.containerURL.forFylesHardlinks(within: appType)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        self.previousDirectories = try! FileManager.default.contentsOfDirectory(atPath: url.path).map { url.appendingPathComponent($0) }
        self.currentSessionDirectoryForHardlinks = url.appendingPathComponent(UUID().description)
        try! FileManager.default.createDirectory(at: self.currentSessionDirectoryForHardlinks, withIntermediateDirectories: true, attributes: nil)
        deletePreviousDirectories()
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeRequestHardLinkToFyle(queue: queueForNotifications) { [weak self] (fyleElement, completionHandler) in
                self?.processRequestHardLinkToFyleNotification(fyleElement: fyleElement, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeRequestAllHardLinksToFyles(queue: queueForNotifications) { [weak self] (fyleElements, completionHandler) in
                self?.processRequestAllHardLinksToFylesNotification(fyleElements: fyleElements, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observePersistedMessagesWereDeleted(queue: queueForNotifications) { [weak self] (discussionUriRepresentation, messageUriRepresentations) in
                self?.processPersistedMessagesWereWipedOrDeleted(discussionUriRepresentation: discussionUriRepresentation, messageUriRepresentations: messageUriRepresentations)
            },
            ObvMessengerInternalNotification.observePersistedDiscussionWasDeleted(queue: queueForNotifications) { [weak self] discussionUriRepresentation in
                self?.processPersistedDiscussionWasDeletedNotification(discussionUriRepresentation: discussionUriRepresentation)
            },
            ObvMessengerInternalNotification.observePersistedMessagesWereWiped(queue: queueForNotifications) { [weak self] (discussionUriRepresentation, messageUriRepresentations) in
                self?.processPersistedMessagesWereWipedOrDeleted(discussionUriRepresentation: discussionUriRepresentation, messageUriRepresentations: messageUriRepresentations)
            },
            ObvMessengerInternalNotification.observeDraftToSendWasReset(queue: queueForNotifications) { [weak self] (discussionObjectID, draftObjectID) in
                self?.processDraftToSendWasResetNotification(discussionObjectID: discussionObjectID, draftObjectID: draftObjectID)
            },
            ObvMessengerInternalNotification.observeDraftFyleJoinWasDeleted(queue: queueForNotifications) { [weak self] (discussionUriRepresentation, draftUriRepresentation, draftFyleJoinUriRepresentation) in
                self?.processDraftFyleJoinWasDeletedNotification(discussionUriRepresentation: discussionUriRepresentation, draftUriRepresentation: draftUriRepresentation, draftFyleJoinUriRepresentation: draftFyleJoinUriRepresentation)
            },
            ObvMessengerInternalNotification.observeShareExtensionExtensionContextWillCompleteRequest(queue: queueForNotifications) { [weak self] in
                self?.processShareExtensionExtensionContextWillCompleteRequestNotification()
            },
        ])
    }
    
    
    deinit {
        self.deleteCurrentDirectory()
    }
    
    
    private static let errorDomain = "HardLinksToFylesCoordinator"
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    
    private func deleteCurrentDirectory() {
        do {
            try FileManager.default.removeItem(at: currentSessionDirectoryForHardlinks)
        } catch let error {
            os_log("Could not delete directory at %{public}@: %{public}@", log: log, type: .error, currentSessionDirectoryForHardlinks.path, error.localizedDescription)
        }
    }
    
    
    private func deletePreviousDirectories() {
        let log = self.log
        queueForDeletingPreviousDirectories.async { [weak self] in
            guard let _self = self else { return }
            for url in _self.previousDirectories {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch let error {
                    os_log("Could not delete directory at %{public}@: %{public}@", log: log, type: .error, url.path, error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: Processing notifications
    
    private func processRequestHardLinkToFyleNotification(fyleElement: FyleElement, completionHandler: (HardLinkToFyle) -> Void) {
        do {
            let hardlink = try HardLinkToFyle(fyleElement: fyleElement, currentSessionDirectoryForHardlinks: currentSessionDirectoryForHardlinks, log: log)
            completionHandler(hardlink)
        } catch {
            os_log("Failed to create HardLink", log: log, type: .fault)
            return
        }
    }
    
    
    private func processRequestAllHardLinksToFylesNotification(fyleElements: [FyleElement], completionHandler: ([HardLinkToFyle?]) -> Void) {
        let hardlinks = fyleElements.map {
            try? HardLinkToFyle(fyleElement: $0, currentSessionDirectoryForHardlinks: currentSessionDirectoryForHardlinks, log: log)
        }
        completionHandler(hardlinks)
    }
    
    
    private func processPersistedMessagesWereWipedOrDeleted(discussionUriRepresentation: TypeSafeURL<PersistedDiscussion>, messageUriRepresentations: Set<TypeSafeURL<PersistedMessage>>) {
        for messageUriRepresentation in messageUriRepresentations {
            do {
                try FyleElementForFyleMessageJoinWithStatus.trashMessageDirectory(
                    discussionURIRepresentation: discussionUriRepresentation,
                    messageURIRepresentation: messageUriRepresentation,
                    in: currentSessionDirectoryForHardlinks)
            } catch {
                os_log("Failed to delete hard links of message: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
        do {
            try FyleElementForFyleMessageJoinWithStatus.trashDiscussionDirectoryIfEmpty(
                discussionURIRepresentation: discussionUriRepresentation,
                in: currentSessionDirectoryForHardlinks)
        } catch {
            os_log("Failed to delete hard links of message: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
    
    
    private func processPersistedDiscussionWasDeletedNotification(discussionUriRepresentation: TypeSafeURL<PersistedDiscussion>) {
        do {
            try FyleElementForFyleMessageJoinWithStatus.trashDiscussionDirectory(
                discussionURIRepresentation: discussionUriRepresentation,
                in: currentSessionDirectoryForHardlinks)
        } catch {
            os_log("Failed to delete hard links of discussion: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }


    private func processDraftToSendWasResetNotification(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        let discussionUriRepresentation = discussionObjectID.uriRepresentation()
        let draftUriRepresentation = draftObjectID.uriRepresentation()
        do {
            try FyleElementForPersistedDraftFyleJoin.trashDraftDirectory(
                discussionURIRepresentation: discussionUriRepresentation,
                draftURIRepresentation: draftUriRepresentation,
                in: currentSessionDirectoryForHardlinks)
            try FyleElementForFyleMessageJoinWithStatus.trashDiscussionDirectoryIfEmpty(
                discussionURIRepresentation: discussionUriRepresentation,
                in: currentSessionDirectoryForHardlinks)
        } catch {
            os_log("Failed to delete hard links of draft: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }

    private func processDraftFyleJoinWasDeletedNotification(discussionUriRepresentation: TypeSafeURL<PersistedDiscussion>, draftUriRepresentation: TypeSafeURL<PersistedDraft>, draftFyleJoinUriRepresentation: TypeSafeURL<PersistedDraftFyleJoin>) {
        do {
            try FyleElementForPersistedDraftFyleJoin.trashDraftFyleJoinDirectory(
                discussionURIRepresentation: discussionUriRepresentation,
                draftURIRepresentation: draftUriRepresentation,
                draftFyleJoinURIRepresentation: draftFyleJoinUriRepresentation,
                in: currentSessionDirectoryForHardlinks)
            try FyleElementForFyleMessageJoinWithStatus.trashDiscussionDirectoryIfEmpty(
                discussionURIRepresentation: discussionUriRepresentation,
                in: currentSessionDirectoryForHardlinks)
        } catch {
            os_log("Failed to delete hard links of draft fyle join: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }

    
    private func processShareExtensionExtensionContextWillCompleteRequestNotification() {
        guard appType == .shareExtension else { return }
        self.deleteCurrentDirectory()
        try? FileManager.default.createDirectory(at: self.currentSessionDirectoryForHardlinks, withIntermediateDirectories: true, attributes: nil)
    }
    
}

// MARK: - HardLinkToFyle

final class HardLinkToFyle: NSObject, QLPreviewItem {

    let creationDate = Date()
    let uti: String
    let fyleURL: URL
    let fileName: String
    private(set) var hardlinkURL: URL?
    private(set) var activityItemProvider: ActivityItemProvider?

    override func isEqual(_ object: Any?) -> Bool {
        guard let otherObject = object as? HardLinkToFyle else { return false }
        return self.uti == otherObject.uti && self.fyleURL == otherObject.fyleURL && self.fileName == otherObject.fileName && self.hardlinkURL == otherObject.hardlinkURL
    }
    
    override var debugDescription: String {
        "HardLinkToFyle(creationDate: \(creationDate.debugDescription) uti: \(uti), fileName: \(fileName), fyleURL: \(fyleURL), hardlinkURL: \(hardlinkURL?.path ?? "nil")"
    }
    
    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(uti)
        hasher.combine(fyleURL)
        hasher.combine(fileName)
        hasher.combine(hardlinkURL)
        return hasher.finalize()
    }
    
    private static func makeError(message: String) -> Error { NSError(domain: "HardLinkToFyle", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { HardLinkToFyle.makeError(message: message) }


    final class ActivityItemProvider: UIActivityItemProvider {
        
        private let hardlinkURL: URL
        private let uti: String
        
        fileprivate init(hardlinkURL: URL, uti: String) {
            self.hardlinkURL = hardlinkURL
            self.uti = uti
            super.init(placeholderItem: hardlinkURL)
        }
        
        override var item: Any {
            return hardlinkURL
        }

        var excludedActivityTypes: [UIActivity.ActivityType]? {
            if ObvUTIUtils.uti(self.uti, conformsTo: kUTTypeImage) {
                return [.openInIBooks]
            } else {
                return []
            }
        }

    }
    
    fileprivate init(fyleElement: FyleElement, currentSessionDirectoryForHardlinks: URL, log: OSLog) throws {
        self.uti = fyleElement.uti
        self.fyleURL = fyleElement.fyleURL
        self.fileName = fyleElement.fileName
        guard fyleElement.fullFileIsAvailable else {
            self.hardlinkURL = nil
            self.activityItemProvider = nil
            super.init()
            return
        }
        let directoryForHardLink = fyleElement.directoryForHardLink(in: currentSessionDirectoryForHardlinks)
        try FileManager.default.createDirectory(at: directoryForHardLink, withIntermediateDirectories: true, attributes: nil)
        let appropriateFilename = HardLinkToFyle.determineAppropriateFilename(originalFilename: fyleElement.fileName, uti: fyleElement.uti)
        let hardlinkURL = directoryForHardLink.appendingPathComponent(appropriateFilename)
        try HardLinkToFyle.linkOrCopyItem(at: fyleElement.fyleURL, to: hardlinkURL, log: log)
        self.hardlinkURL = hardlinkURL
        self.activityItemProvider = ActivityItemProvider(hardlinkURL: hardlinkURL, uti: fyleElement.uti)
        super.init()
    }
    
    private static func determineAppropriateFilename(originalFilename: String, uti: String) -> String {
        let escapedFilename = originalFilename.replacingOccurrences(of: "/", with: "_")
        // We have a specific case of .m4a files to fix the issue where Android sends audio/mpeg as a MIME type of .m4a files
        if let utiFromFilename = ObvUTIUtils.utiOfFile(withName: escapedFilename), (utiFromFilename == uti || ObvUTIUtils.uti(utiFromFilename, conformsTo: kUTTypeMPEG4Audio)) {
            return escapedFilename
        } else {
            if let filenameExtension = ObvUTIUtils.preferredTagWithClass(inUTI: uti, inTagClass: .FilenameExtension) {
                return [escapedFilename, filenameExtension].joined(separator: ".")
            } else {
                return escapedFilename
            }
        }
    }
    
    private static func linkOrCopyItem(at fyleURL: URL, to hardlinkURL: URL, log: OSLog) throws {
        guard !FileManager.default.fileExists(atPath: hardlinkURL.path) else { return }
        do {
            try FileManager.default.linkItem(at: fyleURL, to: hardlinkURL)
        } catch {
            os_log("Could not create hardlink: %{public}@. We try to copy the file.", log: log, type: .error, error.localizedDescription)
            do {
                try FileManager.default.copyItem(at: fyleURL, to: hardlinkURL)
            } catch let error {
                os_log("Could not create hardlink: %{public}@", log: log, type: .fault, error.localizedDescription)
                throw error
            }
        }
    }

    // MARK: QLPreviewItem
    
    var previewItemURL: URL? {
        return self.hardlinkURL
    }
    
    var previewItemTitle: String? {
        if self.hardlinkURL == nil {
            return CommonString.Title.downloadingFile
        } else {
            return nil // Keep default title
        }
    }

}



// MARK: - FyleElement and implementing classes

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




struct FyleElementForDraftFyleJoin: FyleElement {
    
    let fileName: String
    let uti: String
    let fullFileIsAvailable: Bool
    let fyleURL: URL
    let sha256: Data

    init?(_ draftFyleJoin: DraftFyleJoin) {
        guard let fyle = draftFyleJoin.fyle else { return nil }
        self.fileName = draftFyleJoin.fileName
        self.uti = draftFyleJoin.uti
        self.fullFileIsAvailable = true
        self.fyleURL = fyle.url
        self.sha256 = fyle.sha256
    }
    
    private init(fileName: String, uti: String, fullFileIsAvailable: Bool, fyleURL: URL, sha256: Data) {
        self.fileName = fileName
        self.uti = uti
        self.fullFileIsAvailable = fullFileIsAvailable
        self.fyleURL = fyleURL
        self.sha256 = sha256
    }

    
    static func makeError(message: String) -> Error { NSError(domain: "FyleElementForDraftFyleJoin", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    func directoryForHardLink(in currentSessionDirectoryForHardlinks: URL) -> URL {
        currentSessionDirectoryForHardlinks
            .appendingPathComponent(sha256.hexString(), isDirectory: true)
    }
    
    func replacingFullFileIsAvailable(with newFullFileIsAvailable: Bool) -> FyleElement {
        FyleElementForDraftFyleJoin(fileName: fileName, uti: uti, fullFileIsAvailable: newFullFileIsAvailable, fyleURL: fyleURL, sha256: sha256)
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

    fileprivate static func trashDraftDirectory(discussionURIRepresentation: TypeSafeURL<PersistedDiscussion>, draftURIRepresentation: TypeSafeURL<PersistedDraft>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrash = draftDirectory(discussionURIRepresentation: discussionURIRepresentation, draftURIRepresentation: draftURIRepresentation, in: currentSessionDirectoryForHardlinks)
        let trashURL = ObvMessengerConstants.containerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrash.path) else { return }
        try FileManager.default.moveItem(at: urlToTrash, to: trashURL)
    }

    fileprivate static func trashDraftFyleJoinDirectory(discussionURIRepresentation: TypeSafeURL<PersistedDiscussion>, draftURIRepresentation: TypeSafeURL<PersistedDraft>, draftFyleJoinURIRepresentation: TypeSafeURL<PersistedDraftFyleJoin>, in currentSessionDirectoryForHardlinks: URL) throws {
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
        let directory = fyleMessageJoinWithStatusObjectID.uriRepresentation().path.replacingOccurrences(of: "/", with: "_")
        return messageDirectory(discussionURIRepresentation: discussionObjectID.uriRepresentation(), messageURIRepresentation: messageObjectID.uriRepresentation(), in: currentSessionDirectoryForHardlinks)
            .appendingPathComponent(directory, isDirectory: true)
    }
    
    func directoryForHardLink(in currentSessionDirectoryForHardlinks: URL) -> URL {
        FyleElementForFyleMessageJoinWithStatus.fyleMessageJoinWithStatusDirectory(
            discussionObjectID: discussionObjectID,
            messageObjectID: messageObjectID,
            fyleMessageJoinWithStatusObjectID: fyleMessageJoinWithStatusObjectID,
            in: currentSessionDirectoryForHardlinks)
    }
        
    fileprivate static func trashDiscussionDirectory(discussionURIRepresentation: TypeSafeURL<PersistedDiscussion>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrash = discussionDirectory(discussionURIRepresentation: discussionURIRepresentation, in: currentSessionDirectoryForHardlinks)
        let trashURL = ObvMessengerConstants.containerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrash.path) else { return }
        try FileManager.default.moveItem(at: urlToTrash, to: trashURL)
    }

    fileprivate static func trashDiscussionDirectoryIfEmpty(discussionURIRepresentation: TypeSafeURL<PersistedDiscussion>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrashIfEmpty = discussionDirectory(discussionURIRepresentation: discussionURIRepresentation, in: currentSessionDirectoryForHardlinks)
        guard FileManager.default.isDirectory(url: urlToTrashIfEmpty) else { return }
        let contents = try FileManager.default.contentsOfDirectory(at: urlToTrashIfEmpty, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        guard contents.isEmpty else { return }
        let trashURL = ObvMessengerConstants.containerURL.forTrash.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.fileExists(atPath: urlToTrashIfEmpty.path) else { return }
        try FileManager.default.moveItem(at: urlToTrashIfEmpty, to: trashURL)
    }

    fileprivate static func trashMessageDirectory(discussionURIRepresentation: TypeSafeURL<PersistedDiscussion>, messageURIRepresentation: TypeSafeURL<PersistedMessage>, in currentSessionDirectoryForHardlinks: URL) throws {
        let urlToTrash = messageDirectory(discussionURIRepresentation: discussionURIRepresentation, messageURIRepresentation: messageURIRepresentation, in: currentSessionDirectoryForHardlinks)
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

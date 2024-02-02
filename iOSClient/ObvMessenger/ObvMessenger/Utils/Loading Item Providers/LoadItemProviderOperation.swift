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
import MobileCoreServices
import UniformTypeIdentifiers
import os.log
import UIKit
import Contacts
import OlvidUtils
import ObvUI
import ObvUICoreData
import ObvSettings


/// This operation takes an `itemProvider` and loads it.
///
/// This operation performs the following actions:
/// - It first choose the most appropriate UTI to load. In the "worst" case, we choose the first UTI returned by `registeredTypeIdentifiers`
/// - Then it loads a file representation and copy this file to a temporary location `tempURL`
/// - It keeps track of the UTI and of the file name so as to return an appropriate `loadedFileRepresentation`.
final class LoadItemProviderOperation: OperationWithSpecificReasonForCancel<LoadItemProviderOperationReasonForCancel>, OperationProvidingLoadedItemProvider {
    
    private let preferredTypes: [UTType] = [.fileURL, .jpeg, .png, .mpeg4Movie, .mp3, .quickTimeMovie]
    private let ignoredTypes: Set<UTType?> = Set([.groupActivitiesActivity, .Bitmoji.avatarID, .Bitmoji.comicID, .Bitmoji.packID])

    private let itemProviderOrItemURL: ItemProviderOrItemURL
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "LoadItemProviderOperation")

    // Called iff a progress is available for tracking the loading progress
    private let progressAvailable: (Progress) -> Void
    
    convenience init(itemURL: URL, progressAvailable: @escaping (Progress) -> Void) {
        self.init(itemProviderOrItemURL: .itemURL(url: itemURL), progressAvailable: progressAvailable)
    }
    
    convenience init(itemProvider: NSItemProvider, progressAvailable: @escaping (Progress) -> Void) {
        self.init(itemProviderOrItemURL: .itemProvider(itemProvider: itemProvider), progressAvailable: progressAvailable)
    }
    
    init(itemProviderOrItemURL: ItemProviderOrItemURL, progressAvailable: @escaping (Progress) -> Void) {
        self.itemProviderOrItemURL = itemProviderOrItemURL
        self.progressAvailable = progressAvailable
        super.init()
    }
    
    private var _isFinished = false {
        willSet { willChangeValue(for: \.isFinished) }
        didSet { didChangeValue(for: \.isFinished) }
    }
    override var isFinished: Bool { _isFinished }

    override func cancel(withReason reason: LoadItemProviderOperationReasonForCancel) {
        assert(self.reasonForCancel == nil)
        self.reasonForCancel = reason
        self.cancel()
        _isFinished = true
    }

    private(set) var loadedItemProvider: LoadedItemProvider?

    override func main() {
        
        switch itemProviderOrItemURL {
        case .itemProvider(itemProvider: let itemProvider):
            process(itemProvider)
        case .itemURL(url: let url):
            process(url)
        }
    }
    
    // Available in certain cases, depending on the "load" method used
    private var operationProgress: Progress?
    
    private func process(_ itemURL: URL) {
        assert(!itemURL.path.contains("PluginKitPlugin")) // This is a particular case, but we know the loading won't work in that case
        let fileType: UTType = Self.determineFileType(at: itemURL)
        let filename = (itemURL as NSURL).lastPathComponent ?? "File"
        loadedItemProvider = .file(tempURL: itemURL, fileType: fileType, filename: filename)
        _isFinished = true
        return
    }
    
    
    private static func determineFileType(at url: URL) -> UTType {
        if (url as NSURL).pathExtension == UTType.olvidBackup.preferredFilenameExtension {
            return .olvidBackup
        } else if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type
        } else {
            return .data
        }
    }
    
    
    private func process(_ itemProvider: NSItemProvider) {

        // Find the most appropriate UTI to load
        
        let availableContentTypes = itemProvider.registeredTypeIdentifiers(fileOptions: NSItemProviderFileOptions(rawValue: 0))
            .compactMap({ UTType($0) })
        os_log("Available type identifiers of the attachment: %{public}@", log: Self.log, type: .info, availableContentTypes.debugDescription)
        guard !availableContentTypes.isEmpty else { assertionFailure(); return cancel(withReason: .itemHasNoRegisteredTypeIdentifier) }
        
        let filteredContentTypes = availableContentTypes.filter({ !ignoredTypes.contains($0) })
        guard !filteredContentTypes.isEmpty else {
            os_log("No acceptable content type was found, we do not load any item provider", log: Self.log, type: .info)
            _isFinished = true
            return
        }

        let availablePreferredContentTypes = preferredTypes.filter({ filteredContentTypes.contains($0) })
        let contentTypeToLoad: UTType
        if !availablePreferredContentTypes.isEmpty {
            // This is the easy case, where the file provider does provide a content type we "prefer"
            contentTypeToLoad = preferredTypes.first(where: { availablePreferredContentTypes.contains($0) })!
        } else {
            // There is no "preferred" UTI available. We simply take the first UTI available
            assert(filteredContentTypes.count == 1, "We should have a special rule and include one of the UTIs in the list of preferred UTIs")
            contentTypeToLoad = filteredContentTypes.first!
        }

        assert(itemProvider.hasItemConformingToTypeIdentifier(contentTypeToLoad.identifier))
        
        // We have found an appropriate UTI for the item provider
        // We can load it
        
        os_log("Content type to load is: %{public}@", log: Self.log, type: .info, contentTypeToLoad.debugDescription)

        var progress: Progress?
        
        if contentTypeToLoad.conforms(to: .vCard) {
        
            os_log("Type identifier to load conforms to kUTTypeVCard", log: Self.log, type: .info)

            progress = itemProvider.obvLoadDataRepresentation(for: .vCard, completionHandler: { [weak self] (data, error) in
                guard error == nil else {
                    if let progress = self?.operationProgress, progress.isCancelled {
                        // The user cancelled the file loading, there is nothing left to do
                        self?._isFinished = true
                        return
                    } else {
                        self?.cancel(withReason: .loadFileRepresentationFailed(error: error!))
                        return
                    }
                }
                guard let data = data, let cnContacts = try? CNContactVCardSerialization.contacts(with: data) else {
                    self?.cancel(withReason: .couldNotLoadVCard)
                    return
                }
                assert(cnContacts.count == 1)
                guard let contact = cnContacts.first else {
                    self?.cancel(withReason: .couldNotLoadVCard)
                    return
                }
                let contactName = [contact.givenName, contact.familyName].joined(separator: "-")
                let filename = [contactName, "vcf"].joined(separator: ".")
                let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(filename)
                do {
                    let contactData = try CNContactVCardSerialization.data(with: [contact])
                    try contactData.write(to: tempURL)
                } catch {
                    self?.cancel(withReason: .couldNotCopyItem(error: error))
                    return
                }
                self?.loadedItemProvider = .file(tempURL: tempURL, fileType: contentTypeToLoad, filename: filename)
                self?._isFinished = true
                return
            })
            
        } else if contentTypeToLoad.conforms(to: .text) {
            
            os_log("Type identifier to load conforms to kUTTypeText", log: Self.log, type: .info)

            itemProvider.loadItem(forTypeIdentifier: UTType.text.identifier) { [weak self] (item, error) in
                guard error == nil else {
                    self?.cancel(withReason: .loadFileRepresentationFailed(error: error!))
                    return
                }
                if let text = item as? String {
                    self?.loadedItemProvider = .text(content: text)
                    self?._isFinished = true
                    return
                } else if let url = item as? URL {
                    let filename = url.lastPathComponent
                    let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(UUID().uuidString)
                    do {
                        try FileManager.default.copyItem(at: url, to: tempURL)
                    } catch {
                        self?.cancel(withReason: .couldNotCopyItem(error: error))
                        return
                    }
                    self?.loadedItemProvider = .file(tempURL: tempURL, fileType: .text, filename: filename)
                    self?._isFinished = true
                    return
                } else {
                    self?.cancel(withReason: .couldNotLoadString)
                    return
                }
            }
                   
        } else if contentTypeToLoad.conforms(to: .fileURL) {
            
            os_log("Type identifier to load conforms to kUTTypeFileURL", log: Self.log, type: .info)

            itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] (item, error) in
                guard error == nil else {
                    self?.cancel(withReason: .loadFileRepresentationFailed(error: error!))
                    return
                }
                guard let pickerURL = item as? URL else {
                    self?.cancel(withReason: .pickerURLIsNil)
                    return
                }
                let filename = pickerURL.lastPathComponent
                let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.copyItem(at: pickerURL, to: tempURL)
                } catch {
                    self?.cancel(withReason: .couldNotCopyItem(error: error))
                    return
                }
                let fileType = (try? pickerURL.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? contentTypeToLoad
                self?.loadedItemProvider = .file(tempURL: tempURL, fileType: fileType, filename: filename)
                self?._isFinished = true
                return

            }
            
        } else if contentTypeToLoad.conforms(to: .url) {
            
            os_log("Type identifier to load conforms to kUTTypeURL", log: Self.log, type: .info)

            itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] (item, error) in
                guard error == nil else {
                    os_log("Load of type kUTTypeURL did fail: %{public}@", log: Self.log, type: .fault, error!.localizedDescription)
                    self?.cancel(withReason: .loadFileRepresentationFailed(error: error!))
                    return
                }
                os_log("Loaded type kUTTypeURL", log: Self.log, type: .info)
                guard let url = item as? URL else {
                    os_log("The item of type type kUTTypeURL could not be casted to an URL", log: Self.log, type: .fault)
                    self?.cancel(withReason: .couldNotLoadURL)
                    return
                }
                os_log("The item of type type kUTTypeURL was casted to the following URL: %{public}@", log: Self.log, type: .info, url.description)
                self?.loadedItemProvider = .url(content: url)
                self?._isFinished = true
                return
            }
            
        } else if contentTypeToLoad == .image {

            os_log("Type identifier to load is kUTTypeImage", log: Self.log, type: .info)

            // Note that we do not check whether the uti "conforms" to kUTTypeImage. This would be the case of jpeg and png images, which we want to load "as is"
            
            itemProvider.loadItem(forTypeIdentifier: UTType.image.identifier) { [weak self] (item, error) in
                guard error == nil else {
                    self?.cancel(withReason: .loadFileRepresentationFailed(error: error!))
                    return
                }
                guard let image = item as? UIImage else {
                    assertionFailure()
                    self?.cancel(withReason: .noneOfTheItemTypeIdentifiersCouldBeLoaded(contentTypes: availableContentTypes))
                    return
                }
                let filename: String
                let data: Data
                let contentTypeOfFile: UTType
                if let pngData = image.pngData() {
                    filename = "image.png"
                    data = pngData
                    contentTypeOfFile = .png
                } else if let jpegData = image.jpegData(compressionQuality: 1.0) {
                    filename = "image.jpeg"
                    data = jpegData
                    contentTypeOfFile = .jpeg
                } else {
                    self?.cancel(withReason: .noneOfTheItemTypeIdentifiersCouldBeLoaded(contentTypes: availableContentTypes))
                    return
                }
                let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(UUID().uuidString)

                // If we reach this point, we were able to load png or jpeg data
                do {
                    try data.write(to: tempURL)
                } catch {
                    self?.cancel(withReason: .couldNotCopyItem(error: error))
                    return
                }
                self?.loadedItemProvider = .file(tempURL: tempURL, fileType: contentTypeOfFile, filename: filename)
                self?._isFinished = true
                return

            }
            
        } else {
            
            os_log("Type identifier requires to load a file representation", log: Self.log, type: .info)
            progress = itemProvider.loadFileRepresentation(forTypeIdentifier: contentTypeToLoad.identifier) { [weak self] (url, error) in
                os_log("Within the completion handler of loadFileRepresentation", log: Self.log, type: .info)
                guard error == nil else {
                    os_log("The loadFileRepresentation completion returned an error: %{public}@", log: Self.log, type: .info, String(describing: error?.localizedDescription))
                    if let progress = self?.operationProgress, progress.isCancelled {
                        // The user cancelled the file loading, there is nothing left to do
                        self?._isFinished = true
                        return
                    } else {
                        self?.cancel(withReason: .loadFileRepresentationFailed(error: error!))
                        return
                    }
                }
                guard let pickerURL = url else {
                    self?.cancel(withReason: .pickerURLIsNil)
                    return
                }
                let filename = pickerURL.lastPathComponent
                let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.copyItem(at: pickerURL, to: tempURL)
                } catch {
                    self?.cancel(withReason: .couldNotCopyItem(error: error))
                    return
                }
                self?.loadedItemProvider = .file(tempURL: tempURL, fileType: contentTypeToLoad, filename: filename)
                self?._isFinished = true
                return
            }

        }
        
        // If a progress is available at this point, we call the appropriate callback.
        // This typically allows not give a progress to the CompositionViewFreezeManager
        if let progress = progress {
            operationProgress = progress
            progressAvailable(progress)
        }

    }
    
}


enum ItemProviderOrItemURL {
    case itemProvider(itemProvider: NSItemProvider)
    case itemURL(url: URL)
}


enum LoadedItemProvider {
    case file(tempURL: URL, fileType: UTType, filename: String)
    case text(content: String)
    case url(content: URL)
}


//fileprivate extension String {
//    func utiConformsTo(_ otherUTI: CFString) -> Bool {
//        UTTypeConformsTo(self as CFString, otherUTI)
//    }
//}


enum LoadItemProviderOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case noneOfTheItemTypeIdentifiersCouldBeLoaded(contentTypes: [UTType])
    case loadFileRepresentationFailed(error: Error)
    case pickerURLIsNil
    case itemHasNoRegisteredTypeIdentifier
    case couldNotCopyItem(error: Error)
    case couldNotLoadString
    case couldNotLoadURL
    case couldNotLoadVCard

    var logType: OSLogType {
        return .fault
    }
    
    var errorDescription: String? {
        switch self {
        case .noneOfTheItemTypeIdentifiersCouldBeLoaded(contentTypes: let contentTypes):
            return "None of the item type identifiers could be loaded: \(contentTypes.debugDescription)"
        case .loadFileRepresentationFailed(error: let error):
            return "Failed to load representation: \(error.localizedDescription)"
        case .pickerURLIsNil:
            return "Picker URL is nil, which is unexpected"
        case .couldNotCopyItem(error: let error):
            return "Could not copy item: \(error.localizedDescription)"
        case .itemHasNoRegisteredTypeIdentifier:
            return "The item provides no registered type identifier"
        case .couldNotLoadString:
            return "Could not load String"
        case .couldNotLoadURL:
            return "Could not load URL"
        case .couldNotLoadVCard:
            return "Could not load VCard"
        }
    }
}


fileprivate struct UTI {
    
    struct Bitmoji {
        static let avatarID = "com.bitmoji.metadata.avatarID"
        static let packID = "com.bitmoji.metadata.packID"
        static let comicID = "com.bitmoji.metadata.comicID"
    }
    
    struct Apple {
        static let groupActivitiesActivity = "com.apple.group-activities.activity"
    }
    
}


fileprivate extension UTType {
    
    static var groupActivitiesActivity: UTType? {
        .init("com.apple.group-activities.activity")
    }
    
    struct Bitmoji {
        static var avatarID: UTType? {
            .init("com.bitmoji.metadata.avatarID")
        }
        static var packID: UTType? {
            .init("com.bitmoji.metadata.packID")
        }
        static var comicID: UTType? {
            .init("com.bitmoji.metadata.comicID")
        }
    }
    
}


fileprivate extension NSItemProvider {
    
    /// Trivial wrapper around the ``NSItemProvider.loadDataRepresentation(for:completionHandler:)`` method since it is only available under iOS 16
    func obvLoadDataRepresentation(for contentType: UTType, completionHandler: @escaping @Sendable (Data?, (Error)?) -> Void) -> Progress {
        if #available(iOS 16, *) {
            return loadDataRepresentation(for: contentType, completionHandler: completionHandler)
        } else {
            return loadDataRepresentation(forTypeIdentifier: contentType.identifier, completionHandler: completionHandler)
        }
    }

}

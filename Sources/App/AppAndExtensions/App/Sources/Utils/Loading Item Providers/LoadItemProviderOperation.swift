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
import MobileCoreServices
import UniformTypeIdentifiers
import os.log
import UIKit
import Contacts
import OlvidUtils
import ObvUI
import ObvUICoreData
import ObvSettings
import ObvAppCoreConstants


/// This operation takes an `itemProvider` and loads it.
///
/// This operation performs the following actions:
/// - It first choose the most appropriate UTI to load. In the "worst" case, we choose the first UTI returned by `registeredTypeIdentifiers`
/// - Then it loads a file representation and copy this file to a temporary location `tempURL`
/// - It keeps track of the UTI and of the file name so as to return an appropriate `loadedFileRepresentation`.
final class LoadItemProviderOperation: OperationWithSpecificReasonForCancel<LoadItemProviderOperationReasonForCancel>, @unchecked Sendable, OperationProvidingLoadedItemProvider {
    
    private let preferredTypes: [UTType] = [.fileURL, .jpeg, .png, .mpeg4Movie, .mp3, .quickTimeMovie, .gif, .webInternetLocation, .webP, .url]
    private let ignoredTypes: Set<UTType?> = Set([.groupActivitiesActivity, .Bitmoji.avatarID, .Bitmoji.comicID, .Bitmoji.packID])

    private let itemProviderOrItemURL: ItemProviderOrItemURL
    
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "LoadItemProviderOperation")

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
            return _isFinished = true
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
        
        if contentTypeToLoad == .webInternetLocation {
            
            os_log("Type identifier to load conforms to UTType.webInternetLocation", log: Self.log, type: .info)

            if itemProvider.canLoadObject(ofClass: URL.self) {
                _ = itemProvider.loadObject(ofClass: URL.self) { [weak self] url, error in
                    guard let self else { assertionFailure(); return }
                    guard error == nil else {
                        return cancel(withReason: .loadFileRepresentationFailed(error: error!))
                    }
                    guard let url else {
                        return cancel(withReason: .couldNotLoadURL)
                    }
                    loadedItemProvider = .url(content: url)
                    return _isFinished = true
                }
            } else {
                _ = itemProvider.loadObject(ofClass: String.self) { [weak self] text, error in
                    guard let self else { assertionFailure(); return }
                    guard error == nil else {
                        return cancel(withReason: .loadFileRepresentationFailed(error: error!))
                    }
                    guard let text else {
                        return cancel(withReason: .couldNotLoadURL)
                    }
                    loadedItemProvider = .text(content: text)
                    return _isFinished = true
                }
            }

        } else if contentTypeToLoad.conforms(to: .vCard) {
            
            os_log("Type identifier to load conforms to UTType.vCard", log: Self.log, type: .info)
            
            progress = itemProvider.obvLoadDataRepresentation(for: .vCard, completionHandler: { [weak self] (data, error) in
                guard let self else { assertionFailure(); return }
                guard error == nil else {
                    if let progress = operationProgress, progress.isCancelled {
                        // The user cancelled the file loading, there is nothing left to do
                        _isFinished = true
                        return
                    } else {
                        return cancel(withReason: .loadFileRepresentationFailed(error: error!))
                    }
                }
                guard let data = data, let cnContacts = try? CNContactVCardSerialization.contacts(with: data) else {
                    return cancel(withReason: .couldNotLoadVCard)
                }
                assert(cnContacts.count == 1)
                guard let contact = cnContacts.first else {
                    return cancel(withReason: .couldNotLoadVCard)
                }
                let contactName = [contact.givenName, contact.familyName].joined(separator: "-")
                let filename = [contactName, "vcf"].joined(separator: ".")
                let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(filename)
                do {
                    let contactData = try CNContactVCardSerialization.data(with: [contact])
                    try contactData.write(to: tempURL)
                } catch {
                    return cancel(withReason: .couldNotCopyItem(error: error))
                }
                loadedItemProvider = .file(tempURL: tempURL, fileType: contentTypeToLoad, filename: filename)
                return _isFinished = true
            })
            
        } else if contentTypeToLoad.conforms(to: .text) {
            
            os_log("Type identifier to load conforms to UTType.text", log: Self.log, type: .info)

            itemProvider.obvLoadItem(forType: .text) { [weak self] (item, error) in
                guard let self else { assertionFailure(); return }
                guard error == nil else {
                    return cancel(withReason: .loadFileRepresentationFailed(error: error!))
                }
                if let text = item as? String {
                    loadedItemProvider = .text(content: text)
                    return _isFinished = true
                } else if let url = item as? URL {
                    let filename = url.lastPathComponent
                    let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(UUID().uuidString)
                    do {
                        try FileManager.default.copyItem(at: url, to: tempURL)
                    } catch {
                        return cancel(withReason: .couldNotCopyItem(error: error))
                    }
                    loadedItemProvider = .file(tempURL: tempURL, fileType: .text, filename: filename)
                    return _isFinished = true
                } else {
                    return cancel(withReason: .couldNotLoadString)
                }
            }
                   
        } else if contentTypeToLoad.conforms(to: .fileURL) {
            
            os_log("Type identifier to load conforms to UTType.fileURL", log: Self.log, type: .info)

            itemProvider.obvLoadItem(forType: .fileURL) { [weak self] (item, error) in
                guard let self else { assertionFailure(); return }
                guard error == nil else {
                    return cancel(withReason: .loadFileRepresentationFailed(error: error!))
                }
                guard let pickerURL = item as? URL else {
                    return cancel(withReason: .pickerURLIsNil)
                }
                let filename = pickerURL.lastPathComponent
                let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.copyItem(at: pickerURL, to: tempURL)
                } catch {
                    return cancel(withReason: .couldNotCopyItem(error: error))
                }
                let fileType = (try? pickerURL.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? contentTypeToLoad
                loadedItemProvider = .file(tempURL: tempURL, fileType: fileType, filename: filename)
                return _isFinished = true
            }
            
        } else if contentTypeToLoad.conforms(to: .url) {
            
            os_log("Type identifier to load conforms to UTType.url", log: Self.log, type: .info)

            itemProvider.obvLoadItem(forType: .url) { [weak self] (item, error) in
                guard let self else { assertionFailure(); return }
                guard error == nil else {
                    os_log("Load of type UTType.url did fail: %{public}@", log: Self.log, type: .fault, error!.localizedDescription)
                    return cancel(withReason: .loadFileRepresentationFailed(error: error!))
                }
                os_log("Loaded type UTType.url", log: Self.log, type: .info)
                guard let url = item as? URL else {
                    os_log("The item of type type UTType.url could not be casted to an URL. Trying with an NSURL", log: Self.log, type: .error)
                    itemProvider.loadObject(ofClass: NSURL.self) { [weak self] object, error in
                        guard let self else { assertionFailure(); return }
                        guard error == nil else {
                            os_log("Load of type UTType.url as an NSURL did fail: %{public}@", log: Self.log, type: .fault, error!.localizedDescription)
                            return cancel(withReason: .loadFileRepresentationFailed(error: error!))
                        }
                        guard let url = object as? URL else {
                            return cancel(withReason: .couldNotLoadURL)
                        }
                        loadedItemProvider = .url(content: url)
                        return _isFinished = true
                    }
                    return
                }
                os_log("The item of type type UTType.url was casted to the following URL: %{public}@", log: Self.log, type: .info, url.description)
                loadedItemProvider = .url(content: url)
                return _isFinished = true
            }
            
        } else if contentTypeToLoad == .image {

            os_log("Type identifier to load is UTType.image", log: Self.log, type: .info)

            // Note that we do not check whether the uti "conforms" to UTType.image. This would be the case of jpeg and png images, which we want to load "as is" (i.e., using the loadFileRepresentation API)
            
            itemProvider.obvLoadItem(forType: .image) { [weak self] (item, error) in
                guard let self else { assertionFailure(); return }
                guard error == nil else {
                    return cancel(withReason: .loadFileRepresentationFailed(error: error!))
                }
                guard let image = item as? UIImage else {
                    assertionFailure()
                    return cancel(withReason: .noneOfTheItemTypeIdentifiersCouldBeLoaded(contentTypes: availableContentTypes))
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
                    return cancel(withReason: .noneOfTheItemTypeIdentifiersCouldBeLoaded(contentTypes: availableContentTypes))
                }
                let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(UUID().uuidString)

                // If we reach this point, we were able to load png or jpeg data
                do {
                    try data.write(to: tempURL)
                } catch {
                    return cancel(withReason: .couldNotCopyItem(error: error))
                }
                loadedItemProvider = .file(tempURL: tempURL, fileType: contentTypeOfFile, filename: filename)
                return _isFinished = true
            }
            
        } else if contentTypeToLoad == .olvidLinkPreview {
            
            os_log("Type identifier to load is UTType.olvidLinkPreview", log: Self.log, type: .info)

            itemProvider.obvLoadItem(forType: .olvidLinkPreview) { [weak self] (item, error) in
                guard let self else { assertionFailure(); return }
                guard error == nil else {
                    return cancel(withReason: .loadFileRepresentationFailed(error: error!))
                }
                guard let metadata = item as? ObvLinkMetadata else {
                    assertionFailure()
                    return cancel(withReason: .noneOfTheItemTypeIdentifiersCouldBeLoaded(contentTypes: availableContentTypes))
                }
                let filename: String = metadata.url?.absoluteString ?? UUID().uuidString
                let contentTypeOfFile: UTType = .olvidLinkPreview
                let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(UUID().uuidString)
                // If we reach this point, we were able to load png or jpeg data
                do {
                    let data: Data = try metadata.obvEncode().rawData
                    try data.write(to: tempURL)
                } catch {
                    return cancel(withReason: .couldNotCopyItem(error: error))
                }
                loadedItemProvider = .file(tempURL: tempURL, fileType: contentTypeOfFile, filename: filename)
                return _isFinished = true
            }
            
        } else {
            
            os_log("Type identifier requires to load a file representation", log: Self.log, type: .info)
            progress = itemProvider.loadFileRepresentation(forTypeIdentifier: contentTypeToLoad.identifier) { [weak self] (url, error) in
                guard let self else { assertionFailure(); return }
                os_log("Within the completion handler of loadFileRepresentation", log: Self.log, type: .info)
                guard error == nil else {
                    os_log("The loadFileRepresentation completion returned an error: %{public}@", log: Self.log, type: .info, String(describing: error?.localizedDescription))
                    if let progress = operationProgress, progress.isCancelled {
                        // The user cancelled the file loading, there is nothing left to do
                        return _isFinished = true
                    } else {
                        return cancel(withReason: .loadFileRepresentationFailed(error: error!))
                    }
                }
                guard let pickerURL = url else {
                    return cancel(withReason: .pickerURLIsNil)
                }
                let filename = pickerURL.lastPathComponent
                let tempURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent(UUID().uuidString)
                do {
                    try FileManager.default.copyItem(at: pickerURL, to: tempURL)
                } catch {
                    return cancel(withReason: .couldNotCopyItem(error: error))
                }
                loadedItemProvider = .file(tempURL: tempURL, fileType: contentTypeToLoad, filename: filename)
                return _isFinished = true
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


    /// Simple wrapper around ``loadItem(forTypeIdentifier:options:completionHandler:)`` making it possible to use a `UTType` instead of a type identifier.
    func obvLoadItem(forType type: UTType, options: [AnyHashable : Any]? = nil, completionHandler: NSItemProvider.CompletionHandler? = nil) {
        self.loadItem(forTypeIdentifier: type.identifier, options: options, completionHandler: completionHandler)
    }
     
}

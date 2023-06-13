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

import UIKit
import UniformTypeIdentifiers
import Platform_Sequence_KeyPathSorting
import Platform_NSItemProvider_UTType_Backport

/// Protocol exposing delegation methods for ``AttachmentsDropView``
@available(iOSApplicationExtension 14, *)
@MainActor
public protocol AttachmentsDropViewDelegate: AnyObject {
    /// Delegate method that gets called prior the start of a drop session
    /// - Parameter view: The view requesting the start of a drop session
    /// - Returns: If the drop session should begin
    func attachmentsDropViewShouldBegingDropSession(_ view: AttachmentsDropView) -> Bool

    /// Delegate method called when the user has dropped items to be appended as attachments to the current discussion
    /// - Parameters:
    ///   - view: An instance of ``AttachmentsDropView`` responsible for this call
    ///   - items: An array of items `NSItemProvider`s to append as attachments
    func attachmentsDropView(_ view: AttachmentsDropView, didDrop items: [NSItemProvider])
}

@available(iOSApplicationExtension 14, *)
public final class AttachmentsDropView: UIView {
    private enum Constants {
        // If an item provider has a registered type identifier that conforms to one of the types bellow,
        // we load it as a file (i.e., not as text) and restrict to the conforming type identifier when creating the DroppedItemProvider.
        static let typeIdentifiersToLoadAsFile: [UTType] = [.movie, .image, .pdf]
    }

    /// The drop view's delegate
    public weak var delegate: AttachmentsDropViewDelegate?

    /// An array of allowed `UTType`s for the attachments
    private let allowedTypes: [UTType]

    private let directoryForTemporaryFiles: URL

    private weak var targetDropView: _AttachmentsTargetDropZoneView!

    /// Creates a view that accepts content to be attached to a message :), via a drop operation
    /// - Parameters:
    ///   - allowedTypes: The types that are allowed to be dropped
    ///   - directoryForTemporaryFiles: The root directory where to store some stuff
    public init(allowedTypes: [UTType], directoryForTemporaryFiles: URL) {
        self.allowedTypes = allowedTypes
        self.directoryForTemporaryFiles = directoryForTemporaryFiles

        super.init(frame: .zero)

        _setupViews()
    }

    @available(*, unavailable)
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    #if DEBUG
    deinit {
        if FileManager.default.fileExists(atPath: directoryForTemporaryFiles.path) {
            do {
                let directoryChildrenURLs = try FileManager.default.contentsOfDirectory(at: directoryForTemporaryFiles,
                                                                                        includingPropertiesForKeys: [],
                                                                                        options: .skipsSubdirectoryDescendants)

                precondition(directoryChildrenURLs.isEmpty, "expected to no-longer have any temp items…, have: \(directoryChildrenURLs)")
            } catch {
                fatalError("failed to fetch contents with error: \(error)")
            }
        }
    }
    #endif

    private func _setupViews() {
        backgroundColor = .clear

        isOpaque = false

        isUserInteractionEnabled = false

        translatesAutoresizingMaskIntoConstraints = false

        layoutMargins = .zero

        let targetDropView = _AttachmentsTargetDropZoneView()

        targetDropView.isHidden = true

        targetDropView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(targetDropView)

        self.targetDropView = targetDropView

        _setupConstraints()
    }

    private func _setupConstraints() {
        let viewsDictionary = ["targetDropView": targetDropView!]

        NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "H:|-[targetDropView]-|",
                                                                   options: [],
                                                                   metrics: nil,
                                                                   views: viewsDictionary))

        NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "V:|-[targetDropView]-|",
                                                                   options: [],
                                                                   metrics: nil,
                                                                   views: viewsDictionary))
    }

    /// Updates the subviews for a given drop location
    /// - Parameter dropLocation: The current location of the drop, within `self`'s coordinate space
    private func _updateSubviews(for dropLocation: CGPoint, isFinished: Bool) {
        if isFinished {
            targetDropView.stopMarchingAntsAnimation()

            targetDropView.isHidden = true
        } else {
            targetDropView.isHidden = !bounds.contains(dropLocation)

            targetDropView.startMarchingAntsAnimation()
        }
    }
}

@available(iOSApplicationExtension 14, *)
extension AttachmentsDropView: UIDropInteractionDelegate {
    
    public func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        guard let delegate else {
            assertionFailure("we're missing our delegate")

            return false
        }

        guard delegate.attachmentsDropViewShouldBegingDropSession(self) else {
            return false
        }

        let conforms = session.hasItemsConforming(toTypeIdentifiers: allowedTypes.map(\.identifier))

        return conforms
    }

    
    public func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        let dropLocation = session.location(in: self)

        _updateSubviews(for: dropLocation, isFinished: false)

        let dropOperation: UIDropOperation

        if bounds.contains(dropLocation) {
            dropOperation = .copy
        } else {
            dropOperation = .cancel
        }

        return .init(operation: dropOperation)
    }

    
    public func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        
        guard let delegate else {
            assertionFailure("we're missing our delegate")
            return
        }

        // We create a dispatch group to synchronize all the file representations loading
        
        let group = DispatchGroup()
        
        // We will fill the following dictionary with the loaded file representations. The keys are the dropped files' indexes.
        
        var droppedItemProviderFromIndex: [Int: NSItemProvider] = [:]

        // Enumerate the session items, load each one, and populate the droppedItemProviderFromIndex dictionnary
        
        for (itemIndex, sessionItem) in session.items.map(\.itemProvider).enumerated() {
            
            group.enter()

            // Special cases for session items conforming to our predefined types within `Constants.typeIdentifiersToLoadAsFile`
            let preferredTypeIdentifierToLoadAsFile: UTType? = Constants.typeIdentifiersToLoadAsFile.reduce(nil) { partialResult, uti -> UTType? in
                if let partialResult {
                    return partialResult
                } else {
                    let contentTypes: [UTType]

                    if #available(iOSApplicationExtension 16, *) {
                        contentTypes = sessionItem.registeredContentTypes
                    } else {
                        contentTypes = sessionItem
                            .registeredTypeIdentifiers
                            .compactMap(UTType.init) /// there should be **no** cases where `UTType`'s initializer would fail, since at the end of the day the type exists within `MobileCoreServices`

                        assert(contentTypes.count == sessionItem.registeredTypeIdentifiers.count, "we're missing a casted UTType…")
                    }

                    return contentTypes
                        .first {
                            return $0.conforms(to: uti)
                        }
                }
            }

            if sessionItem.hasItemConformingToTypeIdentifier(UTType.url),
               preferredTypeIdentifierToLoadAsFile == nil {
                
                _ = sessionItem.loadObject(ofClass: URL.self) { value, error in

                    if let error {
                        assertionFailure("failed to load textual representation of URL with error: \(error)")
                        group.leave()
                        return
                    }

                    guard let value else {
                        assertionFailure("failed to retrieve URL value for item…")
                        group.leave()
                        return
                    }

                    let droppedItem = NSItemProvider(object: value.absoluteString as NSString)

                    DispatchQueue.main.async {
                        droppedItemProviderFromIndex[itemIndex] = droppedItem
                        group.leave()
                    }
                    
                }
                
            } else if sessionItem.hasItemConformingToTypeIdentifier(UTType.text),
                      preferredTypeIdentifierToLoadAsFile == nil {
                
                _ = sessionItem.loadObject(ofClass: String.self) { value, error in

                    if let error {
                        assertionFailure("failed to load textual representation of String with error: \(error)")
                        group.leave()
                        return
                    }

                    guard let value else {
                        assertionFailure("failed to retrieve String value for item…")
                        group.leave()
                        return
                    }

                    let droppedItem = NSItemProvider(object: value as NSString)

                    DispatchQueue.main.async {
                        droppedItemProviderFromIndex[itemIndex] = droppedItem
                        group.leave()
                    }
                }
                
            } else {
                
                sessionItem.loadFileRepresentation(forTypeIdentifier: UTType.data.identifier) { url, error in

                    if let error {
                        assertionFailure("failed to load file representation with error: \(error)")
                        group.leave()
                        return
                    }

                    guard let url else {
                        assertionFailure("failed to retrieve URL for file…")
                        group.leave()
                        return
                    }

                    let droppedItem: DroppedItemProvider

                    let typesToRegister: [UTType]

                    if let preferredTypeIdentifierToLoadAsFile {
                        typesToRegister = [preferredTypeIdentifierToLoadAsFile]
                    } else {
                        typesToRegister = sessionItem
                            .registeredTypeIdentifiers
                            .compactMap(UTType.init) /// there should be **no** cases where `UTType`'s initializer would fail, since at the end of the day the type exists within `MobileCoreServices`

                        assert(typesToRegister.count == sessionItem.registeredTypeIdentifiers.count, "we're missing a casted UTType…")
                    }

                    do {
                        droppedItem = try DroppedItemProvider(
                            url: url,
                            directoryForTemporaryFiles: self.directoryForTemporaryFiles,
                            typeIdentifiersToRegister: typesToRegister
                        )
                    } catch {
                        assertionFailure("failed to copy item, with error: \(error)")
                        group.leave()
                        return
                    }

                    DispatchQueue.main.async {
                        droppedItemProviderFromIndex[itemIndex] = droppedItem
                        group.leave()
                    }

                }
            }
        }

        // We wait until all the file representations are loaded
        group.notify(qos: .userInitiated, queue: DispatchQueue.main) {

            guard !droppedItemProviderFromIndex.isEmpty else {
                assertionFailure("expected to have items to handle…")
                return
            }

            let sortedItems = droppedItemProviderFromIndex
                .sorted(by: \.key)
                .map(\.value)

            delegate.attachmentsDropView(self, didDrop: sortedItems)
            
        }
    }

    
    public func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
        let dropLocation = session.location(in: self)

        _updateSubviews(for: dropLocation, isFinished: true)
    }

    
    public func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
        let dropLocation = session.location(in: self)

        _updateSubviews(for: dropLocation, isFinished: true)
    }
    
}

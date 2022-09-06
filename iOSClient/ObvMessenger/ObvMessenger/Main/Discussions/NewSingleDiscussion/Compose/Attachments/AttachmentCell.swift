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

import UIKit
import QuickLookThumbnailing
import CoreData
import os.log


@available(iOS 14.0, *)
final class AttachmentCell: UICollectionViewCell {
    
    private var fyleJoin: FyleJoin?
 
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.automaticallyUpdatesContentConfiguration = false
    }
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "AttachmentCell")

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateWith(fyleJoin: FyleJoin, indexPath: IndexPath, delegate: ViewShowingHardLinksDelegate?, cacheDelegate: DiscussionCacheDelegate?) {
        assert(delegate != nil)
        assert(cacheDelegate != nil)
        self.delegate = delegate
        self.cacheDelegate = cacheDelegate
        self.fyleJoin = fyleJoin
        self.setNeedsUpdateConfiguration()
    }
    
    weak var delegate: ViewShowingHardLinksDelegate?
    weak var cacheDelegate: DiscussionCacheDelegate?

    /// Maps a draft fyle join onto a hard link URL, making it possible for the cell to compute a thumnail
    private static var hardlinkForDraftFyleObjectID = [TypeSafeManagedObjectID<PersistedDraftFyleJoin>: HardLinkToFyle]()

    override func updateConfiguration(using state: UICellConfigurationState) {
        // If those assert fail, it probably mean that a previous the AttachmentsCollectionViewController was not deallocated (i.e., there is a memory cycle)
        assert(delegate != nil)
        assert(cacheDelegate != nil)
        guard let draftFyleJoin = self.fyleJoin as? PersistedDraftFyleJoin else { assertionFailure(); return }
        var content = AttachmentCellCustomContentConfiguration().updated(for: state)
        // If the draftFyleJoin has no fyle, we can't compute a thumbnail.
        // If there is a fyle, either we already have hardlink to the fyle, in which case we can use it as a fileURL, or we don't have one. In that case, we request one and, when we receive it, we store is and ask the cell to update its configuration.
        let draftFyleJoinObjectID = draftFyleJoin.typedObjectID
        if let hardlink = AttachmentCell.hardlinkForDraftFyleObjectID[draftFyleJoinObjectID], let hardlinkURL = hardlink.hardlinkURL, FileManager.default.fileExists(atPath: hardlinkURL.path) {
            let size = CGSize(width: AttachmentsCollectionViewController.cellSize, height: AttachmentsCollectionViewController.cellSize)
            content.hardlink = hardlink
            if let thumbnail = cacheDelegate?.getCachedImageForHardlink(hardlink: hardlink, size: size) {
                content.thumbnail = thumbnail
            } else {
                content.thumbnail = nil
                Task {
                    do {
                        try await cacheDelegate?.requestImageForHardlink(hardlink: hardlink, size: size)
                        setNeedsUpdateConfiguration()
                    } catch {
                        os_log("The request image for hardlink to fyle %{public}@ failed: %{public}@", log: Self.log, type: .error, hardlink.fyleURL.lastPathComponent, error.localizedDescription)
                    }
                }
            }
        } else {
            content.hardlink = nil
            AttachmentCell.hardlinkForDraftFyleObjectID.removeValue(forKey: draftFyleJoinObjectID)
            if let fyleElement = draftFyleJoin.fyleElement ?? draftFyleJoin.genericFyleElement {
                ObvMessengerInternalNotification.requestHardLinkToFyle(fyleElement: fyleElement) { result in
                    DispatchQueue.main.async { [weak self] in
                        switch result {
                        case .success(let hardlink):
                            AttachmentCell.hardlinkForDraftFyleObjectID[draftFyleJoinObjectID] = hardlink
                            self?.setNeedsUpdateConfiguration()
                        case .failure(let error):
                            assertionFailure(error.localizedDescription)
                        }
                    }
                }.postOnDispatchQueue()
            }
        }
        self.contentConfiguration = content
    }
    
    
    func getAllShownHardLink() -> [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)] {
        guard let contentView = self.contentView as? AttachmentCellContentView else { assertionFailure(); return [] }
        return contentView.getAllShownHardLink()
    }
}


@available(iOS 14.0, *)
fileprivate struct AttachmentCellCustomContentConfiguration: UIContentConfiguration, Hashable {
    
    var hardlink: HardLinkToFyle?
    var thumbnail: UIImage?

    func makeContentView() -> UIView & UIContentView {
        return AttachmentCellContentView(configuration: self)
    }

    func updated(for state: UIConfigurationState) -> Self {
        return self
    }

}


@available(iOS 14.0, *)
fileprivate final class AttachmentCellContentView: UIView, UIContentView, ViewShowingHardLinks {
    
    fileprivate let imageView = UIImageViewForHardLink()
    private var appliedConfiguration: AttachmentCellCustomContentConfiguration!
    fileprivate var currentHardlink: HardLinkToFyle?

    var delegate: ViewShowingHardLinksDelegate? {
        assert(superview is AttachmentCell)
        return (superview as? AttachmentCell)?.delegate
    }

    init(configuration: AttachmentCellCustomContentConfiguration) {
        super.init(frame: .zero)
        setupInternalViews()
        self.configuration = configuration
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    var configuration: UIContentConfiguration {
        get { appliedConfiguration }
        set {
            guard let newConfig = newValue as? AttachmentCellCustomContentConfiguration else { return }
            let currentConfig = appliedConfiguration
            apply(currentConfig: currentConfig, newConfig: newConfig)
            appliedConfiguration = newConfig
        }
    }

    
    /// Implementing `UIViewWithThumbnailsForUTI`
    var imageForUTI = [String: UIImage]()

    
    private func setupInternalViews() {

        clipsToBounds = true
        backgroundColor = .quaternarySystemFill
        
        addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        
        let constraints = [
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
        ]
        NSLayoutConstraint.activate(constraints)
    }
 
    private func apply(currentConfig: AttachmentCellCustomContentConfiguration?, newConfig: AttachmentCellCustomContentConfiguration) {
        currentHardlink = newConfig.hardlink
        guard let localHardlink = newConfig.hardlink else {
            imageView.reset()
            return
        }
        imageView.setHardlink(newHardlink: localHardlink, withImage: newConfig.thumbnail)
    }
    
    
    func getAllShownHardLink() -> [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)] {
        var hardlinks = [(HardLinkToFyle, UIView)]()
        if let hardlink = imageView.hardlink {
            hardlinks.append((hardlink, imageView))
        }
        return hardlinks
    }

}

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
import CoreData
import ObvUICoreData


final class FyleProgressView: UIView, UIViewWithTappableStuff {
    
    enum FyleProgressViewConfiguration: Equatable, CustomDebugStringConvertible {
        // For sent attachments
        case uploadableOrUploading(progress: Progress)
        // For received attachments
        case downloadable(receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>, progress: Progress)
        case downloading(receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>, progress: Progress)
        case cancelled
        // For received attachments sent from other owned device
        case downloadableSent(sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>, progress: Progress)
        case downloadingSent(sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>, progress: Progress)
        // For both
        case complete
        var debugDescription: String {
            switch self {
            case .uploadableOrUploading(progress: let progress):
                return "FyleProgressViewConfiguration.uploadableOrUploading<progress: \(progress.debugDescription)>"
            case .downloadable(receivedJoinObjectID: let receivedJoinObjectID, progress: let progress):
                return "FyleProgressViewConfiguration.downloadable<receivedJoinObjectID: \(receivedJoinObjectID.debugDescription), progress: \(progress.debugDescription)>"
            case .downloadableSent(sentJoinObjectID: let sentJoinObjectID, progress: let progress):
                return "FyleProgressViewConfiguration.downloadableSent<sentJoinObjectID: \(sentJoinObjectID.debugDescription), progress: \(progress.debugDescription)>"
            case .downloading(receivedJoinObjectID: let receivedJoinObjectID, progress: let progress):
                return "FyleProgressViewConfiguration.downloading<receivedJoinObjectID: \(receivedJoinObjectID.debugDescription), progress: \(progress.debugDescription)>"
            case .downloadingSent(sentJoinObjectID: let sentJoinObjectID, progress: let progress):
                return "FyleProgressViewConfiguration.downloadingSent<sentJoinObjectID: \(sentJoinObjectID.debugDescription), progress: \(progress.debugDescription)>"
            case .cancelled:
                return "FyleProgressViewConfiguration.cancelled"
            case .complete:
                return "FyleProgressViewConfiguration.complete"
            }
        }
    }
    
    
    private var currentConfiguration: FyleProgressViewConfiguration?
    
    
    func setConfiguration(_ newConfiguration: FyleProgressViewConfiguration) {
        guard self.currentConfiguration != newConfiguration else { return }
        self.currentConfiguration = newConfiguration
        refresh()
    }
    
    private func refresh() {
        switch currentConfiguration {
        case .uploadableOrUploading(progress: let progress):
            imageViewWhenPaused.isHidden = true
            imageViewWhenDownloading.isHidden = true
            imageViewWhenCancelled.isHidden = true
            imageViewWhenUploading.isHidden = false
            progressView.isHidden = false
            progressView.observedProgress = progress
            isUserInteractionEnabled = false
        case .downloadable(_, progress: let progress), .downloadableSent(_, progress: let progress):
            imageViewWhenPaused.isHidden = false
            imageViewWhenDownloading.isHidden = true
            imageViewWhenCancelled.isHidden = true
            imageViewWhenUploading.isHidden = true
            progressView.isHidden = (progress.completedUnitCount == 0)
            progressView.observedProgress = progress
            isUserInteractionEnabled = true
        case .downloading(_, progress: let progress), .downloadingSent(_, progress: let progress):
            imageViewWhenPaused.isHidden = true
            imageViewWhenDownloading.isHidden = false
            imageViewWhenCancelled.isHidden = true
            imageViewWhenUploading.isHidden = true
            progressView.isHidden = false
            progressView.observedProgress = progress
            isUserInteractionEnabled = true
        case .cancelled:
            imageViewWhenPaused.isHidden = true
            imageViewWhenDownloading.isHidden = true
            imageViewWhenCancelled.isHidden = false
            imageViewWhenUploading.isHidden = true
            progressView.isHidden = true
            isUserInteractionEnabled = false
        case .complete:
            imageViewWhenPaused.isHidden = true
            imageViewWhenDownloading.isHidden = true
            imageViewWhenCancelled.isHidden = true
            imageViewWhenUploading.isHidden = true
            progressView.isHidden = true
            isUserInteractionEnabled = false
        case .none:
            assertionFailure()
        }
    }
    
    
    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        guard acceptTapOutsideBounds || self.bounds.contains(tapGestureRecognizer.location(in: self)) else { return nil }
        guard !self.isHidden else { return nil }
        switch currentConfiguration {
        case .downloading(receivedJoinObjectID: let receivedJoinObjectID, progress: _):
            return .receivedFyleMessageJoinWithStatusToPauseDownload(receivedJoinObjectID: receivedJoinObjectID)
        case .downloadable(receivedJoinObjectID: let receivedJoinObjectID, progress: _):
            return .receivedFyleMessageJoinWithStatusToResumeDownload(receivedJoinObjectID: receivedJoinObjectID)
        case .downloadingSent(sentJoinObjectID: let sentJoinObjectID, progress: _):
            return .sentFyleMessageJoinWithStatusReceivedFromOtherOwnedDeviceToPauseDownload(sentJoinObjectID: sentJoinObjectID)
        case .downloadableSent(sentJoinObjectID: let sentJoinObjectID, progress: _):
            return .sentFyleMessageJoinWithStatusReceivedFromOtherOwnedDeviceToResumeDownload(sentJoinObjectID: sentJoinObjectID)
        case .uploadableOrUploading, .cancelled, .complete, .none:
            return nil
        }
    }

    
    private let imageViewWhenPaused = UIImageView()
    private let imageViewWhenDownloading = UIImageView()
    private let imageViewWhenUploading = UIImageView()
    private let imageViewWhenCancelled = UIImageView()
    private let progressView = UIProgressView()

    
    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupInternalViews() {
        
        backgroundColor = .clear
        
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 33, weight: .bold)

        addSubview(imageViewWhenPaused)
        imageViewWhenPaused.translatesAutoresizingMaskIntoConstraints = false
        imageViewWhenPaused.image = UIImage(systemIcon: .arrowDownCircle, withConfiguration: symbolConfig)!

        addSubview(imageViewWhenDownloading)
        imageViewWhenDownloading.translatesAutoresizingMaskIntoConstraints = false
        imageViewWhenDownloading.image = UIImage(systemIcon: .pauseCircle, withConfiguration: symbolConfig)!
        imageViewWhenDownloading.isHidden = true

        addSubview(imageViewWhenUploading)
        imageViewWhenUploading.translatesAutoresizingMaskIntoConstraints = false
        imageViewWhenUploading.image = UIImage(systemIcon: .arrowUpCircle, withConfiguration: symbolConfig)!
        imageViewWhenUploading.isHidden = true

        addSubview(imageViewWhenCancelled)
        imageViewWhenCancelled.translatesAutoresizingMaskIntoConstraints = false
        imageViewWhenCancelled.image = UIImage(systemIcon: .exclamationmarkCircle, withConfiguration: symbolConfig)!
        imageViewWhenCancelled.isHidden = true

        addSubview(progressView)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.isHidden = true
        
        let fyleProgressSize = MessageCellConstants.fyleProgressSize
        let constraints = [

            self.widthAnchor.constraint(equalToConstant: fyleProgressSize),
            self.heightAnchor.constraint(equalToConstant: fyleProgressSize),

            imageViewWhenPaused.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            imageViewWhenPaused.centerYAnchor.constraint(equalTo: self.centerYAnchor),

            imageViewWhenDownloading.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            imageViewWhenDownloading.centerYAnchor.constraint(equalTo: self.centerYAnchor),

            imageViewWhenUploading.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            imageViewWhenUploading.centerYAnchor.constraint(equalTo: self.centerYAnchor),

            imageViewWhenCancelled.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            imageViewWhenCancelled.centerYAnchor.constraint(equalTo: self.centerYAnchor),

            progressView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            progressView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
        ]
        
        NSLayoutConstraint.activate(constraints)
        
    }
    
    override var intrinsicContentSize: CGSize {
        CGSize(width: MessageCellConstants.fyleProgressSize, height: MessageCellConstants.fyleProgressSize)
    }
        
}

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
import MobileCoreServices
import CoreData
import ObvUI
import ObvUICoreData


final class CollectionOfFylesView: ObvRoundedRectView {

    let imageAttachments: [(attachment: FyleMessageJoinWithStatus, worker: ThumbnailWorker, imagePlaceholder: UIView)]
    let nonImageAttachments: [(attachment: FyleMessageJoinWithStatus, worker: ThumbnailWorker, backgroundView: UIView)]
    let hideProgresses: Bool

    private var progressObservationTokens = Set<NSKeyValueObservation>()
    
    private let byteCountFormatter = ByteCountFormatter()
    
    private let mainStackView = UIStackView()
        
    /// The `FyleMessageJoinWithStatus` items, ordered as displayed to the user
    var fyleMessagesJoinWithStatus: [FyleMessageJoinWithStatus] {
        let images = imageAttachments.map { $0.attachment }
        let nonImages = nonImageAttachments.map { $0.attachment }
        return images + nonImages
    }
    
    init(attachments: [FyleMessageJoinWithStatus], hideProgresses: Bool) {
        assert(!attachments.isEmpty)
        self.hideProgresses = hideProgresses
        self.imageAttachments = attachments.compactMap {
            guard ObvUTIUtils.uti($0.uti, conformsTo: kUTTypeImage) else { return nil }
            guard let fyleElement = $0.fyleElement else { return nil }
            let worker = ThumbnailWorker(fyleElement: fyleElement)
            let imageViewPlaceholder = UIView()
            return ($0, worker, imageViewPlaceholder)
        }
        self.nonImageAttachments = attachments.compactMap {
            guard !ObvUTIUtils.uti($0.uti, conformsTo: kUTTypeImage) else { return nil}
            guard let fyleElement = $0.fyleElement else { return nil }
            let worker = ThumbnailWorker(fyleElement: fyleElement)
            let backgroundView = UIView()
            return ($0, worker, backgroundView)
        }
        super.init(frame: CGRect.zero)
        setup()
    }
    
    deinit {
        progressObservationTokens.forEach({ $0.invalidate() })
    }
    
    private static func thumbnailTypeFor(attachment: FyleMessageJoinWithStatus) -> ThumbnailType {
        if attachment.isWiped {
            return .wiped
        } else if (attachment.message as? PersistedMessageReceived)?.readingRequiresUserAction == true {
            return .visibilityRestricted
        } else {
            return .normal
        }
    }
    

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    

    /// This is typically called when the user taps on a readOnce message. In that case, we want to refresh the thumbnails.
    func refresh() {
        for thing in imageAttachments {
            let thumbnailType = CollectionOfFylesView.thumbnailTypeFor(attachment: thing.attachment)
            let fyleIsAvailable = thing.attachment.fullFileIsAvailable
            showThumbnail(in: thing.imagePlaceholder, thumbnailType: thumbnailType, fyleIsAvailable: fyleIsAvailable, using: thing.worker)
        }
    }

    
    private func setup() {
        
        self.accessibilityIdentifier = "CollectionOfFylesView"
        self.translatesAutoresizingMaskIntoConstraints = false
        self.clipsToBounds = true

        mainStackView.accessibilityIdentifier = "mainStackView"
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.alignment = .fill
        mainStackView.axis = .vertical
        mainStackView.spacing = 4.0
        self.addSubview(mainStackView)

        if !imageAttachments.isEmpty {
            setupImageFyleStackView()
        }
        
        if !nonImageAttachments.isEmpty {
            setupNonImageAttachmentStackView()
        }
        
        setupConstraints()
    }
    
    
    private func setupImageFyleStackView() {
        
        for index in stride(from: 0, to: imageAttachments.count, by: 2) {
            
            let imageFyleStackView = UIStackView()
            imageFyleStackView.accessibilityIdentifier = "imageFyleStackView for index \(index)"
            imageFyleStackView.translatesAutoresizingMaskIntoConstraints = false
            imageFyleStackView.alignment = .fill
            imageFyleStackView.axis = .horizontal
            imageFyleStackView.spacing = 4.0
            mainStackView.addArrangedSubview(imageFyleStackView)

            let numberPhotosInRow = min(2, imageAttachments.count - index) // 1 or 2
            
            var imagePlaceHolderConstraints = [NSLayoutConstraint]()
            
            for subindex in 0..<numberPhotosInRow {
                
                let (attachment, worker, imageViewPlaceholder) = imageAttachments[index + subindex]

                imageViewPlaceholder.clipsToBounds = true
                imageViewPlaceholder.accessibilityIdentifier = "imageView"
                imageViewPlaceholder.translatesAutoresizingMaskIntoConstraints = false
                imageViewPlaceholder.backgroundColor = AppTheme.shared.colorScheme.systemBackground
                imageViewPlaceholder.clipsToBounds = true

                let multipler = (imageAttachments.count == 1) ? 1 : CGFloat(2 / numberPhotosInRow)
                imagePlaceHolderConstraints.append(imageViewPlaceholder.widthAnchor.constraint(equalTo: imageViewPlaceholder.heightAnchor, multiplier: multipler))

                if imageAttachments.count == 1 {
                    imagePlaceHolderConstraints.append(imageViewPlaceholder.heightAnchor.constraint(equalTo: mainStackView.widthAnchor))
                } else {
                    imagePlaceHolderConstraints.append(imageViewPlaceholder.heightAnchor.constraint(equalTo: mainStackView.widthAnchor, multiplier: 0.5, constant: imageFyleStackView.spacing/2))
                }

                imageFyleStackView.addArrangedSubview(imageViewPlaceholder)
                                    
                self.showThumbnailOrProgressForAttachment(attachment, in: imageViewPlaceholder, using: worker, progress: attachment.progressObject)
                                    
            }
            
            _ = imagePlaceHolderConstraints.map { $0.priority = .defaultHigh }
            NSLayoutConstraint.activate(imagePlaceHolderConstraints)
            
        }

    }
    
    private func setupNonImageAttachmentStackView() {
        
        for (nonImageAttachment, worker, backgroundView) in nonImageAttachments {
            
            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.backgroundColor = AppTheme.shared.colorScheme.surfaceLight
            mainStackView.addArrangedSubview(backgroundView)

            let nonImageAttachmentStackView = UIStackView()
            nonImageAttachmentStackView.accessibilityIdentifier = "nonImageAttachmentStackView"
            nonImageAttachmentStackView.translatesAutoresizingMaskIntoConstraints = false
            nonImageAttachmentStackView.alignment = .center
            nonImageAttachmentStackView.axis = .horizontal
            nonImageAttachmentStackView.spacing = 4.0
            nonImageAttachmentStackView.clipsToBounds = true
            nonImageAttachmentStackView.backgroundColor = .white
            backgroundView.addSubview(nonImageAttachmentStackView)
            
            let square = UIView()
            square.accessibilityIdentifier = "square"
            square.translatesAutoresizingMaskIntoConstraints = false
            square.backgroundColor = AppTheme.shared.colorScheme.surfaceMedium
            square.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            square.setContentCompressionResistancePriority(.required, for: .horizontal)
            square.clipsToBounds = true
            nonImageAttachmentStackView.addArrangedSubview(square)
            
            let textsStackView = UIStackView()
            textsStackView.translatesAutoresizingMaskIntoConstraints = false
            textsStackView.accessibilityIdentifier = "textsStackView"
            textsStackView.axis = .vertical
            textsStackView.alignment = .leading
            nonImageAttachmentStackView.addArrangedSubview(textsStackView)
            
            let title = UILabel()
            title.translatesAutoresizingMaskIntoConstraints = false
            title.text = nonImageAttachment.fileName
            title.font = UIFont.preferredFont(forTextStyle: .caption1)
            title.textColor = appTheme.colorScheme.blackTextHighEmphasis
            title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            title.lineBreakMode = .byTruncatingMiddle
            textsStackView.addArrangedSubview(title)

            let subtitle = UILabel()
            subtitle.translatesAutoresizingMaskIntoConstraints = false
            let byteCountText = byteCountFormatter.string(fromByteCount: nonImageAttachment.fyle?.getFileSize() ?? nonImageAttachment.totalByteCount)
            if let mimeType = ObvUTIUtils.getHumanReadableType(forUTI: nonImageAttachment.uti) {
                subtitle.text = "\(byteCountText) - \(mimeType)"
            } else {
                subtitle.text = "\(byteCountText)"
            }
            subtitle.font = UIFont.preferredFont(forTextStyle: .caption2)
            subtitle.textColor = appTheme.colorScheme.blackTextMediumEmphasis
            subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            subtitle.lineBreakMode = .byTruncatingMiddle
            textsStackView.addArrangedSubview(subtitle)

            let constraints = [
                square.widthAnchor.constraint(equalTo: square.heightAnchor),
                square.widthAnchor.constraint(equalToConstant: 60.0),
                backgroundView.topAnchor.constraint(equalTo: nonImageAttachmentStackView.topAnchor),
                backgroundView.trailingAnchor.constraint(equalTo: nonImageAttachmentStackView.trailingAnchor, constant: 4.0),
                backgroundView.bottomAnchor.constraint(equalTo: nonImageAttachmentStackView.bottomAnchor),
                backgroundView.leadingAnchor.constraint(equalTo: nonImageAttachmentStackView.leadingAnchor),
            ]
            _ = constraints.map { $0.priority = .defaultHigh }
            NSLayoutConstraint.activate(constraints)
            
            self.showThumbnailOrProgressForAttachment(nonImageAttachment, in: square, using: worker, progress: nonImageAttachment.progressObject)

        }

    }
    

    private func showThumbnailOrProgressForAttachment(_ attachment: FyleMessageJoinWithStatus, in imageViewPlaceholder: UIView, using worker: ThumbnailWorker, progress: Progress) {

        assert(Thread.isMainThread)
        
        let thumbnailType = CollectionOfFylesView.thumbnailTypeFor(attachment: attachment)
        
        let attachmentIsComplete: Bool
        let fyleIsAvailable = attachment.fullFileIsAvailable
        if let sentAttachment = attachment as? SentFyleMessageJoinWithStatus {
            attachmentIsComplete = (sentAttachment.status == .complete)
            self.showThumbnail(in: imageViewPlaceholder, thumbnailType: thumbnailType, fyleIsAvailable: fyleIsAvailable, using: worker)
        } else if let receivedAttachment = attachment as? ReceivedFyleMessageJoinWithStatus {
            attachmentIsComplete = (receivedAttachment.status == .complete)
        } else {
            assertionFailure()
            return
        }
        
        if attachmentIsComplete {
            
            for subview in imageViewPlaceholder.subviews {
                if subview is ObvCircledProgressView {
                    subview.removeFromSuperview()
                }
            }
            self.showThumbnail(in: imageViewPlaceholder, thumbnailType: thumbnailType, fyleIsAvailable: fyleIsAvailable, using: worker)
            
        } else if !hideProgresses {
            
            if let obvCircleProgressView = imageViewPlaceholder.subviews.first(where: { $0 is ObvCircledProgressView }) as? ObvCircledProgressView {

                if obvCircleProgressView.observedProgress != progress {
                    obvCircleProgressView.observedProgress = progress
                }
                
            } else {
                
                let obvCircleProgressView = (Bundle.main.loadNibNamed(ObvCircledProgressView.nibName, owner: nil, options: nil)!.first as! ObvCircledProgressView)
                obvCircleProgressView.accessibilityIdentifier = "obvCircleProgressView"
                obvCircleProgressView.tintColor = .lightGray
                obvCircleProgressView.progressColor = AppTheme.shared.colorScheme.primary700
                obvCircleProgressView.imageWhenPaused = UIImage(named: "ProgressIconDownload")
                obvCircleProgressView.imageWhenDownloading = UIImage(named: "ProgressIconPause")
                obvCircleProgressView.imageWhenCancelled = UIImage(named: "ProgressIconCancelled")
                obvCircleProgressView.observedProgress = progress
                if let receivedAttachment = attachment as? ReceivedFyleMessageJoinWithStatus {
                    if receivedAttachment.status == .cancelledByServer {
                        obvCircleProgressView.showAsCancelled()
                    }
                }
                imageViewPlaceholder.addSubview(obvCircleProgressView)
                
                let constraints = [
                    obvCircleProgressView.centerXAnchor.constraint(equalTo: imageViewPlaceholder.centerXAnchor),
                    obvCircleProgressView.centerYAnchor.constraint(equalTo: imageViewPlaceholder.centerYAnchor),
                    obvCircleProgressView.widthAnchor.constraint(equalTo: obvCircleProgressView.heightAnchor),
                    obvCircleProgressView.widthAnchor.constraint(equalToConstant: 50),
                ]
                NSLayoutConstraint.activate(constraints)
                
                obvCircleProgressView.setNeedsLayout()
                obvCircleProgressView.layoutIfNeeded()
                
                progressObservationTokens.insert(attachment.observe(\.rawStatus, options: .initial) { [weak self] (attachment, change) in
                    assert(Thread.isMainThread)
                    // For legacy reasons, we modify the progress here depending on the attachment status
                    if let receivedAttachment = attachment as? ReceivedFyleMessageJoinWithStatus {
                        progress.isPausable = true
                        switch receivedAttachment.status {
                        case .downloadable:
                            progress.pause()
                        case .downloading:
                            progress.resume()
                        case .complete:
                            progress.resume()
                        case .cancelledByServer:
                            progress.isPausable = false
                        }
                    }
                    self?.showThumbnailOrProgressForAttachment(attachment, in: imageViewPlaceholder, using: worker, progress: progress)
                })
                
            }
            
        }
        
    }
    
    
    private func showThumbnail(in imageViewPlaceholder: UIView, thumbnailType: ThumbnailType, fyleIsAvailable: Bool, using worker: ThumbnailWorker) {
        // We check whether the last computed thumbnail is not already sufficient. If this is the case, we don't do anything.
        if let lastComputedThumnbnail = worker.lastComputedThumnbnail, lastComputedThumnbnail.type == thumbnailType, !lastComputedThumnbnail.isSymbol {
            return
        }
        let size = CGSize(width: UIScreen.main.bounds.size.width, height: UIScreen.main.bounds.size.height)
        if let lastComputedThumnbnail = worker.lastComputedThumnbnail, lastComputedThumnbnail == (thumbnailType, false) {
            return
        }
        worker.createThumbnail(size: size, thumbnailType: thumbnailType, fyleIsAvailable: fyleIsAvailable) { [weak self] (thumbnail) in
            DispatchQueue.main.async {
                self?.showThumbnail(thumbnail, in: imageViewPlaceholder, animate: true)
            }
        }
    }
    
    private func showThumbnail(_ thumbnail: Thumbnail, in imageViewPlaceholder: UIView, animate: Bool) {
        // We make sure there isn't a UIImage already
        for previousImageView in imageViewPlaceholder.subviews.filter({ $0 is UIImageView }) {
            previousImageView.removeFromSuperview()
        }
        let imageView = UIImageView(image: thumbnail.image)
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleAspectFill
        if thumbnail.isSymbol {
            // If the thumbnail was obtained using a symbol (typically, an SF symbol), we center it in a square
            let side: CGFloat = min(imageViewPlaceholder.bounds.width, imageViewPlaceholder.bounds.height) / 2.0
            let size = CGSize(width: side, height: side)
            let origin = CGPoint(x: imageViewPlaceholder.bounds.width/2-side/2, y: imageViewPlaceholder.bounds.height/2-side/2)
            imageView.frame = CGRect(origin: origin, size: size)
            imageView.tintColor = appTheme.colorScheme.systemFill
        } else {
            // If the thumbnail is not a symbol, but an actual thumbnail of the attachment, we do not add any padding
            imageView.frame = CGRect(origin: CGPoint.zero, size: imageViewPlaceholder.bounds.size)
        }
        imageView.isHidden = true
        imageViewPlaceholder.insertSubview(imageView, at: 0)
        if animate {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                UIView.transition(with: imageViewPlaceholder, duration: 0.3, options: .transitionCrossDissolve, animations: {
                    imageView.isHidden = false
                })
            }
        } else {
            imageView.isHidden = false
        }
    }

    
    private func setupConstraints() {
        let constraints = [
            mainStackView.topAnchor.constraint(equalTo: self.topAnchor, constant: 0),
            mainStackView.rightAnchor.constraint(equalTo: self.rightAnchor, constant: 0),
            mainStackView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0),
            mainStackView.leftAnchor.constraint(equalTo: self.leftAnchor, constant: 0),
        ]
        NSLayoutConstraint.activate(constraints)
    }
        
}


// MARK: - Utilities for locating attachments on tap

extension CollectionOfFylesView {
    
    /// The point is in the coordinate space of this CollectionOfFylesView
    func fyleMessageJoinWithStatus(at point: CGPoint) -> FyleMessageJoinWithStatus? {
        
        // Detect taps on imageView
        for (attachment, _, imagePlaceholder) in imageAttachments {
            let newPoint = convert(point, to: imagePlaceholder)
            if imagePlaceholder.bounds.contains(newPoint) {
                return attachment
            }
        }
        
        // Detect taps on non-image attachments
        for (attachment, _, backgroundView) in nonImageAttachments {
            let newPoint = convert(point, to: backgroundView)
            if backgroundView.bounds.contains(newPoint) {
                return attachment
            }
        }
        
        return nil
    }
    
    func thumbnailViewOfFyleMessageJoinWithStatus(_ attachment: FyleMessageJoinWithStatus) -> UIView? {
        for imageAttachment in imageAttachments {
            if imageAttachment.attachment == attachment {
                return imageAttachment.imagePlaceholder.subviews.first
            }
        }
        for nonImageAttachment in nonImageAttachments {
            if nonImageAttachment.attachment == attachment {
                let backgroundView = nonImageAttachment.backgroundView
                guard let nonImageAttachmentStackView = backgroundView.subviews.first as? UIStackView else { return nil }
                guard let square = nonImageAttachmentStackView.arrangedSubviews.first else { return nil }
                return square.subviews.first
            }
        }
        return nil
    }
    
}

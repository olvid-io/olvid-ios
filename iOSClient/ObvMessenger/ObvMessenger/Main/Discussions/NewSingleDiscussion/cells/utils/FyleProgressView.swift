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


@available(iOS 13.0, *)
final class FyleProgressView: UIView {
    
    enum FyleProgressViewConfiguration: Equatable {
        // For sent attachments
        case uploadableOrUploading(progress: Progress?)
        // For received attachments
        case pausedOrDownloading(progress: Progress?)
        case cancelled
        // For both
        case complete
    }
    
    
    private var currentConfiguration: FyleProgressViewConfiguration?
    
    
    func setConfiguration(_ newConfiguration: FyleProgressViewConfiguration) {
        guard self.currentConfiguration != newConfiguration else { return }
        self.currentConfiguration = newConfiguration
        refresh()
    }
    
    private static var progressObservations = [(progress: Progress, token: NSKeyValueObservation)]()
    
    private func refresh() {
        switch currentConfiguration {
        case .uploadableOrUploading(progress: let progress):
            imageViewWhenPaused.isHidden = true
            imageViewWhenDownloading.isHidden = true
            imageViewWhenCancelled.isHidden = true
            imageViewWhenUploading.isHidden = false
            progressView.isHidden = false
            progressView.progress = 0
            progressView.observedProgress = progress
            isUserInteractionEnabled = false
        case .pausedOrDownloading(progress: let progress):
            if let progress = progress {
                imageViewWhenPaused.isHidden = !progress.isPaused
                imageViewWhenDownloading.isHidden = progress.isPaused
            } else {
                imageViewWhenPaused.isHidden = false
                imageViewWhenDownloading.isHidden = true
            }
            imageViewWhenCancelled.isHidden = true
            imageViewWhenUploading.isHidden = true
            progressView.isHidden = progress?.isPaused ?? true
            if let progress = progress, !FyleProgressView.progressObservations.map({ $0.progress }).contains(progress) {
                // We observe this new progress
                let token = progress.observe(\.isPaused, changeHandler: { [weak self] progress, _ in
                    DispatchQueue.main.async {
                        guard self?.progressView.observedProgress == progress else { return }
                        self?.progressView.isHidden = progress.isPaused
                        self?.imageViewWhenPaused.isHidden = !progress.isPaused
                        self?.imageViewWhenDownloading.isHidden = progress.isPaused
                    }
                })
                FyleProgressView.progressObservations.append((progress, token))
            }
            progressView.observedProgress = progress
            isUserInteractionEnabled = true
        case .cancelled:
            imageViewWhenPaused.isHidden = true
            imageViewWhenDownloading.isHidden = true
            imageViewWhenCancelled.isHidden = false
            imageViewWhenUploading.isHidden = true
            progressView.isHidden = true
            progressView.observedProgress = nil
            progressView.progress = 0
            isUserInteractionEnabled = false
        case .complete:
            imageViewWhenPaused.isHidden = true
            imageViewWhenDownloading.isHidden = true
            imageViewWhenCancelled.isHidden = true
            imageViewWhenUploading.isHidden = true
            progressView.isHidden = true
            progressView.observedProgress = nil
            progressView.progress = 0
            isUserInteractionEnabled = false
        case .none:
            assertionFailure()
        }
    }
    
    
    @objc private func userDidTap() {
        switch currentConfiguration {
        case .pausedOrDownloading(progress: let progress):
            guard let progress = progress else { assertionFailure(); return }
            if progress.isPaused {
                progress.resume()
            } else {
                progress.pause()
            }
        default:
            return
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
        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(userDidTap)))
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

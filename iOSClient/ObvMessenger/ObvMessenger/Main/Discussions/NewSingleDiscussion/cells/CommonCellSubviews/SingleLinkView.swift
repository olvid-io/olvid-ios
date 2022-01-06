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
import LinkPresentation


@available(iOS 13.0, *)
final class SingleLinkView: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator {
    
    enum Configuration: Equatable, Hashable {
        case metadataNotYetAvailable(url: URL)
        case metadataAvailable(url: URL, metadata: LPLinkMetadata)
    }
    
    private var currentConfiguration: Configuration?

    func setConfiguration(newConfiguration: Configuration) {
        guard newConfiguration != currentConfiguration else { return }
        self.currentConfiguration = newConfiguration
        switch newConfiguration {
        case .metadataNotYetAvailable(url: _):
            coverView.alpha = 1.0
            spinner.alpha = 1.0
            spinner.startAnimating()
        case .metadataAvailable(url: _, metadata: let metadata):
            linkView.metadata = metadata
            UIView.animate(withDuration: 0.3) { [weak self] in
                self?.coverView.alpha = 0
            }
        }
    }
    
    
    func prepareForReuse() {
        spinner.startAnimating()
    }
    
    var maskedCorner: UIRectCorner {
        get { bubble.maskedCorner }
        set { bubble.maskedCorner = newValue }
    }

    private let bubble = BubbleView()
    private let linkView = LPLinkView()
    private let coverView = UIView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let size = CGFloat(200)
    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side

    
    init(expirationIndicatorSide side: ExpirationIndicatorView.Side) {
        self.expirationIndicatorSide = side
        super.init(frame: .zero)
        setupInternalViews()
    }
    

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    private func setupInternalViews() {
                        
        addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = nil

        addSubview(expirationIndicator)
        expirationIndicator.translatesAutoresizingMaskIntoConstraints = false

        bubble.addSubview(linkView)
        linkView.translatesAutoresizingMaskIntoConstraints = false
        
        bubble.addSubview(coverView)
        coverView.translatesAutoresizingMaskIntoConstraints = false
        coverView.backgroundColor = .secondarySystemBackground
        
        coverView.addSubview(spinner)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = false
        spinner.startAnimating()
                
        NSLayoutConstraint.activate([
            bubble.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: self.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            linkView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            linkView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
            linkView.topAnchor.constraint(equalTo: bubble.topAnchor),
            linkView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            coverView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
            coverView.topAnchor.constraint(equalTo: bubble.topAnchor),
            coverView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: coverView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: coverView.centerYAnchor),
        ])
        
        let sizeConstraints = [
            bubble.widthAnchor.constraint(equalToConstant: size),
            bubble.heightAnchor.constraint(equalToConstant: size),
        ]
        _ = sizeConstraints.map({ $0.priority -= 1 })
        NSLayoutConstraint.activate(sizeConstraints)
        
        setupConstraintsForExpirationIndicator(gap: MessageCellConstants.gapBetweenExpirationViewAndBubble)

    }

}

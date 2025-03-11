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
import LinkPresentation
import UniformTypeIdentifiers
import OlvidUtils

final class SinglePreviewView: ViewForOlvidStack {
    
    //MARK: enum - Configuration
    enum Configuration: Equatable, Hashable {
        case downloadable
        case downloadingOrDecoding
        case completeButReadRequiresUserInteraction
        case cancelledByServer
        case complete(preview: ObvLinkMetadata)
        
        var isComplete: Bool {
            switch self {
            case .complete:
                return true
            default:
                return false
            }
        }
        
        var preview: ObvLinkMetadata? {
            switch self {
            case .downloadable, .downloadingOrDecoding, .completeButReadRequiresUserInteraction, .cancelledByServer:
                return nil
            case .complete(let preview):
                return preview
            }
        }
        
    }
    
    //MARK: attributes - public
    var currentConfiguration: SinglePreviewView.Configuration? {
        didSet {
            guard currentConfiguration != oldValue else { return }
            updateUI()
        }
    }
    
    //MARK: attributes - public - static
    private static let thresholdForIconSize = CGSize(width: 400, height: 400) // in pixels
    private static let cellSize = CGSize(width: 280.0, height: 280.0)
    
    //MARK: attributes - private - UI
    private let bubbleView = BubbleView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let previewImageView = UIImageView()
    private let titleView = UIView()
    private let mainVStackView = UIStackView()
    private let bottomHStackView = UIStackView()
    private let titleAndLinkVStackView = UIStackView()
    private let titleLabel = UILabel()
    private let descLabel = UILabel()
    private let urlLabel = UILabel()
    private let iconPreviewImageView = UIImageView()

    //MARK: attributes - private - Constraints
    private var previewHeightConstraint: NSLayoutConstraint?

    
    //MARK: attributes - public - Extension - ViewWithExpirationIndicator
    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side
    
    //MARK: methods - life cycle
    init(expirationIndicatorSide side: ExpirationIndicatorView.Side) {
        self.expirationIndicatorSide = side
        super.init(frame: .zero)
        setupInternalViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func prepareForReuse() {
        spinner.startAnimating()
    }
    
    //MARK: Methods - UI
    private func updateUI() {
        switch currentConfiguration {
        case .downloadingOrDecoding,
                .downloadable,
                .completeButReadRequiresUserInteraction:
            spinner.alpha = 1.0
            spinner.startAnimating()
            previewImageView.alpha = 0.0
            bubbleView.backgroundColor = .systemFill
            cleanTitle()
            setSizeConstraints(size: CGSize(width: SinglePreviewView.cellSize.width, height: SinglePreviewView.cellSize.height / 2.0))
        case .cancelledByServer:
            spinner.alpha = 0.0
            spinner.stopAnimating()
            previewImageView.alpha = 0.0
            bubbleView.backgroundColor = .systemFill
            cleanTitle()
            setSizeConstraints(size: CGSize(width: SinglePreviewView.cellSize.width, height: SinglePreviewView.cellSize.height / 2.0))
        case let .complete(preview: preview):
            spinner.alpha = 0.0
            spinner.stopAnimating()
            bubbleView.backgroundColor = .secondarySystemBackground
            updateMetadata(preview: preview)
        case .none:
            assertionFailure()
        }
    }
    
    private func updateMetadata(preview: ObvLinkMetadata) {
        
        if let title = preview.title {
            self.titleLabel.text = title
            self.titleLabel.isHidden = false
        } else {
            self.titleLabel.isHidden = true
        }
        
        if let description = preview.desc {
            self.descLabel.text = description
            self.descLabel.isHidden = false
            self.descLabel.numberOfLines = ObvMessengerConstants.LinkPreview.numberOfLinesForDescriptions // May be reset bellow
        } else {
            self.descLabel.isHidden = true
        }
        
        if let url = preview.url?.toHttpsURL?.host {
            let domain = url.replacingOccurrences(of: "^www.", with: "", options: .regularExpression)
            self.urlLabel.text = domain
            self.urlLabel.isHidden = false
            if ObvMessengerConstants.LinkPreview.domainsWithLongDescription.contains(domain) {
                self.descLabel.numberOfLines = 0
            }
        } else {
            self.urlLabel.isHidden = true
        }
        
        titleView.alpha = 1.0
        
        if let image = preview.image {
            if image.size.width < Self.thresholdForIconSize.width && image.size.height < Self.thresholdForIconSize.height {
                self.iconPreviewImageView.image = image
                self.iconPreviewImageView.contentMode = .scaleAspectFit
                self.iconPreviewImageView.isHidden = false
                self.spinner.alpha = 0.0
                self.spinner.stopAnimating()
                cleanPreviewImage(force: true)
                self.previewImageView.alpha = 0.0
            } else {
                iconPreviewImageView.isHidden = true
                if self.previewImageView.image != image {
                    cleanPreviewImage()
                }
                self.spinner.alpha = 0.0
                self.spinner.stopAnimating()
                setPreviewImage(with: image)
                self.previewImageView.alpha = 1.0
            }
        } else {
            iconPreviewImageView.isHidden = true
            cleanPreviewImage(force: true)
        }
    }
    
    private func cleanPreviewImage(force: Bool = false) {
        self.previewImageView.image = nil
        self.previewImageView.alpha = 0.0
        self.setSizeConstraints(size: force ? CGSize(width: SinglePreviewView.cellSize.width, height: 0.0) : SinglePreviewView.cellSize)
    }
    
    private func cleanTitle() {
        self.titleView.alpha = 0.0
        self.urlLabel.isHidden = true
        self.descLabel.isHidden = true
        self.urlLabel.isHidden = true
        self.iconPreviewImageView.isHidden = true
    }
    
    private func setPreviewImage(with image: UIImage) {
        let imageWidth = image.size.width
        let imageHeight = image.size.height
        let widthRatio = SinglePreviewView.cellSize.width / imageWidth
        let imagereSizedHeight = imageHeight * widthRatio
        
        previewImageView.image = image
        
        setSizeConstraints(size: CGSize(width: SinglePreviewView.cellSize.width, height: imagereSizedHeight))
    }
    
    private func setupInternalViews() {
                        
        addSubview(bubbleView)
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.backgroundColor = .secondarySystemBackground
        
        addSubview(expirationIndicator)
        expirationIndicator.translatesAutoresizingMaskIntoConstraints = false

        bubbleView.addSubview(previewImageView)
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        
        bubbleView.addSubview(titleView)
        titleView.translatesAutoresizingMaskIntoConstraints = false
        titleView.backgroundColor = .secondarySystemBackground
        
        titleView.addSubview(mainVStackView)
        mainVStackView.translatesAutoresizingMaskIntoConstraints = false
        mainVStackView.axis = .vertical

        let descTextSize = 14.0
        let descFontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).withSize(descTextSize).withDesign(.rounded) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).withSize(descTextSize)
        descLabel.font = UIFont(descriptor: descFontDescriptor, size: descTextSize)
        descLabel.textColor = appTheme.colorScheme.label
        descLabel.textAlignment = .left
        descLabel.numberOfLines = 0
        descLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        mainVStackView.addArrangedSubview(descLabel)
        mainVStackView.setCustomSpacing(8.0, after: descLabel)

        mainVStackView.addArrangedSubview(bottomHStackView)
        bottomHStackView.translatesAutoresizingMaskIntoConstraints = false
        bottomHStackView.axis = .horizontal
        bottomHStackView.alignment = .top
        
        bottomHStackView.addArrangedSubview(iconPreviewImageView)
        iconPreviewImageView.translatesAutoresizingMaskIntoConstraints = false
        bottomHStackView.setCustomSpacing(8.0, after: iconPreviewImageView)

        bottomHStackView.addArrangedSubview(titleAndLinkVStackView)
        titleAndLinkVStackView.translatesAutoresizingMaskIntoConstraints = false
        titleAndLinkVStackView.axis = .vertical
        
        let titleTextSize = 14.0
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title1).withSymbolicTraits(.traitBold)?.withSize(titleTextSize).withDesign(.rounded) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title1).withSize(titleTextSize)
        titleLabel.font = UIFont(descriptor: fontDescriptor, size: titleTextSize)
        titleLabel.textAlignment = .left
        titleLabel.numberOfLines = 0
        titleLabel.textColor = appTheme.colorScheme.label
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        titleAndLinkVStackView.addArrangedSubview(titleLabel)

        let urlTextSize = 14.0
        let urlFontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .caption1).withSize(urlTextSize).withDesign(.rounded) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .caption1).withSize(urlTextSize)
        urlLabel.font = UIFont(descriptor: urlFontDescriptor, size: urlTextSize)
        urlLabel.textColor = appTheme.colorScheme.secondaryLabel
        urlLabel.textAlignment = .left
        urlLabel.numberOfLines = 0
        urlLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        titleAndLinkVStackView.addArrangedSubview(urlLabel)

        bubbleView.addSubview(spinner)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = false
        spinner.startAnimating()
        
        let titleEdges = UIEdgeInsets(top: 8.0, left: 15.0, bottom: -8.0, right: -15.0)
        NSLayoutConstraint.activate([
            bubbleView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            bubbleView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bubbleView.topAnchor.constraint(equalTo: self.topAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            
            titleView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
            titleView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor),
            titleView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor),
            
            mainVStackView.topAnchor.constraint(equalTo: titleView.topAnchor, constant: titleEdges.top),
            mainVStackView.trailingAnchor.constraint(equalTo: titleView.trailingAnchor, constant: titleEdges.right),
            mainVStackView.leadingAnchor.constraint(equalTo: titleView.leadingAnchor, constant: titleEdges.left),
            mainVStackView.bottomAnchor.constraint(equalTo: titleView.bottomAnchor, constant: titleEdges.bottom),
            
            previewImageView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor),
            previewImageView.topAnchor.constraint(equalTo: bubbleView.topAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: titleView.topAnchor),
            
            spinner.centerXAnchor.constraint(equalTo: bubbleView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: bubbleView.centerYAnchor),
        ])
        
        let sizeConstraints = [
            iconPreviewImageView.widthAnchor.constraint(equalToConstant: 40.0),
            iconPreviewImageView.heightAnchor.constraint(equalToConstant: 40.0),
        ]
        _ = sizeConstraints.map({ $0.priority -= 1 })
        NSLayoutConstraint.activate(sizeConstraints)
        
        initialSetupSizeConstraint(size: SinglePreviewView.cellSize)
        
        setupConstraintsForExpirationIndicator(gap: MessageCellConstants.gapBetweenExpirationViewAndBubble)

    }
    
    private func initialSetupSizeConstraint(size: CGSize) {
        assert(self.previewHeightConstraint == nil)
        
        let widthConstraint = bubbleView.widthAnchor.constraint(equalToConstant: SinglePreviewView.cellSize.width)
        widthConstraint.priority -= 1
        previewHeightConstraint = previewImageView.heightAnchor.constraint(equalToConstant: size.height)
        previewHeightConstraint!.priority -= 1
        NSLayoutConstraint.activate([widthConstraint, previewHeightConstraint!])
    }
    
    private func setSizeConstraints(size: CGSize) {
        
        guard let previewHeightConstraint = self.previewHeightConstraint else { assertionFailure(); return }
        
        if previewHeightConstraint.constant != size.height {
            previewHeightConstraint.constant = size.height
            setNeedsUpdateConstraints()
        }
        
    }
}

//MARK: extension - ViewWithExpirationIndicator
extension SinglePreviewView: ViewWithExpirationIndicator {}


//MARK: extension - ViewWithMaskedCorners
extension SinglePreviewView: ViewWithMaskedCorners {
    
    var maskedCorner: UIRectCorner {
        get { bubbleView.maskedCorner }
        set { bubbleView.maskedCorner = newValue }
    }

}

//MARK: extension - UIViewWithTappableStuff
extension SinglePreviewView: UIViewWithTappableStuff {
    
    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        guard !self.isHidden && self.showInStack else { return nil }
        guard self.bounds.contains(tapGestureRecognizer.location(in: self)) else { return nil }
        if case let .complete(preview: preview) = currentConfiguration, let url = preview.url {
            return .openLink(url: url)
        }
        
        return nil
    }
    
    
}

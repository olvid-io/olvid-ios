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

import UIKit
import ObvUICoreData
import Combine
import ObvEncoder
import ObvDesignSystem


final class LinkPreviewComposeView: UIView {
    
    @Published var draftFyleJoin: PersistedDraftFyleJoin? // Of type "link preview"
    
    private var linkMetatada: ObvLinkMetadata?
    
    private var cancellables = [AnyCancellable]()
    
    private let contentHStackView = UIStackView()
    private let textVStackView = UIStackView()
    private let textContentView = UIView()
    private let previewImageView = UIImageView()
    private let titleLabel = UILabel()
    private let descLabel = UILabel()
    private let linkLabel = UILabel()
    private let topSeparatorView = UIView()
    private let bottomSeparatorView = UIView()
    private let closeContentView = UIView()
    private var closeButton: UIButton!
    
    private let removePreviewSubject = PassthroughSubject<Void, Never>()
    public var removePreviewPublisher: AnyPublisher<Void, Never> {
        removePreviewSubject.eraseToAnyPublisher()
    }
        
    init(draft: PersistedDraft) {
        
        super.init(frame: .zero)
        
        setupInternalViews()
        observeDraftFyleJoin()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        debugPrint("Deinit")
    }
    
    private func observeDraftFyleJoin() {
        $draftFyleJoin.sink { [weak self] draftFyleJoin in
            guard let self else { return }
            updateLinkMetadata(from: draftFyleJoin)
        }.store(in: &cancellables)
    }

    private func setupStyle() {
        previewImageView.contentMode = .scaleAspectFill
        previewImageView.clipsToBounds = true
        previewImageView.backgroundColor = .clear
        
        contentHStackView.axis = .horizontal
        contentHStackView.backgroundColor = .clear
        
        textVStackView.axis = .vertical
        textVStackView.backgroundColor = .clear
        textVStackView.distribution = .fillEqually
        
        textContentView.backgroundColor = .clear
        
        let titleTextSize = 14.0
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title1).withSymbolicTraits(.traitBold)?.withSize(titleTextSize).withDesign(.rounded) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title1).withSize(titleTextSize)
        titleLabel.font = UIFont(descriptor: fontDescriptor, size: titleTextSize)
        titleLabel.textAlignment = .left
        titleLabel.numberOfLines = 1
        titleLabel.textColor = appTheme.colorScheme.label
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        
        let descTextSize = 14.0
        let descFontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).withSize(descTextSize).withDesign(.rounded) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).withSize(descTextSize)
        descLabel.font = UIFont(descriptor: descFontDescriptor, size: descTextSize)
        descLabel.textColor = appTheme.colorScheme.label
        descLabel.textAlignment = .left
        descLabel.numberOfLines = 1
        descLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        
        let urlTextSize = 14.0
        let urlFontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .caption1).withSize(urlTextSize).withDesign(.rounded) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .caption1).withSize(urlTextSize)
        linkLabel.font = UIFont(descriptor: urlFontDescriptor, size: urlTextSize)
        linkLabel.textColor = appTheme.colorScheme.secondaryLabel
        linkLabel.textAlignment = .left
        linkLabel.numberOfLines = 1
        
        topSeparatorView.backgroundColor = AppTheme.shared.colorScheme.quaternaryLabel
        topSeparatorView.translatesAutoresizingMaskIntoConstraints = false
        
        bottomSeparatorView.backgroundColor = AppTheme.shared.colorScheme.quaternaryLabel
        bottomSeparatorView.translatesAutoresizingMaskIntoConstraints = false
        
        closeContentView.backgroundColor = .clear
        let symbolConfig = UIImage.SymbolConfiguration(textStyle: .body)
        let xmark = UIImage(systemIcon: .xmarkCircleFill, withConfiguration: symbolConfig)!
        closeButton = UIButton.systemButton(with: xmark, target: self, action: #selector(removePreview(sender:)))
    }
    
    @objc
    private func removePreview(sender: UIButton) {
        removePreviewSubject.send(())
    }
    
    private func setupInternalViews() {
        setupStyle()
        
        addSubview(contentHStackView)
        
        contentHStackView.translatesAutoresizingMaskIntoConstraints = false
        contentHStackView.addArrangedSubview(previewImageView)
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        
        contentHStackView.addArrangedSubview(textContentView)
        
        closeContentView.translatesAutoresizingMaskIntoConstraints = false
        contentHStackView.addArrangedSubview(closeContentView)
        
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeContentView.addSubview(closeButton)
        
        textContentView.addSubview(textVStackView)
        textVStackView.translatesAutoresizingMaskIntoConstraints = false
        
        textVStackView.addArrangedSubview(titleLabel)
        
        textVStackView.addArrangedSubview(descLabel)
        
        textVStackView.addArrangedSubview(linkLabel)
        
        addSubview(topSeparatorView)
        
        addSubview(bottomSeparatorView)
        
        let titleEdges = UIEdgeInsets(top: 2.0, left: 8.0, bottom: -2.0, right: -8.0)
        
        NSLayoutConstraint.activate([
            topSeparatorView.leadingAnchor.constraint(equalTo: leadingAnchor),
            topSeparatorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            topSeparatorView.topAnchor.constraint(equalTo: topAnchor),

            bottomSeparatorView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomSeparatorView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomSeparatorView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentHStackView.topAnchor.constraint(equalTo: topSeparatorView.bottomAnchor),
            contentHStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentHStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentHStackView.bottomAnchor.constraint(equalTo: bottomSeparatorView.topAnchor),
            
            textVStackView.topAnchor.constraint(equalTo: textContentView.topAnchor, constant: titleEdges.top),
            textVStackView.trailingAnchor.constraint(equalTo: textContentView.trailingAnchor, constant: titleEdges.right),
            textVStackView.leadingAnchor.constraint(equalTo: textContentView.leadingAnchor, constant: titleEdges.left),
            textVStackView.bottomAnchor.constraint(equalTo: textContentView.bottomAnchor, constant: titleEdges.bottom),
            
            closeButton.leadingAnchor.constraint(equalTo: closeContentView.leadingAnchor),
            closeButton.trailingAnchor.constraint(equalTo: closeContentView.trailingAnchor, constant: -10.0),
            closeButton.topAnchor.constraint(equalTo: closeContentView.topAnchor),
            closeButton.bottomAnchor.constraint(equalTo: closeContentView.bottomAnchor),
        ])
        
        let sizeConstraints = [
            previewImageView.widthAnchor.constraint(equalToConstant: 50.0),
            previewImageView.heightAnchor.constraint(equalToConstant: 50.0),
            closeContentView.widthAnchor.constraint(equalToConstant: 50.0),
            closeContentView.heightAnchor.constraint(equalToConstant: 50.0),
            topSeparatorView.heightAnchor.constraint(equalToConstant: 0.5),
            bottomSeparatorView.heightAnchor.constraint(equalToConstant: 0.5),
        ]
//        _ = sizeConstraints.map({ $0.priority -= 1 })
        NSLayoutConstraint.activate(sizeConstraints)
    }
 
    private func clear() {
        previewImageView.image = nil
        previewImageView.isHidden = true
        titleLabel.text = ""
        titleLabel.isHidden = true
        descLabel.text = ""
        descLabel.isHidden = true
        linkLabel.text = ""
        linkLabel.isHidden = true
    }
    
    private func updateLinkMetadata(from draftFyleJoin: PersistedDraftFyleJoin?) {
        clear()
        
        guard let draftFyleJoin = draftFyleJoin, let fallbackURL = URL(string: draftFyleJoin.fileName), let fyleURL = draftFyleJoin.fyle?.url else {
            linkMetatada = nil
            self.updateUI()
            return
        }
        
        if FileManager.default.fileExists(atPath: fyleURL.path),
           let data = try? Data(contentsOf: fyleURL),
           let obvEncoded = ObvEncoded(withRawData: data) {
            Task {
                guard let preview = ObvLinkMetadata.decode(obvEncoded, fallbackURL: fallbackURL) else { return }
                self.linkMetatada = preview
                self.updateUI()
            }
        }
    }
    
    private func updateUI() {
        guard let linkMetatada = linkMetatada else {
            clear()
            return
        }
        
        if let image = linkMetatada.image {
            previewImageView.image = image
            previewImageView.isHidden = false
        } else {
            previewImageView.isHidden = true
        }
        
        if let text = linkMetatada.title {
            titleLabel.text = text
            titleLabel.isHidden = false
        } else {
            titleLabel.isHidden = true
        }
        
        if let text = linkMetatada.desc {
            descLabel.text = text
            descLabel.isHidden = false
        } else {
            descLabel.isHidden = true
        }

        if let text = linkMetatada.url?.absoluteString {
            linkLabel.text = text
            linkLabel.isHidden = false
        } else {
            linkLabel.isHidden = true
        }

    }
}

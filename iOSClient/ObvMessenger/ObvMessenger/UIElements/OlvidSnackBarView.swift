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
import ObvTypes
import ObvUI
import ObvDesignSystem


final class OlvidSnackBarView: UIView {
    
    private let label = UILabel()
    private let button = UIButton(type: .system)
    private let imageView = UIImageView()
    private let backgroundEffectView = UIVisualEffectView()
    private let topLineView = UIView()
    private let bottomLineView = UIView()
    private var currentSnackBarCategory: OlvidSnackBarCategory?
    private var currentOwnedCryptoId: ObvCryptoId?
    private var contentView = UIView()
        

    func configure(with snackBarCategory: OlvidSnackBarCategory, ownedCryptoId: ObvCryptoId) {
        guard snackBarCategory != self.currentSnackBarCategory else { return }
        self.currentSnackBarCategory = snackBarCategory
        self.currentOwnedCryptoId = ownedCryptoId
        self.label.text = snackBarCategory.body
        self.button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        self.button.configuration = makeButtonConfiguration(title: snackBarCategory.buttonTitle)
        let config = UIImage.SymbolConfiguration(pointSize: 30, weight: .regular)
        let image = UIImage(systemIcon: snackBarCategory.icon, withConfiguration: config)
        self.button.maximumContentSizeCategory = .extraLarge
        imageView.image = image?.withTintColor(labelColor, renderingMode: .alwaysOriginal)
    }
    
    private let labelColor = AppTheme.shared.colorScheme.secondaryLabel
    
    @available(iOS 15, *)
    private func makeButtonConfiguration(title: String?) -> UIButton.Configuration {
        var config = UIButton.Configuration.gray()
        config.title = title
        config.buttonSize = .medium
        config.cornerStyle = .capsule
        config.image = UIImage(systemIcon: .infoCircle)
        config.imagePadding = 4.0
        return config
    }
    
    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func buttonTapped() {
        guard let ownedCryptoId = self.currentOwnedCryptoId,
              let snackBarCategory = self.currentSnackBarCategory else { return }
        ObvMessengerInternalNotification.UserWantsToSeeDetailedExplanationsOfSnackBar(ownedCryptoId: ownedCryptoId, snackBarCategory: snackBarCategory)
            .postOnDispatchQueue()
    }
    
    
    private func setupInternalViews() {
        
        addSubview(backgroundEffectView)
        backgroundEffectView.translatesAutoresizingMaskIntoConstraints = false
        backgroundEffectView.effect = UIBlurEffect(style: .regular)
                
        addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        
        contentView.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.text = "This is a test"
        label.textColor = labelColor
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true

        contentView.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(topLineView)
        topLineView.translatesAutoresizingMaskIntoConstraints = false
        topLineView.backgroundColor = .black.withAlphaComponent(0.1)

        addSubview(bottomLineView)
        bottomLineView.translatesAutoresizingMaskIntoConstraints = false
        bottomLineView.backgroundColor = .black.withAlphaComponent(0.1)

        NSLayoutConstraint.activate([
            
            topLineView.heightAnchor.constraint(equalToConstant: 1),
            topLineView.topAnchor.constraint(equalTo: self.topAnchor),
            topLineView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            topLineView.leadingAnchor.constraint(equalTo: self.leadingAnchor),

            bottomLineView.heightAnchor.constraint(equalToConstant: 1),
            bottomLineView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            bottomLineView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bottomLineView.leadingAnchor.constraint(equalTo: self.leadingAnchor),

            backgroundEffectView.topAnchor.constraint(equalTo: self.topAnchor),
            backgroundEffectView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            backgroundEffectView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            backgroundEffectView.leadingAnchor.constraint(equalTo: self.leadingAnchor),

            contentView.topAnchor.constraint(equalTo: self.topAnchor, constant: 16),
            contentView.trailingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            contentView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -25 - 8),
            contentView.leadingAnchor.constraint(equalTo: self.safeAreaLayoutGuide.leadingAnchor, constant: 16),

            imageView.trailingAnchor.constraint(equalTo: label.leadingAnchor, constant: -16),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor),

            label.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            button.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            button.lastBaselineAnchor.constraint(equalTo: label.lastBaselineAnchor),

            contentView.heightAnchor.constraint(greaterThanOrEqualTo: label.heightAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: button.heightAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: imageView.heightAnchor),

        ])
            
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        
    }
    
}

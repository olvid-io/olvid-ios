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

import SwiftUI
import UIKit
import ObvUICoreData
import ObvUIObvCircledInitials
import ObvSystemIcon
import ObvDesignSystem
import ObvSettings


// MARK: - NewCircledInitialsView
/// Square view, with a rounded clip view allowing to display either an icon, an initial (letter), or a photo.
public final class NewCircledInitialsView: UIView {
    
    private let roundedClipView = UIView()
    private let iconView = UIImageView()
    private let initialView = UILabel()
    private let pictureView = UIImageView()
    private let redShieldView = UIImageView()
    private let greenShieldView = UIImageView()

    public private(set) var currentConfiguration: CircledInitialsConfiguration?

    public override var translatesAutoresizingMaskIntoConstraints: Bool {
        didSet {
            if translatesAutoresizingMaskIntoConstraints == false {
                configureForAutolayout()
            }
        }
    }

    public func configure(with configuration: CircledInitialsConfiguration) {
        guard self.currentConfiguration != configuration else { return }
        self.currentConfiguration = configuration

        prepareForReuse()
        roundedClipView.backgroundColor = configuration.backgroundColor(appTheme: AppTheme.shared, using: ObvMessengerSettings.Interface.identityColorStyle)
        setupIconView(icon: configuration.icon, tintColor: configuration.foregroundColor(appTheme: AppTheme.shared, using: ObvMessengerSettings.Interface.identityColorStyle))

        switch configuration {
        case .contact(let initial, let photo, let showGreenShield, let showRedShield, let cryptoId, let tintAdjustmentMode):
            let textColor: UIColor

            let roundedClipViewBackgroundColor: UIColor

            switch tintAdjustmentMode {
            case .normal:
                textColor = cryptoId.colors.text

                roundedClipViewBackgroundColor = configuration.backgroundColor(appTheme: AppTheme.shared, using: ObvMessengerSettings.Interface.identityColorStyle)

            case .disabled:
                textColor = AppTheme.shared.colorScheme.secondaryLabel

                roundedClipViewBackgroundColor = AppTheme.shared.colorScheme.systemFill
            }

            setupInitialView(string: initial, textColor: textColor)
            roundedClipView.backgroundColor = roundedClipViewBackgroundColor
            setupPictureView(photo: photo)
            greenShieldView.isHidden = !showGreenShield
            redShieldView.isHidden = !showRedShield
        case .group(let photo, _):
            setupPictureView(photo: photo)
            greenShieldView.isHidden = true
            redShieldView.isHidden = true
        case .groupV2(photo: let photo, groupIdentifier: _, showGreenShield: let showGreenShield):
            setupPictureView(photo: photo)
            greenShieldView.isHidden = !showGreenShield
            redShieldView.isHidden = true
        case .icon:
            greenShieldView.isHidden = true
            redShieldView.isHidden = true
        case .photo(photo: let photo):
            setupPictureView(photo: photo)
            greenShieldView.isHidden = true
            redShieldView.isHidden = true
        }
    }


    private func prepareForReuse() {
        iconView.isHidden = true
        initialView.isHidden = true
        pictureView.isHidden = true
        redShieldView.isHidden = true
        greenShieldView.isHidden = true
        roundedClipView.backgroundColor = .clear
    }
    
    
    private func setupIconView(icon: SystemIcon?, tintColor: UIColor) {
        if let icon = icon {
            let configuration = UIImage.SymbolConfiguration(weight: .black)
            let iconImage = UIImage(systemIcon: icon, withConfiguration: configuration)
            iconView.image = iconImage
            iconView.isHidden = false
            iconView.backgroundColor = backgroundColor
            iconView.tintColor = tintColor
        } else {
            iconView.image = nil
            iconView.isHidden = true
        }
        chooseAppropriateRepresentation()
    }

    
    private func setupInitialView(string: String, textColor: UIColor) {
        initialView.isHidden = true
        guard let initial = string.trimmingCharacters(in: .whitespacesAndNewlines).first else { return }
        initialView.text = String(initial)
        initialView.isHidden = false
        initialView.textColor = textColor
        chooseAppropriateRepresentation()
    }
    
    
    private func setupPictureView(photo: CircledInitialsConfiguration.Photo?) {
        guard let photo else {
            pictureView.image = nil
            pictureView.isHidden = true
            return
        }
        let image: UIImage
        switch photo {
        case .url(let imageURL):
            guard let imageURL = imageURL else {
                pictureView.image = nil
                pictureView.isHidden = true
                return
            }
            guard FileManager.default.fileExists(atPath: imageURL.path) else {
                // This happens when we are in the middle of a group details edition.
                // The imageURL should soon be changed to a valid one.
                pictureView.image = nil
                pictureView.isHidden = true
                return
            }
            guard let data = try? Data(contentsOf: imageURL) else {
                pictureView.image = nil
                pictureView.isHidden = true
                return
            }
            guard let _image = UIImage(data: data) else {
                pictureView.image = nil
                pictureView.isHidden = true
                return
            }
            image = _image
        case .image(let _image):
            guard let _image else {
                pictureView.image = nil
                pictureView.isHidden = true
                return
            }
            image = _image
        }
        pictureView.image = image
        pictureView.isHidden = false
        chooseAppropriateRepresentation()
    }
    
    
    private func chooseAppropriateRepresentation() {
        if !pictureView.isHidden {
            iconView.isHidden = true
            initialView.isHidden = true
        } else if !initialView.isHidden {
            iconView.isHidden = true
        } else if !iconView.isHidden {
            initialView.isHidden = true
        }
    }
    
    public init() {
        super.init(frame: .zero)
        setupInternalViews()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupInternalViews() {
        
        clipsToBounds = true
        backgroundColor = .clear
        
        addSubview(roundedClipView)

        roundedClipView.backgroundColor = .red
        roundedClipView.clipsToBounds = true

        roundedClipView.addSubview(iconView)

        iconView.contentMode = .scaleAspectFit
        iconView.backgroundColor = .clear
        iconView.isHidden = true
        
        roundedClipView.addSubview(initialView)

        initialView.font = UIFont.rounded(ofSize: 30, weight: .black)
        initialView.textAlignment = .center
        initialView.isHidden = true
        
        roundedClipView.addSubview(pictureView)

        pictureView.contentMode = .scaleAspectFill
        pictureView.backgroundColor = .magenta
        pictureView.isHidden = true
        
        self.addSubview(greenShieldView)

        greenShieldView.contentMode = .scaleAspectFill
        greenShieldView.backgroundColor = .clear
        greenShieldView.image = UIImage(systemIcon: .checkmarkShieldFill, withConfiguration: nil)
        greenShieldView.tintColor = AppTheme.shared.colorScheme.green
        greenShieldView.isHidden = true

        roundedClipView.addSubview(redShieldView)

        redShieldView.contentMode = .scaleAspectFill
        redShieldView.backgroundColor = .clear
        redShieldView.image = UIImage(systemIcon: .exclamationmarkShieldFill, withConfiguration: nil)
        redShieldView.tintColor = .red
        redShieldView.isHidden = true
        
    }
    
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        configureSizes()

        if translatesAutoresizingMaskIntoConstraints {
            configureForManualLayout()
        }
    }
    
    private func configureSizes() {
        let minSize = min(bounds.width, bounds.height)
        roundedClipView.layer.cornerRadius = minSize/2
        initialView.font = UIFont.rounded(ofSize: minSize/2, weight: .black) // Heuristic
    }



    private func configureForAutolayout() {
        roundedClipView.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        initialView.translatesAutoresizingMaskIntoConstraints = false
        pictureView.translatesAutoresizingMaskIntoConstraints = false
        greenShieldView.translatesAutoresizingMaskIntoConstraints = false
        redShieldView.translatesAutoresizingMaskIntoConstraints = false

        let constraints = [

            // We constraint this view to be squared
            self.heightAnchor.constraint(equalTo: self.widthAnchor),

            // The `roundedClipView` clips other views (see the code in layoutSubviews)
            roundedClipView.topAnchor.constraint(equalTo: self.topAnchor),
            roundedClipView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            roundedClipView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            roundedClipView.leadingAnchor.constraint(equalTo: self.leadingAnchor),

            iconView.centerXAnchor.constraint(equalTo: roundedClipView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: roundedClipView.centerYAnchor),
            iconView.widthAnchor.constraint(equalTo: roundedClipView.widthAnchor, multiplier: 0.6),
            iconView.heightAnchor.constraint(equalTo: roundedClipView.heightAnchor, multiplier: 0.6),

            initialView.topAnchor.constraint(equalTo: roundedClipView.topAnchor),
            initialView.trailingAnchor.constraint(equalTo: roundedClipView.trailingAnchor),
            initialView.bottomAnchor.constraint(equalTo: roundedClipView.bottomAnchor),
            initialView.leadingAnchor.constraint(equalTo: roundedClipView.leadingAnchor),

            pictureView.topAnchor.constraint(equalTo: roundedClipView.topAnchor),
            pictureView.trailingAnchor.constraint(equalTo: roundedClipView.trailingAnchor),
            pictureView.bottomAnchor.constraint(equalTo: roundedClipView.bottomAnchor),
            pictureView.leadingAnchor.constraint(equalTo: roundedClipView.leadingAnchor),

            greenShieldView.topAnchor.constraint(equalTo: self.topAnchor),
            greenShieldView.rightAnchor.constraint(equalTo: self.rightAnchor),
            greenShieldView.heightAnchor.constraint(equalTo: greenShieldView.widthAnchor),
            greenShieldView.widthAnchor.constraint(equalTo: self.widthAnchor, multiplier: 0.3),

            redShieldView.centerXAnchor.constraint(equalTo: roundedClipView.centerXAnchor),
            redShieldView.centerYAnchor.constraint(equalTo: roundedClipView.centerYAnchor),
            redShieldView.heightAnchor.constraint(equalTo: redShieldView.widthAnchor),
            redShieldView.widthAnchor.constraint(equalTo: roundedClipView.widthAnchor, multiplier: 0.8),

        ]
        NSLayoutConstraint.activate(constraints)
    }

    private func configureForManualLayout() {
        roundedClipView.frame = bounds

        iconView.bounds.size = roundedClipView.bounds.size * 0.6

        iconView.center = .init(x: roundedClipView.frame.midX,
                                y: roundedClipView.frame.midY)

        initialView.frame = roundedClipView.frame

        pictureView.frame = roundedClipView.frame

        greenShieldView.frame = {
            let width = bounds.width * 0.3

            let horizontalOrigin = bounds.width - width

            return .init(x: horizontalOrigin,
                         y: 0,
                         width: width,
                         height: width)
        }()

        redShieldView.bounds.size = {
            let width = roundedClipView.bounds.width * 0.8

            return .init(width: width,
                         height: width)
        }()

        redShieldView.center = .init(x: roundedClipView.frame.midX,
                                     y: roundedClipView.frame.midY)
    }
}

private extension CGSize {
    static func * (lhs: Self, rhs: CGFloat) -> Self {
        return .init(width: lhs.width * rhs,
                     height: lhs.height * rhs)
    }
}

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


/// Square view, with a rounded clip view allowing to display either an icon, an initial (letter), or a photo.
final class NewCircledInitialsView: UIView {
    
    private let roundedClipView = UIView()
    private let iconView = UIImageView()
    private let initialView = UILabel()
    private let pictureView = UIImageView()
    private let redShieldView = UIImageView()
    private let greenShieldView = UIImageView()
    
    func configureWith(foregroundColor: UIColor, backgroundColor: UIColor, icon: ObvSystemIcon, stringForInitial: String?, photoURL: URL?, showGreenShield: Bool, showRedShield: Bool) {
        prepareForReuse()
        roundedClipView.backgroundColor = backgroundColor
        setupIconView(icon: icon, tintColor: foregroundColor)
        setupInitialView(string: stringForInitial, textColor: foregroundColor)
        setupPictureView(imageURL: photoURL)
        self.greenShieldView.isHidden = !showGreenShield
        self.redShieldView.isHidden = !showRedShield
    }
    
    func configureWith(icon: ObvSystemIcon) {
        prepareForReuse()
        roundedClipView.backgroundColor = appTheme.colorScheme.systemFill
        setupIconView(icon: .person, tintColor: appTheme.colorScheme.secondaryLabel)
    }
    
    private func prepareForReuse() {
        iconView.isHidden = true
        initialView.isHidden = true
        pictureView.isHidden = true
        roundedClipView.backgroundColor = .clear
    }
    
    
    private func setupIconView(icon: ObvSystemIcon, tintColor: UIColor) {
        if #available(iOS 13, *) {
            let configuration = UIImage.SymbolConfiguration(weight: .black)
            let iconImage = UIImage(systemIcon: icon, withConfiguration: configuration)
            iconView.image = iconImage
            iconView.isHidden = false
            iconView.backgroundColor = backgroundColor
            iconView.tintColor = tintColor
        } else {
            iconView.isHidden = true
        }
        chooseAppropriateRepresentation()
    }

    
    private func setupInitialView(string: String?, textColor: UIColor) {
        initialView.isHidden = true
        guard let initial = string?.trimmingCharacters(in: .whitespacesAndNewlines).first else { return }
        initialView.text = String(initial)
        initialView.isHidden = false
        initialView.textColor = textColor
        chooseAppropriateRepresentation()
    }
    
    
    private func setupPictureView(imageURL: URL?) {
        guard let imageURL = imageURL else { return }
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            // This happens when we are in the middle of a group details edition.
            // The imageURL should soon be changed to a valid one.
            return
        }
        guard let data = try? Data(contentsOf: imageURL) else { return }
        guard let image = UIImage(data: data) else { return }
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
        }
    }
    
    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    private func setupInternalViews() {
        
        clipsToBounds = true
        backgroundColor = .clear
        
        addSubview(roundedClipView)
        roundedClipView.translatesAutoresizingMaskIntoConstraints = false
        roundedClipView.backgroundColor = .red
        roundedClipView.clipsToBounds = true
        
        roundedClipView.addSubview(iconView)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.backgroundColor = .clear
        iconView.isHidden = true
        
        roundedClipView.addSubview(initialView)
        initialView.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 13, *) {
            initialView.font = UIFont.rounded(ofSize: 30, weight: .black)
        } else {
            initialView.font = UIFont.systemFont(ofSize: 30)
        }
        initialView.textAlignment = .center
        initialView.isHidden = true
        
        roundedClipView.addSubview(pictureView)
        pictureView.translatesAutoresizingMaskIntoConstraints = false
        pictureView.contentMode = .scaleAspectFill
        pictureView.backgroundColor = .magenta
        pictureView.isHidden = true
        
        self.addSubview(greenShieldView)
        greenShieldView.translatesAutoresizingMaskIntoConstraints = false
        greenShieldView.contentMode = .scaleAspectFill
        greenShieldView.backgroundColor = .clear
        if #available(iOS 13, *) {
            greenShieldView.image = UIImage(systemIcon: .checkmarkShieldFill, withConfiguration: nil)
        } else {
            // No green shield under iOS 12 or less...
        }
        greenShieldView.tintColor = appTheme.colorScheme.green
        greenShieldView.isHidden = true

        roundedClipView.addSubview(redShieldView)
        redShieldView.translatesAutoresizingMaskIntoConstraints = false
        redShieldView.contentMode = .scaleAspectFill
        redShieldView.backgroundColor = .clear
        if #available(iOS 13, *) {
            redShieldView.image = UIImage(systemIcon: .exclamationmarkShieldFill, withConfiguration: nil)
        } else {
            // No red shield under iOS 12 or less...
        }
        redShieldView.tintColor = .red
        redShieldView.isHidden = true
        
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
    
    
    override func layoutSubviews() {
        super.layoutSubviews()
        configureSizes()
    }
    
    private func configureSizes() {
        let minSize = min(bounds.width, bounds.height)
        roundedClipView.layer.cornerRadius = minSize/2
        if #available(iOS 13, *) {
            initialView.font = UIFont.rounded(ofSize: minSize/2, weight: .black) // Heuristic
        } else {
            initialView.font = UIFont.systemFont(ofSize: minSize/2)
        }
    }
}

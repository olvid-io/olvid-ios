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


// MARK: - CircledInitialsIcon
enum CircledInitialsIcon: Hashable {
    case lockFill
    case person
    case person3Fill
    case personFillXmark

    var icon: ObvSystemIcon {
        switch self {
        case .lockFill: return .lock(.fill)
        case .person: return .person
        case .person3Fill: return .person3Fill
        case .personFillXmark: return .personFillXmark
        }
    }
}


// MARK: - CircledInitialsConfiguration
enum CircledInitialsConfiguration: Hashable {
    enum ContentType {
        case none
        case icon(ObvSystemIcon, UIColor)
        case initial(String, UIColor)
        case picture(UIImage)
    }
    
    case contact(initial: String, photoURL: URL?, showGreenShield: Bool, showRedShield: Bool, colors: (background: UIColor, text: UIColor))
    case group(photoURL: URL?, colors: (background: UIColor, text: UIColor))
    case icon(_ icon: CircledInitialsIcon)

    func hash(into hasher: inout Hasher) {
        switch self {
        case .contact(initial: let initial, photoURL: let photoURL, showGreenShield: let showGreenShield, showRedShield: let showRedShield, colors: let colors):
            hasher.combine(initial)
            hasher.combine(photoURL)
            hasher.combine(showGreenShield)
            hasher.combine(showRedShield)
            hasher.combine(colors.text)
            hasher.combine(colors.background)
        case .group(photoURL: let photoURL, colors: let colors):
            hasher.combine(photoURL)
            hasher.combine(colors.text)
            hasher.combine(colors.background)
        case .icon(icon: let icon):
            hasher.combine(icon)
        }
    }

    static func == (lhs: CircledInitialsConfiguration, rhs: CircledInitialsConfiguration) -> Bool {
        lhs.hashValue == rhs.hashValue
    }

    func backgroundColor(appTheme: AppTheme) -> UIColor {
        switch self {
        case .contact(_, _, _, _, let colors), .group(_, let colors):
            return colors.background
        case .icon:
            return appTheme.colorScheme.systemFill
        }
    }

    func foregroundColor(appTheme: AppTheme) -> UIColor {
        switch self {
        case .contact(_, _, _, _, let colors), .group(_, let colors):
            return colors.text
        case .icon:
            return appTheme.colorScheme.secondaryLabel
        }
    }

    var icon: ObvSystemIcon? {
        switch self {
        case .contact: return nil
        case .group: return .person3Fill
        case .icon(let icon): return icon.icon
        }
    }

    var photo: UIImage? {
        let url: URL?
        switch self {
        case .contact(initial: _, photoURL: let photoURL, showGreenShield: _, showRedShield: _, colors: _):
            url = photoURL
        case .group(photoURL: let photoURL, colors: _):
            url = photoURL
        case .icon:
            url = nil
        }
        guard let url = url else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    
    fileprivate var contentType: ContentType {
        if let image = self.photo {
            return .picture(image)
        } else if let initials = self.initials {
            return .initial(initials.text, initials.color)
        } else if let iconInfo = self.iconInfo {
            return .icon(iconInfo.icon, iconInfo.tintColor)
        } else {
            return .none
        }
    }
    
    var showGreenShield: Bool {
        switch self {
        case .contact(initial: _, photoURL: _, showGreenShield: let showGreenShield, showRedShield: _, colors: _): return showGreenShield
        default: return false
        }
    }
    
    var showRedShield: Bool {
        switch self {
        case .contact(initial: _, photoURL: _, showGreenShield: _, showRedShield: let showRedShield, colors: _): return showRedShield
        default: return false
        }
    }
    
    fileprivate var initials: (text: String, color: UIColor)? {
        switch self {
        case .contact(initial: let initial, photoURL: _, showGreenShield: _, showRedShield: _, colors: let colors):
            guard let str = initial.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
            return (String(str), colors.text)
        default: return nil
        }
    }
    
    fileprivate var iconInfo: (icon: ObvSystemIcon, tintColor: UIColor)? {
        guard let icon else { return nil }
        return (icon, foregroundColor(appTheme: AppTheme.shared))
    }
}


// MARK: - NewCircledInitialsView
/// Square view, with a rounded clip view allowing to display either an icon, an initial (letter), or a photo.
final class NewCircledInitialsView: UIView {
    
    private let roundedClipView = UIView()
    private let iconView = UIImageView()
    private let initialView = UILabel()
    private let pictureView = UIImageView()
    private let redShieldView = UIImageView()
    private let greenShieldView = UIImageView()

    private var currentConfiguration: CircledInitialsConfiguration?

    func configureWith(_ configuration: CircledInitialsConfiguration) {
        guard self.currentConfiguration != configuration else { return }
        self.currentConfiguration = configuration

        prepareForReuse()
        roundedClipView.backgroundColor = configuration.backgroundColor(appTheme: appTheme)
        setupIconView(icon: configuration.icon, tintColor: configuration.foregroundColor(appTheme: appTheme))

        switch configuration {
        case .contact(let initial, let photoURL, let showGreenShield, let showRedShield, let colors):
            setupInitialView(string: initial, textColor: colors.text)
            setupPictureView(imageURL: photoURL)
            greenShieldView.isHidden = !showGreenShield
            redShieldView.isHidden = !showRedShield
        case .group(let photoURL, _):
            setupPictureView(imageURL: photoURL)
            greenShieldView.isHidden = true
            redShieldView.isHidden = true
        case .icon:
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
    
    
    private func setupIconView(icon: ObvSystemIcon?, tintColor: UIColor) {
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
    
    
    private func setupPictureView(imageURL: URL?) {
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
        guard let image = UIImage(data: data) else {
            pictureView.image = nil
            pictureView.isHidden = true
            return
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
        initialView.font = UIFont.rounded(ofSize: 30, weight: .black)
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
        greenShieldView.image = UIImage(systemIcon: .checkmarkShieldFill, withConfiguration: nil)
        greenShieldView.tintColor = appTheme.colorScheme.green
        greenShieldView.isHidden = true

        roundedClipView.addSubview(redShieldView)
        redShieldView.translatesAutoresizingMaskIntoConstraints = false
        redShieldView.contentMode = .scaleAspectFill
        redShieldView.backgroundColor = .clear
        redShieldView.image = UIImage(systemIcon: .exclamationmarkShieldFill, withConfiguration: nil)
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
        initialView.font = UIFont.rounded(ofSize: minSize/2, weight: .black) // Heuristic
    }
}


// MARK: - SwiftUINewCircledInitialsView
@available(iOS 16.0, *)
struct SwiftUINewCircledInitialsView: View {

    let configuration: CircledInitialsConfiguration

    var body: some View {
        RoundedClipView(configuration: configuration)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: configuration.backgroundColor(appTheme: AppTheme.shared)))
            .clipShape(Circle())
    }
}


// MARK: - RoundedClipView
@available(iOS 16.0, *)
fileprivate struct RoundedClipView: View {

    let configuration: CircledInitialsConfiguration

    var body: some View {
        switch configuration.contentType {
        case .icon(let icon, let color): return AnyView(createIconView(using: icon, color: color))
        case .initial(let text, let color): return AnyView(createInitialView(using: text, color: color))
        case .picture(let image): return AnyView(createPictureView(using: image))
        case .none: return AnyView(Text(""))
        }
    }
    
    private func createIconView(using icon: ObvSystemIcon, color: UIColor) -> some View {
        return Image(systemIcon: icon)
            .font(.system(size: 16, weight: .black))
            .foregroundColor(Color(uiColor: color))
    }
    
    private func createInitialView(using initials: String, color: UIColor) -> some View {
        return Text(initials)
            .font(.system(size: 30, weight: .black, design: .rounded))
            .foregroundColor(Color(uiColor: color))
            .multilineTextAlignment(.center)
    }
    
    private func createPictureView(using uiImage: UIImage) -> some View {
        return Image(uiImage: uiImage)
            .resizable()
            .scaledToFit()
    }
}

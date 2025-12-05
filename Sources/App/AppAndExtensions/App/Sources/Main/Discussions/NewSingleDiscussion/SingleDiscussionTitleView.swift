/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import QuickLookThumbnailing
import ObvTypes
import ObvUICoreData
import ObvUI
import ObvUIObvCircledInitials


// MARK: - Creating a custom discussion title view on iOS 26

extension NewSingleDiscussionViewController.SingleDiscussionTitleViewConfiguration {
    
    /// Creates a configuration for a locked discussion.
    ///
    /// Uses the provided title and subtitle and renders a lock icon as the avatar.
    /// - Parameters:
    ///   - title: The primary text to display.
    ///   - subtitle: The secondary text shown beneath the title.
    /// - Returns: A configuration ready to render the title view.
    static func forLockedDiscussion(title: String, subtitle: String) -> Self {
        return .init(title: title,
                     subtitle: subtitle,
                     circledInitialsConfiguration: .icon(.lockFill))
    }
    
    /// Builds a configuration for a one-to-one discussion.
    ///
    /// Uses the contact’s display name as the title, the position/company
    /// (if available) as the subtitle, and the contact’s circled initials
    /// as the avatar configuration.
    /// - Parameter contact: The contact identity used to derive display info.
    /// - Returns: A configuration ready to render the title view.
    static func forOneToOneDiscussion(contact: PersistedObvContactIdentity) -> Self {
        return .init(title: contact.customOrNormalDisplayName,
                     subtitle: contact.identityCoreDetails?.positionAtCompany() ?? "",
                     circledInitialsConfiguration: contact.circledInitialsConfiguration)
    }
    
    /// Creates a configuration for a legacy (v1) group discussion.
    ///
    /// Uses the group's discussion title as the title and a short, localized list
    /// of member display names as the subtitle. The group's circled initials configuration
    /// is used for the avatar.
    /// - Parameter group: The v1 group used to derive display information.
    /// - Returns: A configuration ready to render the title view.
    static func forGroupV1(group: PersistedContactGroup) -> Self {

        let names = group.contactIdentities
            .sorted { $0.customOrShortDisplayName < $1.customOrShortDisplayName }
            .compactMap({ $0.customOrShortDisplayName })
        let subtitle = names.formatted(.list(type: .and, width: .short))

        return .init(title: group.discussion.title,
                     subtitle: subtitle,
                     circledInitialsConfiguration: group.circledInitialsConfiguration)
        
    }
    
    /// Creates a configuration for a v2 group discussion.
    ///
    /// Uses the group's `displayName` as the title and a short, localized list
    /// of other members' display names as the subtitle. The group's circled initials
    /// configuration is used for the avatar.
    /// - Parameter group: The v2 group used to derive display information.
    /// - Returns: A configuration ready to render the title view.
    static func forGroupV2(group: PersistedGroupV2) -> Self {
        
        let names = group.otherMembersSorted
            .sorted { ($0.displayedCustomDisplayNameOrFirstNameOrLastName ?? "") < ($1.displayedCustomDisplayNameOrFirstNameOrLastName ?? "") }
            .compactMap({ $0.displayedCustomDisplayNameOrFirstNameOrLastName })
        let subtitle = names.formatted(.list(type: .and, width: .short))

        return .init(title: group.displayName,
                     subtitle: subtitle,
                     circledInitialsConfiguration: group.circledInitialsConfiguration)
        
    }
    
}


extension NewSingleDiscussionViewController {
    
    
    /// Configuration model for building the single discussion title view.
    ///
    /// Holds the title and subtitle text along with the visual configuration
    /// for the avatar/circled initials displayed in the view.
    ///
    /// Use this configuration with `makeSingleDiscussionTitleView(configuration:)`
    /// to build the navigation title view of a `NewSingleDiscussionViewController`.
    struct SingleDiscussionTitleViewConfiguration {
        let title: String
        let subtitle: String
        let circledInitialsConfiguration: CircledInitialsConfiguration
    }
        
    
    /// Builds a glass-effect wrapper containing the avatar and labels.
    ///
    /// Creates a UIVisualEffectView configured with an interactive glass effect
    /// and a capsule corner style, then embeds the avatar-and-labels stack with
    /// appropriate insets.
    /// - Parameter configuration: The content configuration used to populate the stack.
    /// - Returns: A UIView (UIVisualEffectView) that renders the glass background.
    @available(iOS 26.0, *)
    func makeSingleDiscussionTitleView(configuration: SingleDiscussionTitleViewConfiguration) -> UIView {
        
        let effectView = UIVisualEffectView()
        effectView.translatesAutoresizingMaskIntoConstraints = false
        let glassEffect = UIGlassEffect()
        glassEffect.isInteractive = true
        UIView.animate {
            effectView.effect = glassEffect
            effectView.cornerConfiguration = .capsule()
        }
        
        let stack = makeStackOfAvatarAndLabels(configuration: configuration)
        stack.translatesAutoresizingMaskIntoConstraints = false
                
        effectView.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: effectView.contentView.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor, constant: -6),
        ])
        
        return effectView
        
    }
    
    
    /// Creates a horizontal stack with the avatar and the labels stack.
    ///
    /// Builds a centered horizontal UIStackView containing a fixed-size
    /// `NewCircledInitialsView` followed by a vertical stack of title and
    /// subtitle labels.
    /// - Parameter configuration: Provides the avatar configuration and label texts.
    /// - Returns: A configured horizontal UIStackView.
    @available(iOS 26.0, *)
    func makeStackOfAvatarAndLabels(configuration: SingleDiscussionTitleViewConfiguration) -> UIView {
        
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center

        let circledInitialsView = NewCircledInitialsView()
        circledInitialsView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            circledInitialsView.widthAnchor.constraint(equalToConstant: 32),
            circledInitialsView.heightAnchor.constraint(equalToConstant: 32),
        ])
        stackView.addArrangedSubview(circledInitialsView)
        circledInitialsView.configure(with: configuration.circledInitialsConfiguration)
        
        stackView.addArrangedSubview(makeStackOfLabels(title: configuration.title, subtitle: configuration.subtitle))
        
        return stackView
    }
    
    
    /// Builds a vertical stack of title and subtitle labels.
    ///
    /// Creates two UILabels with appropriate fonts and colors, arranged in a
    /// vertical UIStackView.
    /// - Parameters:
    ///   - title: The primary text to display.
    ///   - subtitle: The secondary text shown beneath the title.
    /// - Returns: A vertical UIStackView containing the two labels.
    @available(iOS 26.0, *)
    private func makeStackOfLabels(title: String, subtitle: String) -> UIView {
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        
        let titleLabel = UILabel()
        stackView.addArrangedSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        titleLabel.text = title
        titleLabel.textAlignment = .left
        
        let subtitleLabel = UILabel()
        stackView.addArrangedSubview(subtitleLabel)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .semibold)
        subtitleLabel.text = subtitle
        subtitleLabel.textAlignment = .left
        subtitleLabel.textColor = .secondaryLabel
        
        return stackView
        
    }
    
}



// MARK: - Legacy title view

/// Legacy title view used prior to iOS 26.
/// - Warning: Deprecated on iOS 26 and later. Use `NewSingleDiscussionViewController.makeSingleDiscussionTitleView(configuration:)`.
@available(iOS, deprecated: 26.0, message: "Use NewSingleDiscussionViewController.makeSingleDiscussionTitleView(configuration:) on iOS 26+.")
final class SingleDiscussionTitleView: UIView {
    
    public let title: String
    private let subtitle: String
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let viewForLabels = UIView()
    private let circledInitialsView = NewCircledInitialsView()
    
    init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
        super.init(frame: .zero)
        setupInternalViews()
        circledInitialsView.configure(with: .icon(.lockFill))
        configureAccessibility()
    }

    
    convenience init(objectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>) {
        assert(Thread.isMainThread)
        guard let contact = try? PersistedObvContactIdentity.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            self.init(title: "", subtitle: "")
            circledInitialsView.configure(with: .icon(.person))
            return
        }
        self.init(title: contact.customOrNormalDisplayName,
                  subtitle: contact.identityCoreDetails?.positionAtCompany() ?? "")
        circledInitialsView.configure(with: contact.circledInitialsConfiguration)
    }
    
    convenience init(objectID: TypeSafeManagedObjectID<PersistedContactGroup>) {
        assert(Thread.isMainThread)
        guard let group = try? PersistedContactGroup.get(objectID: objectID.objectID, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            self.init(title: "", subtitle: "")
            circledInitialsView.configure(with: .icon(.person3Fill))
            return
        }
        let title = group.discussion.title
                
        let subtitle: String
        let names = group.contactIdentities
            .sorted { $0.customOrShortDisplayName < $1.customOrShortDisplayName }
            .compactMap({ $0.customOrShortDisplayName })
        subtitle = names.formatted(.list(type: .and, width: .short))

        self.init(title: title,
                  subtitle: subtitle)
        circledInitialsView.configure(with: group.circledInitialsConfiguration)
    }
    
    convenience init(objectID: TypeSafeManagedObjectID<PersistedGroupV2>) {
        assert(Thread.isMainThread)
        guard let group = try? PersistedGroupV2.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            self.init(title: "", subtitle: "")
            circledInitialsView.configure(with: .icon(.person3Fill))
            return
        }
        let title = group.displayName
        let subtitle = group.otherMembersSorted.compactMap({ $0.displayedCustomDisplayNameOrFirstNameOrLastName }).joined(separator: ", ")
        self.init(title: title,
                  subtitle: subtitle)
        circledInitialsView.configure(with: group.circledInitialsConfiguration)
    }

    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    private let paddingForInitialsView = CGFloat(2)
    
    private func setupInternalViews() {
                
        addSubview(circledInitialsView)
        circledInitialsView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(viewForLabels)
        viewForLabels.translatesAutoresizingMaskIntoConstraints = false
        
        viewForLabels.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.text = title
        titleLabel.textAlignment = .left
        
        viewForLabels.addSubview(subtitleLabel)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        subtitleLabel.text = subtitle
        subtitleLabel.textAlignment = .left
        subtitleLabel.textColor = .secondaryLabel

        let constraintsForLabels = [
            titleLabel.topAnchor.constraint(equalTo: viewForLabels.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: subtitleLabel.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: viewForLabels.leadingAnchor),
            
            subtitleLabel.bottomAnchor.constraint(equalTo: viewForLabels.bottomAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: viewForLabels.leadingAnchor),
            
            viewForLabels.widthAnchor.constraint(greaterThanOrEqualTo: titleLabel.widthAnchor),
            viewForLabels.widthAnchor.constraint(greaterThanOrEqualTo: subtitleLabel.widthAnchor),
        ]
        NSLayoutConstraint.activate(constraintsForLabels)
        
        let constraints = [

            circledInitialsView.topAnchor.constraint(equalTo: self.topAnchor, constant: paddingForInitialsView),
            circledInitialsView.trailingAnchor.constraint(equalTo: titleLabel.leadingAnchor, constant: -6.0-paddingForInitialsView),
            circledInitialsView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -paddingForInitialsView),
            circledInitialsView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: paddingForInitialsView),

            viewForLabels.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            viewForLabels.centerYAnchor.constraint(equalTo: circledInitialsView.centerYAnchor),

        ]
        NSLayoutConstraint.activate(constraints)
        
        let spacerWidthConstraint = viewForLabels.widthAnchor.constraint(equalToConstant: max(UIScreen.main.bounds.width, UIScreen.main.bounds.height))
        spacerWidthConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([spacerWidthConstraint])
        
        let circledInitialsViewHeightConstraint: NSLayoutConstraint
        if #available(iOS 26, *) {
            circledInitialsViewHeightConstraint = circledInitialsView.heightAnchor.constraint(equalToConstant: 40)
        } else {
            circledInitialsViewHeightConstraint = circledInitialsView.heightAnchor.constraint(equalToConstant: 1_000) // Something large
            circledInitialsViewHeightConstraint.priority = .defaultHigh+1
        }
        NSLayoutConstraint.activate([circledInitialsViewHeightConstraint])

    }
    
    private func configureAccessibility() {
        self.isAccessibilityElement = true
        self.accessibilityElements = []
        self.accessibilityLabel = "\(title), \(subtitle)"
    }

}


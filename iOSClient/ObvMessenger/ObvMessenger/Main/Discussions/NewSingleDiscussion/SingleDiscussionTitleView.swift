/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


@available(iOS 13.0, *)
final class SingleDiscussionTitleView: UIView {
    
    private let title: String
    private let subtitle: String
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let spacer = UIView()
    private let viewForLabels = UIView()
    private let circledInitialsView = NewCircledInitialsView()
    
    init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
        super.init(frame: .zero)
        setupInternalViews()
    }
    

    convenience init(objectID: TypeSafeManagedObjectID<PersistedDiscussionGroupLocked>) {
        assert(Thread.isMainThread)
        self.init(lockedDiscussionObjectID: objectID.downcast)
    }
    
    
    convenience init(objectID: TypeSafeManagedObjectID<PersistedDiscussionOneToOneLocked>) {
        assert(Thread.isMainThread)
        self.init(lockedDiscussionObjectID: objectID.downcast)
    }

    
    /// Used exclusively for locked discussions
    private convenience init(lockedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) {
        assert(Thread.isMainThread)
        guard let discussion = try? PersistedDiscussion.get(objectID: lockedDiscussionObjectID, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            self.init(title: "", subtitle: "")
            circledInitialsView.configureWith(icon: .person)
            return
        }
        self.init(title: discussion.title,
                  subtitle: discussion.subtitle)
        circledInitialsView.configureWith(foregroundColor: AppTheme.shared.colorScheme.secondaryLabel,
                                          backgroundColor: AppTheme.shared.colorScheme.secondarySystemFill,
                                          icon: .lockFill,
                                          stringForInitial: nil,
                                          photoURL: nil,
                                          showGreenShield: false,
                                          showRedShield: false)
    }

    
    convenience init(objectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>) {
        assert(Thread.isMainThread)
        guard let contact = try? PersistedObvContactIdentity.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            self.init(title: "", subtitle: "")
            circledInitialsView.configureWith(icon: .person)
            return
        }
        self.init(title: contact.customOrNormalDisplayName,
                  subtitle: contact.identityCoreDetails.positionAtCompany())
        circledInitialsView.configureWith(foregroundColor: contact.cryptoId.textColor,
                                          backgroundColor: contact.cryptoId.colors.background,
                                          icon: .person,
                                          stringForInitial: contact.customOrFullDisplayName,
                                          photoURL: contact.customPhotoURL ?? contact.photoURL,
                                          showGreenShield: contact.isCertifiedByOwnKeycloak,
                                          showRedShield: !contact.isActive)
    }
    
    convenience init(objectID: TypeSafeManagedObjectID<PersistedContactGroup>) {
        assert(Thread.isMainThread)
        guard let group = try? PersistedContactGroup.get(objectID: objectID.objectID, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            self.init(title: "", subtitle: "")
            circledInitialsView.configureWith(icon: .person3Fill)
            return
        }
        let title = group.discussion.title
        let subtitle = group.contactIdentities.compactMap({ $0.customOrNormalDisplayName }).joined(separator: ", ")
        self.init(title: title,
                  subtitle: subtitle)
        let colors = AppTheme.shared.groupColors(forGroupUid: group.groupUid)
        circledInitialsView.configureWith(foregroundColor: colors.text,
                                          backgroundColor: colors.background,
                                          icon: .person3Fill,
                                          stringForInitial: nil,
                                          photoURL: group.displayPhotoURL,
                                          showGreenShield: false,
                                          showRedShield: false)
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
        
        let circledInitialsViewHeightConstraint = circledInitialsView.heightAnchor.constraint(equalToConstant: 1_000) // Something large
        circledInitialsViewHeightConstraint.priority = .defaultHigh+1
        NSLayoutConstraint.activate([circledInitialsViewHeightConstraint])
        
    }

}

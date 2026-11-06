/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvTypes
import ObvDesignSystem
import ObvSystemIcon


/// The content of one card: who the person is, and why they are suggested.
///
/// The person is at the top, with what brought them here — an invitation, an introduction — on the edge of their picture; under their name, the groups
/// we share. The swipe, the stacking and the green and red fills belong to ``ContactsSuggestionsView``; this view only draws a person.
struct SuggestionCardView: View {

    /// `nil` while the model loads, in which case a placeholder is drawn redacted.
    let model: ContactSuggestion.Model?
    let avatarViewDataSource: ObvAvatarViewDataSource
    let userWantsToSeeDetails: (ObvContactIdentifier) -> Void

    @ScaledMetric(relativeTo: .title) private var avatarDiameter: CGFloat = 156

    private var shownModel: ContactSuggestion.Model {
        model ?? .placeholder
    }

    var body: some View {
        VStack(spacing: 0) {
            avatarWithBadge
            VStack(spacing: 4) {
                Text(verbatim: shownModel.name)
                    .font(.title3)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let positionAtCompany = shownModel.positionAtCompany {
                    Text(verbatim: positionAtCompany)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Clear of the badge, which sits across the lower edge of the picture.
            .padding(.top, 20)
            if let commonGroups = shownModel.commonGroups {
                CommonGroupsSummary(commonGroups: commonGroups, avatarViewDataSource: avatarViewDataSource)
                    .padding(.top, 24)
            }
            Spacer(minLength: 16)
            if let contactForDetails = shownModel.contactForDetails {
                // Bordered rather than glass: the onboarding draws this card scaled and tilted, and glass, drawn from what is under it, does not
                // follow the card.
                Button {
                    userWantsToSeeDetails(contactForDetails)
                } label: {
                    Text("MORE_INFO")
                        .foregroundStyle(Color(uiColor: .label))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(Color(uiColor: .systemGray))
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 48)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .redacted(reason: model == nil ? .placeholder : [])
    }


    private var avatarWithBadge: some View {
        ObvAvatarView(model: shownModel.avatar,
                      style: .circle,
                      size: .custom(frameSize: .init(width: avatarDiameter, height: avatarDiameter)),
                      dataSource: avatarViewDataSource)
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
            }
            .avatarShadow()
            .overlay(alignment: .bottom) {
                switch shownModel.badge {
                case .none:
                    EmptyView()
                case .invitationReceived:
                    BadgeCapsule(text: String(localizedInThisBundle: "INVITATION_RECEIVED"))
                        .alignmentGuide(.bottom) { $0[VerticalAlignment.center] }
                case .introducedBy(let mediatorName):
                    BadgeCapsule(text: String(localizedInThisBundle: "INTRODUCED_BY_\(mediatorName)"))
                        .alignmentGuide(.bottom) { $0[VerticalAlignment.center] }
                case .invitationSent:
                    // Grey: nothing to answer, only a reminder of what the user did.
                    BadgeCapsule(text: String(localizedInThisBundle: "INVITATION_SENT"), color: Color(uiColor: .systemGray))
                        .alignmentGuide(.bottom) { $0[VerticalAlignment.center] }
                }
            }
    }

}


// MARK: - Subviews

private struct BadgeCapsule: View {

    let text: String
    var color = Color.blue

    var body: some View {
        Text(verbatim: text)
            .font(.subheadline)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(color, in: Capsule())
    }

}


/// The pictures of at most three of the groups in common, overlapping, the last one covered by how many more there are; and under them the name of
/// the first group and how many others there are.
private struct CommonGroupsSummary: View {

    let commonGroups: ContactSuggestion.Model.CommonGroups
    let avatarViewDataSource: ObvAvatarViewDataSource

    // The pictures keep their size whatever the text size: only the text grows.
    private static let groupDiameter: CGFloat = 44
    /// How much each picture covers the one before it.
    private static let overlap: CGFloat = 14
    /// The ring of the card's own colour around each picture, which separates it from the one it covers.
    private static let ringWidth: CGFloat = 1.5
    private static let maximumNumberOfPictures = 3

    private var text: String {
        let otherGroups = commonGroups.numberOfGroups - 1
        if otherGroups > 0 {
            // The plural takes one number only, so it is translated on its own and then placed after the group's name.
            let andOtherGroups = String(localizedInThisBundle: "AND_\(otherGroups)_OTHER_GROUPS_IN_COMMON")
            return String(localizedInThisBundle: "GROUP_\(commonGroups.nameOfFirstGroup)_FOLLOWED_BY_\(andOtherGroups)")
        } else {
            return String(localizedInThisBundle: "GROUP_\(commonGroups.nameOfFirstGroup)_IN_COMMON")
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            let pictures = Array(commonGroups.pictures.prefix(Self.maximumNumberOfPictures))
            // Counted from the number of groups rather than from the pictures, a group without one being a group all the same.
            let numberOfGroupsNotShown = commonGroups.numberOfGroups - pictures.count
            if !pictures.isEmpty {
                // Each picture over the one before it, so that the last, which carries the count of the others, is never covered.
                HStack(spacing: -Self.overlap) {
                    ForEach(pictures) { picture in
                        ObvAvatarView(model: picture.avatar,
                                      style: .circle,
                                      size: .custom(frameSize: .init(width: Self.groupDiameter, height: Self.groupDiameter)),
                                      dataSource: avatarViewDataSource)
                            .overlay {
                                if picture.id == pictures.last?.id && numberOfGroupsNotShown > 0 {
                                    MoreGroups(number: numberOfGroupsNotShown)
                                }
                            }
                            .padding(Self.ringWidth)
                            .background(Color(uiColor: .tertiarySystemBackground), in: Circle())
                    }
                }
                // The text under it says how many groups there are.
                .accessibilityHidden(true)
            }
            Text(verbatim: text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

}


/// How many groups are not shown, over the last picture shown: the picture darkened, and the number on it.
private struct MoreGroups: View {

    let number: Int

    var body: some View {
        // Of a fixed size, as the circle it is drawn in is: the number repeats what the text under the pictures says, so not scaling it withholds
        // nothing.
        Text(verbatim: "+" + number.formatted())
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.55), in: Circle())
    }

}


// MARK: - Shadow

extension View {

    /// A shadow barely there, so that a circle stays a circle when its picture is as pale as the card around it.
    func avatarShadow() -> some View {
        shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }

}


// MARK: - Placeholder

private extension ContactSuggestion.Model {

    /// Drawn redacted while the real model loads, so the card keeps its shape.
    static let placeholder = ContactSuggestion.Model(
        avatar: .init(characterOrIcon: .icon(.person), colors: .init(foreground: .secondaryLabel, background: .systemFill), photoURL: nil),
        name: "Firstname Lastname",
        positionAtCompany: "Position @ Company",
        badge: .none,
        commonGroups: nil,
        contactForDetails: nil)

}

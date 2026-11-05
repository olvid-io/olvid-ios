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
import ObvDesignSystem
import ObvSystemIcon


/// Where the people suggested come from, as the second state of the onboarding shows it: the user at the top, a dashed line down to a node standing for
/// a group in common, which branches out to the pictures of people suggested. The first of them is in the middle and larger, at most one more on each
/// side of it, and two more fading out beyond.
struct RelationshipTreeView: View {

    /// The user's own picture, or `nil` while it loads.
    let ownedAvatar: ObvAvatarViewModel?
    /// At most five people suggested, the first in the middle.
    let suggestedAvatars: [ObvAvatarViewModel]
    let avatarViewDataSource: ObvAvatarViewDataSource

    // The diagram is a picture, so it keeps its size whatever the text size: only its labels grow.
    private static let ownedDiameter: CGFloat = 72
    private static let nodeDiameter: CGFloat = 56
    private static let centralDiameter: CGFloat = 76
    /// Either side of the person in the middle, and fading out beyond: smaller, so the one in the middle stands out.
    private static let sideDiameter: CGFloat = 58
    /// Two people with nothing between them.
    private static let pairedDiameter: CGFloat = 66
    private static let spaceBetweenPeople: CGFloat = 12
    private static let heightOfTheLineFromTheUser: CGFloat = 64
    private static let heightOfTheBranches: CGFloat = 64
    /// Barely there: they only say that the list goes on.
    private static let fadedOpacity: Double = 0.15

    /// The horizontal distance from the middle to the centre of a person either side of it.
    private static let sideOffset = centralDiameter / 2 + spaceBetweenPeople + sideDiameter / 2
    /// The horizontal distance from the middle to the centre of a person fading out on a side.
    private static let fadedOffset = sideOffset + sideDiameter + spaceBetweenPeople
    /// With two people and nothing in the middle, they come closer to it: what separates them is the same space as between any two.
    private static let pairedOffset = pairedDiameter / 2 + spaceBetweenPeople
    /// How far from the middle of the label a branch towards a side starts, on that side; further out beside a middle branch, so the three do not crowd
    /// the middle of the label. The branch to the middle starts in the middle.
    private static let branchStartOffset: CGFloat = 20
    private static let branchStartOffsetBesideAMiddleBranch: CGFloat = 36

    private struct Slot: Identifiable {
        let id: Int
        let avatar: ObvAvatarViewModel
        let offset: CGFloat
        let diameter: CGFloat
        let isFaded: Bool
    }

    private var slots: [Slot] {
        let avatars = suggestedAvatars
        var slots = [Slot]()
        switch min(avatars.count, 3) {
        case 1:
            slots.append(.init(id: 0, avatar: avatars[0], offset: 0, diameter: Self.centralDiameter, isFaded: false))
        case 2:
            slots.append(.init(id: 0, avatar: avatars[0], offset: -Self.pairedOffset, diameter: Self.pairedDiameter, isFaded: false))
            slots.append(.init(id: 1, avatar: avatars[1], offset: Self.pairedOffset, diameter: Self.pairedDiameter, isFaded: false))
        case 3:
            slots.append(.init(id: 1, avatar: avatars[1], offset: -Self.sideOffset, diameter: Self.sideDiameter, isFaded: false))
            slots.append(.init(id: 0, avatar: avatars[0], offset: 0, diameter: Self.centralDiameter, isFaded: false))
            slots.append(.init(id: 2, avatar: avatars[2], offset: Self.sideOffset, diameter: Self.sideDiameter, isFaded: false))
        default:
            break
        }
        if avatars.count > 3 {
            slots.append(.init(id: 3, avatar: avatars[3], offset: -Self.fadedOffset, diameter: Self.sideDiameter, isFaded: true))
        }
        if avatars.count > 4 {
            slots.append(.init(id: 4, avatar: avatars[4], offset: Self.fadedOffset, diameter: Self.sideDiameter, isFaded: true))
        }
        return slots
    }

    var body: some View {
        let slots = self.slots
        VStack(spacing: 0) {
            LabelledCircle(label: String(localizedInThisBundle: "YOU")) {
                if let ownedAvatar {
                    ObvAvatarView(model: ownedAvatar,
                                  style: .circle,
                                  size: .custom(frameSize: .init(width: Self.ownedDiameter, height: Self.ownedDiameter)),
                                  dataSource: avatarViewDataSource)
                        .overlay {
                            Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
                        }
                        .avatarShadow()
                } else {
                    Circle()
                        .fill(Color(uiColor: .systemFill))
                        .frame(width: Self.ownedDiameter, height: Self.ownedDiameter)
                }
            }
            DashedLines(segments: [.init(start: 0, end: 0)])
                .frame(width: 1, height: Self.heightOfTheLineFromTheUser)
            LabelledCircle(label: String(localizedInThisBundle: "GROUP_IN_COMMON")) {
                Image(systemIcon: .person2Fill)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.commonGroupsNode)
                    .frame(width: Self.nodeDiameter, height: Self.nodeDiameter)
                    .background(Color(uiColor: .secondarySystemBackground), in: Circle())
                    .overlay {
                        Circle().strokeBorder(Color.commonGroupsNode, lineWidth: 1.5)
                    }
            }
            DashedLines(segments: Self.branches(to: slots.filter({ !$0.isFaded })))
                .frame(height: Self.heightOfTheBranches)
            ZStack {
                ForEach(slots) { slot in
                    ObvAvatarView(model: slot.avatar,
                                  style: .circle,
                                  size: .custom(frameSize: .init(width: slot.diameter, height: slot.diameter)),
                                  dataSource: avatarViewDataSource)
                        .overlay {
                            if slot.offset == 0 {
                                Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
                            }
                        }
                        .avatarShadow()
                        .opacity(slot.isFaded ? Self.fadedOpacity : 1)
                        .offset(x: slot.offset)
                }
            }
            .frame(height: Self.centralDiameter)
            .frame(maxWidth: .infinity)
            Text(verbatim: String(localizedInThisBundle: "ONBOARDING_ORIGIN_RELATION"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 32)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: String(localizedInThisBundle: "ONBOARDING_ORIGIN_RELATION")))
    }

    /// The branches from the label to the people shown plainly: each starts a little off the middle of the label, towards its person, unless the person
    /// is in the middle.
    private static func branches(to slots: [Slot]) -> [DashedLines.Segment] {
        let thereIsAMiddleBranch = slots.contains(where: { $0.offset == 0 })
        let startOffset = thereIsAMiddleBranch ? branchStartOffsetBesideAMiddleBranch : branchStartOffset
        return slots.map { slot in
            let side: CGFloat = slot.offset == 0 ? 0 : (slot.offset < 0 ? -1 : 1)
            return .init(start: side * startOffset, end: slot.offset)
        }
    }

}


// MARK: - Subviews

/// A circle with its label across its lower edge.
private struct LabelledCircle<Content: View>: View {

    let label: String
    @ViewBuilder let circle: () -> Content

    var body: some View {
        VStack(spacing: -12) {
            circle()
            Text(verbatim: label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color(uiColor: .separator), lineWidth: 1)
                }
        }
    }

}


/// Dashed lines from the top edge to the bottom edge, each given by where it starts and ends as horizontal offsets from the middle.
private struct DashedLines: View {

    struct Segment {
        let start: CGFloat
        let end: CGFloat
    }

    let segments: [Segment]

    var body: some View {
        Canvas { context, size in
            var path = Path()
            for segment in segments {
                path.move(to: CGPoint(x: size.width / 2 + segment.start, y: 0))
                path.addLine(to: CGPoint(x: size.width / 2 + segment.end, y: size.height))
            }
            context.stroke(path, with: .color(Color(uiColor: .tertiaryLabel)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
    }

}


private extension Color {
    /// The green of the node standing for a group in common.
    static let commonGroupsNode = Color(red: 0.63, green: 0.86, blue: 0.75)
}

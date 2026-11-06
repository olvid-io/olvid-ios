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
import ObvSystemIcon
import ObvDesignSystem


/// A candidate replacement for the plus button's `Menu`: the actions as a card of tinted rows, the shape Messages uses.
///
/// **This is not wired to anything.** It exists to be looked at in the previews below, the question being whether nine
/// tinted circles read as a toolkit or as a toybox — which is not answerable by reasoning about it.
///
/// One thing it does differently from the menu, forced by the shape rather than chosen: the most used action is at the
/// **top**, where the menu puts it nearest the button. A card is read like a page, and its clipping agrees — Messages'
/// own panel scrolls with Camera and Photos pinned at the top and Check In cut off at the bottom. See
/// ``ComposeViewParameters/Action/orderShownInPanel``.
struct ComposeActionsPanelView: View {
    
    /// How one group of actions is told from the next.
    enum Separation {
        /// A hairline between groups, edge to edge — the card is a container and the line divides it, which is what a
        /// menu does between its sections. Held off an edge it reads as decoration rather than as structure.
        case hairlines
        /// A gap between groups and no line at all. Quieter, and costs about as much height as a hairline does.
        case extraSpacing
        /// Nothing, as Messages has it — which works there because every row is a different app.
        case none
    }
    
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    
    /// The height the rows *want*, measured. See ``body`` for why it cannot simply be asked for.
    @State private var heightTheRowsWant: CGFloat = 0
    
    let actions: [ComposeViewParameters.Action]
    var separation: Separation = .hairlines
    /// Multiplies the paling within a group, so the ramp can be looked at at more than one strength. 1 is the palette.
    var rampStrength: Double = 1
    var maximumHeight: CGFloat? = nil
    /// Whether the card paints its own material and corners. A popover is already a card, so inside one this is false and
    /// the popover's own chrome — Liquid Glass from iOS 26 on — is what the rows sit on. Two cards would be one too many.
    var drawsItsOwnCard: Bool = true
    /// What a row is called. Passed in rather than read off the action, one of them naming the contact this discussion
    /// is with — see `ComposeViewDataSourceModel.actionTitle(for:)`.
    var titleForAction: (ComposeViewParameters.Action) -> String = { $0.title }
    var actionTapped: (ComposeViewParameters.Action) -> Void = { _ in }
    
    private static let cardCornerRadius: CGFloat = 26
    /// The card has a **definite** width rather than hugging its widest row. Hugging it needs `fixedSize(horizontal:)`,
    /// which asks every child for its ideal width — and a separator has no intrinsic width at all, so it collapses to
    /// nothing and the grouping silently disappears. Messages' card is a fixed width too, at about 79% of the screen.
    ///
    /// It widens at the accessibility sizes because the labels do not shrink to fit: at `.accessibility3` "Introduce…"
    /// broke *mid-word*, putting its ellipsis alone on a second line, which reads as a bug rather than as wrapping.
    private var cardWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 340 : 300
    }
    static let horizontalPadding: CGFloat = 18
    static let circleToLabelSpacing: CGFloat = 14
    static let circleDiameter: CGFloat = 38
    
    /// Where the labels start, the circles being to their leading side.
    static var underTheLabels: CGFloat { horizontalPadding + circleDiameter + circleToLabelSpacing }
    
    /// No taller than the rows want, and no taller than a caller asked for. Shrinking below this is what the scrolling
    /// is for; growing above it would only add empty card.
    private var greatestUsefulHeight: CGFloat? {
        guard heightTheRowsWant > 0 else { return maximumHeight }
        guard let maximumHeight else { return heightTheRowsWant }
        return min(maximumHeight, heightTheRowsWant)
    }
    
    /// The actions cut into runs of the same kind, in the order they are shown. The settings come last, a kind of their
    /// own, being the one row that does not put anything into the draft.
    private var groups: [[ComposeViewParameters.Action]] {
        var groups: [[ComposeViewParameters.Action]] = []
        for action in actions {
            if let last = groups.last, last.last?.kind == action.kind {
                groups[groups.endIndex - 1] = last + [action]
            } else {
                groups.append([action])
            }
        }
        return groups
    }
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 { separator }
                    ForEach(Array(group.enumerated()), id: \.element.id) { rank, action in
                        Button {
                            actionTapped(action)
                        } label: {
                            RowView(icon: action.icon,
                                    title: titleForAction(action),
                                    tint: tint(for: action, rank: rank, outOf: group.count))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 10)
            .background {
                /// The rows are measured rather than asked for, `onGeometryChange` being iOS 18 and this iOS 16.
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { heightTheRowsWant = proxy.size.height }
                        .onChange(of: proxy.size.height) { heightTheRowsWant = $0 }
                }
            }
        }
        .scrollBounceBehaviorOniOS16Dot4(.basedOnSize)
        .frame(width: cardWidth)
        /// An **ideal** height rather than a fixed one, and this is the whole of what makes the card scroll when it does
        /// not fit. A popover takes its size from its content's ideal size, then clamps it to the screen and proposes the
        /// clamped height back — so the ideal is what asks for the room, and accepting the smaller proposal is what lets
        /// the scroll view scroll. `fixedSize(vertical:)` was here first and did the first half only: it asked for the
        /// room and then refused the answer, so at `.accessibility3` the card filled the screen and would not move.
        ///
        /// The ceiling below is the other half: an ideal height alone is only a preference, so a container offering more
        /// — the previews, and anything that is not a popover — would stretch the card to fill it.
        .frame(idealHeight: heightTheRowsWant > 0 ? heightTheRowsWant : nil)
        .frame(maxHeight: greatestUsefulHeight)
        .background {
            if drawsItsOwnCard {
                RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
            }
        }
    }
    
    
    @ViewBuilder
    private var separator: some View {
        switch separation {
        case .hairlines:
            /// Not `Divider()`: its colour is `separator`, which is faint by design and close to invisible over a
            /// material, and it carries no width of its own. This one states both.
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(height: 1 / displayScale)
                .padding(.vertical, 4)
        case .extraSpacing:
            Color.clear
                .frame(height: 12)
        case .none:
            EmptyView()
        }
    }
    
    
    /// How a row's circle is painted: its group's colour, weakened by how far down the group the row sits.
    ///
    /// The weakening is applied as **filters on the shape** rather than by naming a paler colour, and that is the whole
    /// point — a `Color(hue:saturation:brightness:)` is a fixed set of numbers, where a system colour resolves itself
    /// per appearance and per contrast setting. Filtering it keeps that: the colour is resolved first, the ramp second.
    ///
    /// Saturation carries most of the ramp because it means the same thing in both appearances — less saturated is less
    /// prominent, always. Brightness cannot: **lighter is weaker on a white background and stronger on a black one**, so
    /// its sign follows the appearance rather than being fixed.
    private func tint(for action: ComposeViewParameters.Action, rank: Int, outOf groupSize: Int) -> RowTint {
        let howFarDownTheGroup = groupSize <= 1 ? 0 : Double(rank) / Double(groupSize - 1)
        let ramp = howFarDownTheGroup * rampStrength
        return RowTint(colour: action.kind.colour,
                       saturation: max(0, 1 - Self.saturationFalloff * ramp),
                       brightness: (colorScheme == .dark ? -Self.brightnessStep : Self.brightnessStep) * ramp)
    }
    
    /// How much saturation the last row of a group gives up.
    private static let saturationFalloff: Double = 0.45
    /// How far the last row of a group moves away from the background it sits on.
    private static let brightnessStep: Double = 0.09
    
}


// MARK: - The colour of a group

extension ComposeViewParameters.Action.Kind {
    
    /// The system colour a kind's rows are drawn from, at full strength on the group's first row.
    ///
    /// System colours rather than values of our own, so that the panel follows the appearance and the contrast settings
    /// the way everything around it does — the hand-picked hues these replaced painted the same numbers in light and in
    /// dark. They also happen to be the hues that were arrived at by hand, so nothing about the design changed with them.
    ///
    /// The pairing is not arbitrary: green sits between the blue above it and the purple below because blue and purple
    /// are close enough on the wheel that the two busiest groups would otherwise read as one long run.
    var colour: Color {
        switch self {
        case .attach: return .blue
        case .capture: return .green
        case .insert: return .purple
        case .ephemeral: return .orange
        case .contact: return .pink
        case .settings: return .gray
        }
    }
    
}


extension ComposeActionsPanelView {
    
    /// A system colour and the two filters that weaken it. Kept apart from the colour so that the filters land on the
    /// shape alone and never on the glyph drawn over it.
    struct RowTint {
        let colour: Color
        let saturation: Double
        let brightness: Double
    }
    
}


// MARK: - One row

extension ComposeActionsPanelView {
    
    private struct RowView: View {
        
        let icon: SystemIcon
        let title: String
        let tint: ComposeActionsPanelView.RowTint
        
        /// The circle does not grow with Dynamic Type, so **the glyph inside it must not either**: a fixed-size container
        /// needs fixed-size type. That is only acceptable because the glyph repeats what the label says, and the label *does* scale.
        private static let glyphSize: CGFloat = 17
        
        var body: some View {
            HStack(spacing: ComposeActionsPanelView.circleToLabelSpacing) {
                /// **Hidden from VoiceOver**, or the row is announced twice: `Image(systemName:)` carries a label taken
                /// from the symbol and a `Button` merges the labels of its children, so this row read as "photo, Photos"
                /// and the settings one as "gearshape fill, Customize". The glyph repeats what the label says, which is
                /// what makes it decorative, and is the same fact that lets its circle pale below the contrast a
                /// meaningful graphic would need. Not `Image(decorative:)`, which names an asset and draws nothing here.
                Image(systemIcon: icon)
                    .accessibilityHidden(true)
                    .font(.system(size: Self.glyphSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: ComposeActionsPanelView.circleDiameter, height: ComposeActionsPanelView.circleDiameter)
                    .background {
                        Circle()
                            .fill(tint.colour)
                            .saturation(tint.saturation)
                            .brightness(tint.brightness)
                    }
                Text(title)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ComposeActionsPanelView.horizontalPadding)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        
    }
    
}


// MARK: - The order, top first

extension ComposeViewParameters.Action {
    
    /// The order the card shows, read from the top, most used first — which is where Messages puts Camera and Photos,
    /// and which the clipping agrees with: a card too tall for the screen loses its **last** rows, so the least used are
    /// the ones that scroll away.
    ///
    /// This replaced a `Menu`, whose order was the reverse of this one and for a reason worth keeping: a menu spills out
    /// of its button and is read from the button outwards, so its most used action had to be declared *first* and drawn
    /// *last*. A card is read like a page instead. Deriving one order from the other by reversal was tried while both
    /// existed and was wrong — it preserved how the menu looked rather than what it meant.
    ///
    /// A kind's actions stay contiguous here, the card cutting a divider wherever the kind changes.
    static let orderShownInPanel: [Self] = [
        .chooseImageFromLibrary,
        .choseFile,
        .pasteContent,
        .shootPhotoOrMovie,
        .scanDocument,
        .shareLocation,
        .createPoll,
        .oneTimeEphemeralMessage,
        .introduceThisContact,
        .composeMessageSettings,
    ]
    
}


#if DEBUG

private let allActions = ComposeViewParameters.Action.orderShownInPanel
private let inAGroupDiscussion = allActions.filter { $0 != .introduceThisContact }

private struct PanelPreview: View {
    var separation: ComposeActionsPanelView.Separation = .hairlines
    var actions: [ComposeViewParameters.Action] = allActions
    var maximumHeight: CGFloat? = nil
    var rampStrength: Double = 1
    var body: some View {
        ComposeActionsPanelView(actions: actions,
                                separation: separation,
                                rampStrength: rampStrength,
                                maximumHeight: maximumHeight)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(Color(.systemGroupedBackground))
    }
}

// The same card in both appearances, which is the whole point of the system colours.

#Preview("1 · Light") {
    PanelPreview()
}

#Preview("2 · Dark") {
    PanelPreview()
        .preferredColorScheme(.dark)
}

// How far a group should pale from its first row. The brightness half of the ramp changes sign with the appearance, so
// both of these want looking at in both.

#Preview("3 · Paling harder, light") {
    PanelPreview(rampStrength: 1.7)
}

#Preview("4 · Paling harder, dark") {
    PanelPreview(rampStrength: 1.7)
        .preferredColorScheme(.dark)
}

// Controls.

#Preview("5 · No colour at all") {
    PanelPreview()
        .grayscale(1)
}

#Preview("6 · No dividers") {
    PanelPreview(separation: .none)
}

#Preview("7 · Group discussion, no Introduce") {
    PanelPreview(actions: inAGroupDiscussion)
}

#Preview("8 · Clipped, as Messages clips") {
    PanelPreview(maximumHeight: 420)
}

#Preview("9 · Accessibility XXL") {
    PanelPreview(maximumHeight: 600)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#endif

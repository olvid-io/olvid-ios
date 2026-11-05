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


/// Shown over the deck the first time the suggestions are opened: how to swipe a card, then where the people suggested come from.
///
/// One screen with two states rather than two pages, followed by the finger or animated when the button is used: the card of a real suggestion, tilted
/// beside the green of an accepted card, gives way to the user linked to the people suggested through a group in common.
struct ContactsSuggestionsOnboardingView: View {

    /// The card of a real suggestion, someone we share groups with. `nil` while it loads.
    let model: ContactSuggestion.Model?
    /// The user's own picture, at the top of the second state. `nil` while it loads.
    let ownedAvatar: ObvAvatarViewModel?
    /// The people suggested at the bottom of the second state, the person of ``model`` first.
    let suggestedAvatars: [ObvAvatarViewModel]
    let avatarViewDataSource: ObvAvatarViewDataSource
    let userIsDone: () -> Void

    /// 0 on the first state, 1 on the second, anything in between while the finger moves.
    @State private var progress: CGFloat = 0
    /// Where `progress` was when the current drag began.
    @State private var progressAtTheStartOfTheDrag: CGFloat?
    /// Whether a finger is on the screen. A `GestureState` goes back to `false` when the system cancels the drag, which `onEnded` never hears of:
    /// that is when the screen settles here rather than there.
    @GestureState private var isPaging = false

    /// The height left to the illustration between the texts and the button.
    @State private var roomForTheIllustration: CGFloat = 0
    /// The height the illustration is laid out at: the room, or more when its content needs more.
    @State private var heightOfTheIllustration: CGFloat = 0

    /// Below 1 only when the illustration needs more height than is left to it, on a short screen or with a large text size: the texts and the
    /// button keep theirs, the button being the way out.
    private var scaleOfTheIllustration: CGFloat {
        guard roomForTheIllustration > 0, heightOfTheIllustration > roomForTheIllustration else { return 1 }
        return roomForTheIllustration / heightOfTheIllustration
    }

    private static let spring = Animation.spring(response: 0.45, dampingFraction: 0.85)

    private static let marginAroundTheButton: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                texts
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                IllustrationHeightLayout {
                    ZStack {
                        card
                            .padding(.horizontal, 48)
                        relationshipCard
                            .padding(.horizontal, 32)
                    }
                    .padding(.vertical, 32)
                    .scaleEffect(scaleOfTheIllustration)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heightOfTheIllustration = $0 }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { roomForTheIllustration = $0 }
                OnboardingPageControl(numberOfPages: 2, currentPage: progress < 0.5 ? 0 : 1) { page in
                    withAnimation(Self.spring) { progress = CGFloat(page) }
                }
                .padding(.bottom, 16)
                // The button is as far from the bottom as from the sides, the safe area counting towards it: above a home indicator the safe area is
                // enough, while a sheet on the Mac has none.
                button
                    .padding(.horizontal, Self.marginAroundTheButton)
                    .padding(.bottom, max(0, Self.marginAroundTheButton - geometry.safeAreaInsets.bottom))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(pagingGesture(width: geometry.size.width))
        }
        // A drag the system cancelled leaves the screen between its two states, and the start of the next drag in the past. A drag that ended has
        // already settled it.
        .onChange(of: isPaging) { isPaging in
            guard !isPaging, progressAtTheStartOfTheDrag != nil else { return }
            progressAtTheStartOfTheDrag = nil
            withAnimation(Self.spring) {
                progress = progress >= 0.5 ? 1 : 0
            }
        }
        .background(Color(uiColor: .secondarySystemBackground).ignoresSafeArea())
    }


    // MARK: - The two states

    /// The opacity of what belongs to the first state, and of what belongs to the second: each fades out over the first half of the way and in over the
    /// second, so the two never overlap.
    private var firstStateOpacity: Double { Double(max(0, 1 - 2 * progress)) }
    private var secondStateOpacity: Double { Double(max(0, 2 * progress - 1)) }

    private var texts: some View {
        ZStack(alignment: .top) {
            StateTexts(title: String(localizedInThisBundle: "ONBOARDING_SWIPE_TITLE"),
                       text: String(localizedInThisBundle: "ONBOARDING_SWIPE_TEXT"))
                .opacity(firstStateOpacity)
                .accessibilityHidden(progress >= 0.5)
            StateTexts(title: String(localizedInThisBundle: "ONBOARDING_ORIGIN_TITLE"),
                       text: String(localizedInThisBundle: "ONBOARDING_ORIGIN_TEXT"))
                .opacity(secondStateOpacity)
                .accessibilityHidden(progress < 0.5)
        }
    }


    /// The scale of the card of the first state, which straightens and grows a little as it gives way to the second.
    private var cardScale: CGFloat { 0.86 + 0.14 * progress }
    
    /// The card of the first state, beside the green of an accepted card and under the hand showing the gesture.
    private var card: some View {
        ZStack {
            // Slightly smaller than the card in front of it, and marked on the side that shows past it.
            FillView(fill: .init(decision: .accept, progress: 1, kind: .suggestion), cornerRadius: SuggestionCard.cornerRadius, markAlignment: .topTrailing)
                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: SuggestionCard.cornerRadius, style: .continuous))
                .scaleEffect(0.95 * cardScale)
                .rotationEffect(.degrees(4), anchor: .bottom)
                .offset(x: 36)
            SuggestionCard(model: model,
                           avatarViewDataSource: avatarViewDataSource,
                           userWantsToSeeDetails: { _ in },
                           fill: nil)
                .allowsHitTesting(false)
                // Attached before the card is scaled and tilted, so that it stays on the card's top right corner as the card moves. Centred on the
                // corner, a little inside it, the corner being rounded.
                .overlay(alignment: .topTrailing) {
                    Image(systemIcon: .handDraw)
                        .font(.system(size: 40))
                        .foregroundStyle(Color(uiColor: .label))
                        .alignmentGuide(.top) { $0[VerticalAlignment.center] }
                        .alignmentGuide(.trailing) { $0[HorizontalAlignment.center] }
                        .offset(x: -12, y: 12)
                        .accessibilityHidden(true)
                }
                .scaleEffect(cardScale)
                .rotationEffect(.degrees(-5 * (1 - progress)), anchor: .bottom)
                .offset(x: -12 * (1 - progress))
        }
        .opacity(firstStateOpacity)
        .accessibilityHidden(true)
    }


    /// The card of the second state, at the height its content needs, growing into place as it comes.
    private var relationshipCard: some View {
        RelationshipTreeView(ownedAvatar: ownedAvatar,
                             suggestedAvatars: suggestedAvatars,
                             avatarViewDataSource: avatarViewDataSource)
            .padding(.horizontal, 20)
            .padding(.top, 40)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity)
            // The people fading out on the sides reach past the card, and are cut by its edges. Clipped before the background, so its shadow is not.
            .clipShape(RoundedRectangle(cornerRadius: SuggestionCard.cornerRadius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: SuggestionCard.cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemBackground))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            }
            .scaleEffect(0.9 + 0.1 * progress)
            .opacity(secondStateOpacity)
            .accessibilityHidden(progress < 0.5)
    }


    /// One button for both states, which goes to the second state from the first and ends the onboarding from the second.
    private var button: some View {
        let title = progress < 0.5 ? String(localizedInThisBundle: "NEXT") : String(localizedInThisBundle: "GOT_IT")
        return PrimaryButton(title: title) {
            if progress < 0.5 {
                withAnimation(Self.spring) { progress = 1 }
            } else {
                userIsDone()
            }
        }
    }


    // MARK: - Swiping between the two states

    /// A swipe to the left goes to the second state and one to the right comes back, following the finger and settling on whichever state the release
    /// points at.
    private func pagingGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($isPaging) { _, isPaging, _ in
                isPaging = true
            }
            .onChanged { value in
                guard width > 0 else { return }
                let start = progressAtTheStartOfTheDrag ?? progress
                progressAtTheStartOfTheDrag = start
                progress = min(1, max(0, start - value.translation.width / width))
            }
            .onEnded { value in
                let start = progressAtTheStartOfTheDrag ?? progress
                progressAtTheStartOfTheDrag = nil
                guard width > 0 else { return }
                let predicted = start - value.predictedEndTranslation.width / width
                withAnimation(Self.spring) {
                    progress = predicted >= 0.5 ? 1 : 0
                }
            }
    }

}


// MARK: - Subviews

/// Gives the illustration all the height it is offered, however little, so that the texts and the button always keep theirs. When its content needs
/// more, it is laid out at the height it needs, centred, for the view to scale it down into the room.
private struct IllustrationHeightLayout: Layout {

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let illustration = subviews.first else { return .zero }
        let neededSize = illustration.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? neededSize.width, height: proposal.height ?? neededSize.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let illustration = subviews.first else { return }
        // The proposal that produced the size, not the bounds.
        let width = proposal.width ?? bounds.width
        let room = proposal.height ?? bounds.height
        let neededHeight = illustration.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        illustration.place(at: CGPoint(x: bounds.midX, y: bounds.midY),
                           anchor: .center,
                           proposal: ProposedViewSize(width: width, height: max(room, neededHeight)))
    }

}


/// The system's page control, showing which of the two states is on screen. A tap or a scrub on it asks for the other state, which the view animates
/// as it does for its button.
private struct OnboardingPageControl: UIViewRepresentable {

    let numberOfPages: Int
    let currentPage: Int
    let userWantsToGoToPage: (Int) -> Void

    func makeUIView(context: Context) -> UIPageControl {
        let pageControl = UIPageControl()
        pageControl.numberOfPages = numberOfPages
        pageControl.currentPage = currentPage
        // The default colours are meant for a dark background; this one is light or dark with the system.
        pageControl.pageIndicatorTintColor = .tertiaryLabel
        pageControl.currentPageIndicatorTintColor = .label
        pageControl.addTarget(context.coordinator, action: #selector(Coordinator.pageControlValueChanged(_:)), for: .valueChanged)
        return pageControl
    }

    func updateUIView(_ pageControl: UIPageControl, context: Context) {
        context.coordinator.userWantsToGoToPage = userWantsToGoToPage
        pageControl.numberOfPages = numberOfPages
        if pageControl.currentPage != currentPage {
            pageControl.currentPage = currentPage
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(userWantsToGoToPage: userWantsToGoToPage)
    }

    final class Coordinator: NSObject {

        var userWantsToGoToPage: (Int) -> Void

        init(userWantsToGoToPage: @escaping (Int) -> Void) {
            self.userWantsToGoToPage = userWantsToGoToPage
        }

        @objc func pageControlValueChanged(_ pageControl: UIPageControl) {
            userWantsToGoToPage(pageControl.currentPage)
        }

    }

}


private struct StateTexts: View {

    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 16) {
            Text(verbatim: title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: text)
                .font(.body)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

}


private struct PrimaryButton: View {

    let title: String
    let action: () -> Void

    var body: some View {
        OlvidButtonNew(action: action) {
            Text(verbatim: title)
        }
    }

}

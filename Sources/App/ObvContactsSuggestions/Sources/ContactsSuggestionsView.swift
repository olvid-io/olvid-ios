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


/// A deck of cards, one per suggested contact or pending invitation. Swiping the top card to the right accepts it, to the left declines it.
public struct ContactsSuggestionsView: View {

    private let ownedCryptoId: ObvCryptoId
    private let scope: ContactSuggestion.Scope
    /// The deck as the caller knew it, so the first frame shows cards rather than an empty state.
    private let initialDeck: ContactSuggestion.Deck
    private let dataSource: any ContactsSuggestionsViewDataSource
    private let actions: any ContactsSuggestionsViewActions
    private let avatarViewDataSource: ObvAvatarViewDataSource

    public struct DataSources {
        let dataSource: any ContactsSuggestionsViewDataSource
        let avatarViewDataSource: ObvAvatarViewDataSource
        public init(dataSource: any ContactsSuggestionsViewDataSource, avatarViewDataSource: ObvAvatarViewDataSource) {
            self.dataSource = dataSource
            self.avatarViewDataSource = avatarViewDataSource
        }
    }

    /// - Parameter showsOnboarding: `true` the first time the suggestions are opened, to show the onboarding over the deck.
    public init(ownedCryptoId: ObvCryptoId, scope: ContactSuggestion.Scope, initialDeck: ContactSuggestion.Deck, showsOnboarding: Bool, dataSources: DataSources, actions: any ContactsSuggestionsViewActions) {
        self.ownedCryptoId = ownedCryptoId
        self.scope = scope
        self.initialDeck = initialDeck
        self.dataSource = dataSources.dataSource
        self.actions = actions
        self.avatarViewDataSource = dataSources.avatarViewDataSource
        self._isShowingOnboarding = State(initialValue: showsOnboarding)
    }

    @State private var isShowingOnboarding: Bool
    /// The ← and → of a hardware keyboard, each pressed once.
    @StateObject private var arrowKeyPresses = ArrowKeyPresses()
    /// The cards of the first people, in the order of the deck, we share groups with. The onboarding shows the first card, then the pictures of all.
    @State private var onboardingModels = [ContactSuggestion.Model]()
    /// The user's own picture, which the onboarding links to the people suggested.
    @State private var ownedAvatar: ObvAvatarViewModel?

    /// `nil` until the stream says anything, in which case ``initialDeck`` is shown.
    @State private var streamedDeck: ContactSuggestion.Deck?
    /// Cards swiped away, hidden at once rather than when the database catches up. What is hidden is the person, whatever card the deck holds for
    /// them meanwhile: accepting an invitation deletes it before the person becomes one-to-one, and in between the deck lists them as somebody to
    /// invite. Each is dropped from here once the stream lists no card about that person.
    @State private var committed = Set<ContactSuggestion.Identifier>()
    /// Cards flying out of the screen, in the order they were swiped, with the way they leave. Kept apart from the deck: deciding a card soon drops it
    /// from the database, and so from the stream, while it is still in the air — and a card drawn from the deck would vanish mid-flight.
    @State private var departures = [Departure]()
    /// Decisions whose action has not returned yet, where there is no departure to wait for (before iOS 17).
    @State private var decisionsInFlight = Set<ContactSuggestion.Identifier>()
    @State private var dragTranslation: CGSize = .zero
    /// Whether a finger is on a card. A `GestureState` goes back to `false` when the system cancels the drag, which `onEnded` never hears of:
    /// that is when ``dragTranslation`` is reset here rather than there.
    @GestureState private var isDragging = false
    /// Measured, for how far a drag must go and where a card flies to.
    @State private var cardWidth: CGFloat = 0
    @State private var failedAction = false

    private var deck: ContactSuggestion.Deck {
        streamedDeck ?? initialDeck
    }

    /// The cards still to be decided, top card first: none about a person swiped away, or whose card is flying out.
    private var remaining: [ContactSuggestion.Identifier] {
        deck.identifiers.filter { card in
            !committed.contains(where: { $0.isAboutTheSamePerson(as: card) })
                && !departures.contains(where: { $0.identifier.isAboutTheSamePerson(as: card) })
        }
    }

    private var topCard: ContactSuggestion.Identifier? {
        remaining.first
    }

    private var numberOfCardsLeft: Int {
        remaining.count
    }

    /// While a finger holds a card: whether the top card is past the line where letting go decides. `nil` while no finger is on a card.
    private var topCardIsPastTheDecisionLine: Bool? {
        guard isDragging else { return nil }
        return SwipeDecision.isPastTheDecisionLine(translation: dragTranslation.width, cardWidth: cardWidth)
    }

    private func departure(of identifier: ContactSuggestion.Identifier) -> Departure.Way? {
        departures.first(where: { $0.identifier == identifier })?.way
    }

    private func isLeaving(_ identifier: ContactSuggestion.Identifier) -> Bool {
        departure(of: identifier) != nil
    }

    public var body: some View {
        VStack(spacing: 0) {
            if numberOfCardsLeft == 0 && departures.isEmpty {
                EmptyDeckView()
            } else {
                CardHeightLayout(preferredTopMargin: 20, preferredBottomMargin: 60) {
                    deckOfCards(cardWidth: cardWidth)
                        .background {
                            GeometryReader { geometry in
                                Color.clear
                                    .onAppear { cardWidth = geometry.size.width }
                                    .onChange(of: geometry.size.width) { cardWidth = $0 }
                            }
                        }
                }
                .padding(.horizontal, 24)
                ChoiceButtons(topCard: topCard, accept: { decideFromAButton(.accept) }, decline: { decideFromAButton(.decline) })
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground).ignoresSafeArea())
        // The onboarding shows under the bar, which keeps only the close button: the title and the menu are about the deck it hides.
        .navigationTitle(isShowingOnboarding ? "" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                ObvButtonWithCancelRole {
                    actions.userWantsToClose()
                }
            }
            if numberOfCardsLeft > 0 && !isShowingOnboarding {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            actions.userWantsToSeeOtherKnownUsers()
                        } label: {
                            Label {
                                Text("SEE_OTHER_KNOWN_USERS")
                            } icon: {
                                Image(systemIcon: .person2)
                            }
                        }
                        Button {
                            showTheOnboardingAgain()
                        } label: {
                            Label {
                                Text("HOW_IT_WORKS")
                            } icon: {
                                Image(systemIcon: .questionmarkCircle)
                            }
                        }
                    } label: {
                        Image(systemIcon: .ellipsis)
                    }
                }
            }
        }
        .overlay {
            if isShowingOnboarding {
                ContactsSuggestionsOnboardingView(model: onboardingModels.first,
                                                  ownedAvatar: ownedAvatar,
                                                  suggestedAvatars: onboardingModels.map(\.avatar),
                                                  avatarViewDataSource: avatarViewDataSource,
                                                  userIsDone: { onboardingIsDone() })
                    .transition(.opacity)
            }
        }
        // Each time the onboarding shows, as it can be asked for again from the menu: the people it shows are those still to be decided.
        .task(id: isShowingOnboarding) {
            guard isShowingOnboarding else { return }
            if ownedAvatar == nil {
                ownedAvatar = await dataSource.ownedAvatar(ownedCryptoId: ownedCryptoId)
            }
            onboardingModels = []
            await loadTheOnboardingModels()
        }
        .takesKeyboardFocusOnAppear()
        .recordsArrowKeyPresses(in: arrowKeyPresses, isActive: !isShowingOnboarding)
        .onChange(of: arrowKeyPresses.latest) { press in
            guard let press, !isShowingOnboarding else { return }
            decideFromAButton(press.decision)
        }
        .task {
            for await newDeck in dataSource.deckStream(ownedCryptoId: ownedCryptoId, scope: scope) {
                // The deck is sorted anew each time it changes; the person the reader is looking at must not be replaced under their finger,
                // even when their card has become another one.
                let previousTopCard = topCard
                if let previousTopCard, !newDeck.hasACard(aboutTheSamePersonAs: previousTopCard) {
                    withdraw(previousTopCard)
                }
                streamedDeck = newDeck.keepingOnTop(previousTopCard)
                // A person the database lists no card about needs hiding no more.
                committed = committed.filter { newDeck.hasACard(aboutTheSamePersonAs: $0) }
            }
        }
        // Opening the deck shows its cards, even under the onboarding: none of them is new any more. A deck with no new card has nothing to
        // mark, which is the case each time it appears again, after the details of a contact.
        .onAppear {
            if deck.hasANewCard {
                actions.cardsWereSeen(deck.identifiers)
            }
        }
        // Closing it too: a card that came while the deck was open was in front of the user.
        .onDisappear {
            if deck.hasANewCard {
                actions.cardsWereSeen(deck.identifiers)
            }
            // The sheet closed over the onboarding, by its close button or by a swipe down, is a way of skipping it, as the onboarding's own button is.
            if isShowingOnboarding {
                actions.onboardingWasShown()
            }
        }
        // A drag the system cancelled (the app sent to the background, a call) leaves the card where the finger was. A drag that ended has already
        // put it back or sent it away.
        .onChange(of: isDragging) { isDragging in
            guard !isDragging, dragTranslation != .zero else { return }
            withAnimation(Self.springBack) {
                dragTranslation = .zero
            }
        }
        .alert(String(localizedInThisBundle: "COULD_NOT_PERFORM_ACTION"), isPresented: $failedAction) {
            Button(String(localizedInThisBundle: "OK"), role: .cancel) {}
        }
        // Felt as the line is crossed under the finger, in either direction, and never when the finger lets go.
        .deckHaptic(.decisionLine, trigger: topCardIsPastTheDecisionLine) { old, new in
            old != nil && new != nil
        }
        .deckHaptic(.actionFailed, trigger: failedAction) { _, failed in
            failed
        }
    }


    // MARK: - Onboarding

    /// As many people as the second state of the onboarding shows: one in the middle, one either side, and two fading out.
    private static let numberOfPeopleInTheOnboarding = 5
    /// The deck starts with the invitations, then the people who share the most groups with us. Only the invitations of people we share no group with
    /// come before the first person we share a group with: when more than this many are waiting, the onboarding shows fewer people, or nobody.
    private static let numberOfCardsLookedAtForTheOnboarding = 20

    /// The cards of the first people still to be decided we share groups with, which is what the onboarding explains. Each is shown as soon as it
    /// is built, so the first card does not wait for the others.
    private func loadTheOnboardingModels() async {
        for identifier in remaining.prefix(Self.numberOfCardsLookedAtForTheOnboarding) {
            guard onboardingModels.count < Self.numberOfPeopleInTheOnboarding else { return }
            guard let model = await dataSource.model(for: identifier), model.commonGroups != nil else { continue }
            onboardingModels.append(model)
        }
    }


    /// The onboarding again, over the deck as it is, from the menu.
    private func showTheOnboardingAgain() {
        withAnimation(.easeOut(duration: 0.25)) {
            isShowingOnboarding = true
        }
    }


    private func onboardingIsDone() {
        withAnimation(.easeOut(duration: 0.25)) {
            isShowingOnboarding = false
        }
        actions.onboardingWasShown()
    }


    private var title: String {
        if numberOfCardsLeft > 0 {
            return String(localizedInThisBundle: "SUGGESTED_CONTACTS_\(numberOfCardsLeft)")
        } else {
            return String(localizedInThisBundle: "SUGGESTED_CONTACTS")
        }
    }


    // MARK: - The deck

    /// How many cards wait under the finger while the deck has them, whatever is flying out.
    private static let numberOfWaitingCardsShown = 3
    
    /// The cards waiting under the finger, top card first. Only the top card follows the finger.
    private var waitingCards: [ContactSuggestion.Identifier] {
        Array(remaining.prefix(Self.numberOfWaitingCardsShown))
    }
    
    /// The cards flying out of the screen. Drawn on top of the waiting ones, and on top of each other in the order they were swiped. Whether the
    /// deck still lists them is irrelevant: each stays until its flight is over.
    private var flyingCards: [ContactSuggestion.Identifier] {
        departures.map(\.identifier)
    }
    
    /// The three waiting cards, under every card still flying out. A card flying out does not take a waiting card's place, so each swipe brings the
    /// next card in under the deck at once, fading in, however quickly the reader swipes.
    private func deckOfCards(cardWidth: CGFloat) -> some View {
        let waiting = waitingCards
        let flying = flyingCards
        let shown = Array(waiting.reversed()) + flying
        return ZStack {
            ForEach(shown, id: \.self) { identifier in
                let flyingIndex = flying.firstIndex(of: identifier)
                let depth = waiting.firstIndex(of: identifier) ?? 0
                let isTopCard = identifier == topCard
                CardSlot(identifier: identifier,
                         dataSource: dataSource,
                         avatarViewDataSource: avatarViewDataSource,
                         userWantsToSeeDetails: { actions.userWantsToSeeDetails(of: $0) },
                         fill: fill(of: identifier, cardWidth: cardWidth))
                    .scaleEffect(1 - 0.05 * CGFloat(depth), anchor: .bottom)
                    .offset(y: 14 * CGFloat(depth))
                    .offset(offset(of: identifier, cardWidth: cardWidth))
                    .rotationEffect(rotation(of: identifier, cardWidth: cardWidth), anchor: .bottom)
                    .opacity(departure(of: identifier) == .withdrawn ? 0 : 1)
                    .zIndex(flyingIndex.map({ Double(Self.numberOfWaitingCardsShown + 1 + $0) }) ?? Double(Self.numberOfWaitingCardsShown - depth))
                    .allowsHitTesting(isTopCard)
                    .accessibilityHidden(!isTopCard)
                    .gesture(dragGesture(of: identifier, cardWidth: cardWidth), including: isTopCard ? .all : .subviews)
                    .accessibilityAction(named: Text(verbatim: acceptLabel(for: identifier))) { decide(.accept) }
                    .accessibilityAction(named: Text(verbatim: declineLabel(for: identifier))) { decide(.decline) }
                    .transition(.opacity)
            }
        }
    }


    private func offset(of identifier: ContactSuggestion.Identifier, cardWidth: CGFloat) -> CGSize {
        if let departure = departure(of: identifier) {
            switch departure {
            case .decided(let decision):
                let direction: CGFloat = decision == .accept ? 1 : -1
                return CGSize(width: direction * cardWidth * 1.6, height: 40)
            case .withdrawn:
                return .zero
            }
        } else if identifier == topCard {
            return dragTranslation
        } else {
            return .zero
        }
    }


    private func rotation(of identifier: ContactSuggestion.Identifier, cardWidth: CGFloat) -> Angle {
        let translation = offset(of: identifier, cardWidth: cardWidth).width
        guard cardWidth > 0 else { return .zero }
        return .degrees(Double(translation / cardWidth) * 18)
    }


    private func fill(of identifier: ContactSuggestion.Identifier, cardWidth: CGFloat) -> CardFill? {
        if let departure = departure(of: identifier) {
            switch departure {
            case .decided(let decision):
                return .init(decision: decision, progress: 1, kind: identifier.kind)
            case .withdrawn:
                return nil
            }
        }
        guard identifier == topCard, dragTranslation.width != 0 else { return nil }
        let progress = SwipeDecision.progress(translation: dragTranslation.width, cardWidth: cardWidth)
        return .init(decision: dragTranslation.width > 0 ? .accept : .decline, progress: progress, kind: identifier.kind)
    }


    /// The drag of one card. It moves and decides that card only, and only while it is the top card: a card withdrawn under the finger keeps its
    /// gesture as it fades out, and must not move or decide the card now on top.
    private func dragGesture(of identifier: ContactSuggestion.Identifier, cardWidth: CGFloat) -> some Gesture {
        DragGesture()
            .updating($isDragging) { _, isDragging, _ in
                isDragging = true
            }
            .onChanged { value in
                guard identifier == topCard else { return }
                dragTranslation = value.translation
            }
            .onEnded { value in
                guard identifier == topCard else { return }
                let decision = SwipeDecision.decide(translation: value.translation.width,
                                                    predictedEndTranslation: value.predictedEndTranslation.width,
                                                    cardWidth: cardWidth)
                switch decision {
                case .accept, .decline:
                    decide(decision)
                case .cancel:
                    withAnimation(Self.springBack) {
                        dragTranslation = .zero
                    }
                }
            }
    }

    /// How a card goes back to its place when nothing was decided.
    private static let springBack = Animation.spring(response: 0.35, dampingFraction: 0.7)


    // MARK: - Deciding

    /// A card leaving the screen, and the way it leaves.
    private struct Departure {
        enum Way: Equatable {
            /// The reader decided: the card flies out on the side of the decision.
            case decided(SwipeDecision)
            /// The database took the top card away, the reader having decided nothing: it fades out where it stands.
            case withdrawn
        }
        let identifier: ContactSuggestion.Identifier
        let way: Way
    }

    /// A tap on a button, refused while a card is still leaving. The next card is on top as soon as one is decided, so a second tap of a double tap
    /// would otherwise decide for a person the reader has not seen. A swipe needs no such guard, being a new gesture on a card already in view.
    private func decideFromAButton(_ decision: SwipeDecision) {
        guard departures.isEmpty, decisionsInFlight.isEmpty else { return }
        decide(decision)
    }

    /// Sends the top card away and performs what it means. Should the action fail, the card comes back.
    private func decide(_ decision: SwipeDecision) {
        guard let identifier = topCard, decision != .cancel else { return }

        if #available(iOS 17, *) {
            withAnimation(.easeIn(duration: 0.3), completionCriteria: .removed) {
                departures.append(.init(identifier: identifier, way: .decided(decision)))
                dragTranslation = .zero
            } completion: {
                // Only now is the card gone from the screen, and can leave the hierarchy.
                guard isLeaving(identifier) else { return }
                departures.removeAll(where: { $0.identifier == identifier })
                // A person the deck lists no card about has nothing to be hidden from.
                if deck.hasACard(aboutTheSamePersonAs: identifier) {
                    committed.insert(identifier)
                }
            }
        } else {
            // No completion to wait for: the card fades out where it stands, and the buttons wait for the action instead.
            decisionsInFlight.insert(identifier)
            withAnimation(.easeIn(duration: 0.25)) {
                committed.insert(identifier)
                dragTranslation = .zero
            }
        }

        Task {
            defer { decisionsInFlight.remove(identifier) }
            do {
                switch decision {
                case .accept:
                    try await actions.userAccepted(identifier)
                case .decline:
                    try await actions.userDeclined(identifier)
                case .cancel:
                    return
                }
            } catch {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    departures.removeAll(where: { $0.identifier == identifier })
                    committed.remove(identifier)
                }
                failedAction = true
            }
        }
    }

    /// The top card is gone from the database while the reader was on it: answered on another device, cancelled by its sender, or no longer
    /// suggestable. It leaves as a departure, so that the buttons wait for it to be gone rather than act on the next person unseen, and a drag on
    /// it ends with it.
    private func withdraw(_ identifier: ContactSuggestion.Identifier) {
        if #available(iOS 17, *) {
            withAnimation(.easeIn(duration: 0.3), completionCriteria: .removed) {
                departures.append(.init(identifier: identifier, way: .withdrawn))
                dragTranslation = .zero
            } completion: {
                departures.removeAll(where: { $0.identifier == identifier && $0.way == .withdrawn })
            }
        } else {
            // No completion to wait for, and no action for the buttons to wait on: the card goes with the deck, and only the drag is undone.
            dragTranslation = .zero
        }
    }


    private func acceptLabel(for identifier: ContactSuggestion.Identifier) -> String {
        identifier.acceptTitle
    }

    private func declineLabel(for identifier: ContactSuggestion.Identifier) -> String {
        identifier.declineTitle
    }

}


// MARK: - What the buttons say

private extension ContactSuggestion.Identifier {

    /// The right. On the card of an invitation we sent, it cancels it: the left only skips cards, and a run of skips must never undo anything.
    var acceptTitle: String {
        switch kind {
        case .suggestion: return String(localizedInThisBundle: "INVITE")
        case .invitationToAnswer: return String(localizedInThisBundle: "ACCEPT")
        case .invitationSent: return String(localizedInThisBundle: "UNINVITE")
        }
    }

    /// The left.
    var declineTitle: String {
        switch kind {
        case .suggestion: return String(localizedInThisBundle: "NOT_NOW")
        case .invitationToAnswer: return String(localizedInThisBundle: "DECLINE")
        case .invitationSent: return String(localizedInThisBundle: "OK")
        }
    }

    /// Declining an invitation answers it: the left button is red. Elsewhere the left sets a person aside or changes nothing.
    var declineAnswersSomebody: Bool {
        kind == .invitationToAnswer
    }

}


// MARK: - One card

/// A card in the deck: its background, the person, and the green or red fill of a swipe. Loads its own model.
private struct CardSlot: View {

    let identifier: ContactSuggestion.Identifier
    let dataSource: any ContactsSuggestionsViewDataSource
    let avatarViewDataSource: ObvAvatarViewDataSource
    let userWantsToSeeDetails: (ObvContactIdentifier) -> Void
    let fill: CardFill?

    @State private var model: ContactSuggestion.Model?

    var body: some View {
        SuggestionCard(model: model,
                       avatarViewDataSource: avatarViewDataSource,
                       userWantsToSeeDetails: userWantsToSeeDetails,
                       fill: fill)
            .task(id: identifier) {
                let model = await dataSource.model(for: identifier)
                if self.model != model {
                    self.model = model
                }
            }
    }

}


/// How far a card has gone towards a decision, which is how strongly it takes the decision's colour.
struct CardFill: Equatable {
    let decision: SwipeDecision
    let progress: CGFloat
    /// The colour depends on the card too: a swipe to the right cancels an invitation we sent.
    let kind: ContactSuggestion.Identifier.Kind
}


/// A card as the deck draws it: the person on a rounded background, and the colour of a swipe over it. Also drawn by the onboarding, so the reader
/// learns on the very card they will swipe.
struct SuggestionCard: View {

    let model: ContactSuggestion.Model?
    let avatarViewDataSource: ObvAvatarViewDataSource
    let userWantsToSeeDetails: (ObvContactIdentifier) -> Void
    let fill: CardFill?

    static let cornerRadius: CGFloat = 40

    var body: some View {
        SuggestionCardView(model: model,
                           avatarViewDataSource: avatarViewDataSource,
                           userWantsToSeeDetails: userWantsToSeeDetails)
            // Clipped before the background, so that nothing of the content reaches past the rounded corners while the shadow is not cut.
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemBackground))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            }
            .overlay {
                if let fill {
                    FillView(fill: fill, cornerRadius: Self.cornerRadius)
                }
            }
            .accessibilityElement(children: .contain)
    }

}


/// The colour a card takes as it is swiped: green with a check on the top left towards accepting, red with a cross on the top right towards declining.
/// On the card of an invitation we sent, the right cancels it, in red with a cross, and the left changes nothing, in grey with a check.
struct FillView: View {

    let fill: CardFill
    let cornerRadius: CGFloat
    /// Where the mark goes. By default on the side the card leaves from: top left towards accepting, top right towards declining.
    var markAlignment: Alignment? = nil

    @ScaledMetric(relativeTo: .body) private var markDiameter: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(color)
            .opacity(fill.progress)
            .overlay(alignment: markAlignment ?? (fill.decision == .accept ? .topLeading : .topTrailing)) {
                Image(systemIcon: mark)
                    .font(.system(size: markDiameter * 0.45, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: markDiameter, height: markDiameter)
                    .background(.white, in: Circle())
                    .padding(20)
                    .opacity(fill.progress)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var towardsTheRight: Bool {
        fill.decision == .accept
    }

    private var color: Color {
        switch fill.kind {
        case .suggestion, .invitationToAnswer: return towardsTheRight ? .suggestionAccept : .suggestionDecline
        case .invitationSent: return towardsTheRight ? .suggestionDecline : Color(uiColor: .systemGray)
        }
    }

    private var mark: SystemIcon {
        switch fill.kind {
        case .suggestion, .invitationToAnswer: return towardsTheRight ? .checkmark : .xmark
        case .invitationSent: return towardsTheRight ? .xmark : .checkmark
        }
    }

}


// MARK: - The buttons under the deck

private struct ChoiceButtons: View {

    let topCard: ContactSuggestion.Identifier?
    let accept: () -> Void
    let decline: () -> Void

    /// With no card left, the buttons are disabled and keep the titles of a suggestion.
    private var kindOfTopCard: ContactSuggestion.Identifier.Kind {
        topCard?.kind ?? .suggestion
    }

    private var declineIsRed: Bool {
        topCard?.declineAnswersSomebody ?? false
    }

    private var declineTitle: String {
        topCard?.declineTitle ?? String(localizedInThisBundle: "NOT_NOW")
    }

    private var acceptTitle: String {
        topCard?.acceptTitle ?? String(localizedInThisBundle: "INVITE")
    }

    var body: some View {
        HStack(spacing: 16) {
            // The tint colours the background of the button before iOS 26; the text keeps its own colour on every version.
            OlvidButtonNew(action: decline, style: .glassOrBordered) {
                Text(verbatim: declineTitle)
                    .foregroundStyle(declineIsRed ? Color.suggestionDecline : Color(uiColor: .label))
            }
            .tint(declineIsRed ? Color.suggestionDecline : Color(uiColor: .systemGray))
            .arrowKeyTooltip(title: declineTitle, arrow: "←")
            OlvidButtonNew(action: accept) {
                // Concatenated rather than interpolated: an interpolated `Text` is a localizable key, and the build would add one to the catalog.
                switch kindOfTopCard {
                case .suggestion:
                    Text(Image(systemIcon: .personFillBadgePlus)) + Text(verbatim: " " + acceptTitle)
                case .invitationToAnswer:
                    Text(verbatim: acceptTitle)
                case .invitationSent:
                    Text(Image(systemIcon: .personFillBadgeMinus)) + Text(verbatim: " " + acceptTitle)
                }
            }
            // Green to invite or accept; the red of a decline to cancel an invitation we sent.
            .tint(kindOfTopCard == .invitationSent ? Color.suggestionDecline : Color.suggestionAccept)
            .arrowKeyTooltip(title: acceptTitle, arrow: "→")
        }
        .disabled(topCard == nil)
    }

}


// MARK: - Haptics

/// The haptics of the deck, felt on an iPhone. There are none before iOS 17, where `sensoryFeedback` does not exist.
private enum DeckHaptic {

    /// The drag of the top card crosses the line where letting go decides. The impact is the one of the swipe that replies to a message.
    case decisionLine
    /// An accept or a decline failed, and the card came back.
    case actionFailed

    @available(iOS 17, *)
    var feedback: SensoryFeedback {
        switch self {
        case .decisionLine: return .impact
        case .actionFailed: return .error
        }
    }

}


private extension View {

    /// Plays `haptic` each time `trigger` changes and `condition` accepts the change.
    func deckHaptic<T: Equatable>(_ haptic: DeckHaptic, trigger: T, condition: @escaping (_ oldValue: T, _ newValue: T) -> Bool) -> some View {
        modifier(DeckHapticModifier(haptic: haptic, trigger: trigger, condition: condition))
    }

}


private struct DeckHapticModifier<T: Equatable>: ViewModifier {

    let haptic: DeckHaptic
    let trigger: T
    let condition: (_ oldValue: T, _ newValue: T) -> Bool

    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.sensoryFeedback(haptic.feedback, trigger: trigger, condition: condition)
        } else {
            content
        }
    }

}


// MARK: - The arrow keys

/// The arrow keys pressed on the deck: → accepts the top card, ← declines it, as the buttons do.
///
/// The key handler reaches the view through this object, which it holds weakly. SwiftUI keeps the handlers of `onKeyPress` alive past the life of
/// the view that installed them, so a handler holding the view would keep the view's state for good.
@MainActor
private final class ArrowKeyPresses: ObservableObject {

    struct Press: Equatable {
        let decision: SwipeDecision
        /// Makes two presses of the same key two changes.
        let id = UUID()
    }

    @Published private(set) var latest: Press?

    /// Publishes the press on the next turn of the main queue. On Mac Catalyst, `onKeyPress` calls its handler during a view update, and a change
    /// published from there is undefined behaviour.
    func record(_ decision: SwipeDecision) {
        let press = Press(decision: decision)
        Task { @MainActor [weak self] in
            self?.latest = press
        }
    }

}


private extension View {

    /// Records ← and → in `presses` while the view has the keyboard focus.
    ///
    /// Only the press counts, not the repeat of a key held down: a repeat would decide card after card, each one unseen, and accepting sends an
    /// invitation. `keyboardShortcut` is not used: on Mac Catalyst it never fires for an arrow, which the system keeps for itself, and a held shortcut
    /// repeats even with `buttonRepeatBehavior(.disabled)`. `onKeyPress` exists from iOS 17, so there are no keys before.
    func recordsArrowKeyPresses(in presses: ArrowKeyPresses, isActive: Bool) -> some View {
        modifier(RecordsArrowKeyPresses(presses: presses, isActive: isActive))
    }

    /// The tooltip of a button that an arrow key also presses, such as "Invite (→)": the title, then the key, as the Mac shows a shortcut.
    ///
    /// Only where ``recordsArrowKeyPresses(in:isActive:)`` gives the keys, so that the tooltip never names a key that does nothing.
    func arrowKeyTooltip(title: String, arrow: String) -> some View {
        modifier(ArrowKeyTooltip(title: title, arrow: arrow))
    }

}


private struct ArrowKeyTooltip: ViewModifier {

    let title: String
    let arrow: String

    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            // Concatenated rather than interpolated, so that the build adds no key to the catalog.
            content.help(Text(verbatim: title + " (" + arrow + ")"))
        } else {
            content
        }
    }

}


private struct RecordsArrowKeyPresses: ViewModifier {

    let presses: ArrowKeyPresses
    /// False while the onboarding covers the deck, so that a key does not decide a card nobody sees.
    let isActive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content
                .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { [weak presses, isActive] press in
                    guard isActive, let presses else { return .ignored }
                    presses.record(press.key == .rightArrow ? .accept : .decline)
                    return .handled
                }
        } else {
            content
        }
    }

}


// MARK: - Empty deck

private struct EmptyDeckView: View {

    var body: some View {
        VStack(spacing: 16) {
            Text(verbatim: "🎉")
                .font(.system(size: 72))
                .accessibilityHidden(true)
            Text("YOU_ARE_ALL_CAUGHT_UP")
                .font(.title3)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}


// MARK: - Colours

extension Color {
    /// The green of inviting and accepting.
    static let suggestionAccept = Color(red: 0.25, green: 0.55, blue: 0.39)
    /// The red of declining.
    static let suggestionDecline = Color(red: 0.84, green: 0.38, blue: 0.31)
}

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
import ObvAccessibility
import ObvSystemIcon


/// The poll shown inside a message bubble: its question, its answers with their share of the votes, when it ends and how many have voted.
///
/// **Drawn by both discussion screens.** It began inside the legacy screen's `MessagePollView`, a UIKit cell subview hosting it in a `UIHostingController`, and moved
/// here so that the SwiftUI screen draws the same poll rather than a second one written to match. Its body is unchanged by that move; what changed is that it is given
/// a model instead of reading Core Data through it, and that it speaks through a protocol instead of an app-side delegate.
///
/// It belongs to `ObvPollFeature` because everything a poll needs is already here — the palette of ``SwiftUI/Color/pollColors``, the accessibility of
/// `ObvAccessibility`, and the screen a tap leads to — and because this module knows nothing of persistence, which is what lets two screens share it.
public struct MessagePollContentView: View {

    private let viewModel: MessagePollViewModel?
    private let textColor: Color
    private let progressColor: Color

    private weak var delegate: (any MessagePollContentViewDelegate)?

    /// How a piece of the poll's own text — its question, and each of its answers — becomes what is drawn.
    ///
    /// **It exists so that a poll found by a search can show why**, and it is a closure rather than a term because the rule for what counts as a match belongs to
    /// whoever is searching, not here: this module knows nothing of persistence and should know nothing of searching either. By default it changes nothing.
    ///
    /// Both the question and the answers go through it, because both are searchable: the text a poll leaves for clients too old to understand one is its question
    /// *and* its numbered answers, so a reader may well have matched an answer.
    private let asDrawn: (String) -> AttributedString

    /// The colours come from the bubble this sits in — white on Olvid blue for a message sent, the label colour on the received background — since a poll is drawn
    /// *inside* a bubble and has to read against it.
    ///
    /// A nil model draws a spinner: the legacy screen creates this view before it has anything to show, and so does a cell whose stream has not spoken yet.
    public init(viewModel: MessagePollViewModel?, textColor: Color, progressColor: Color, delegate: (any MessagePollContentViewDelegate)?, asDrawn: @escaping (String) -> AttributedString = { AttributedString($0) }) {
        self.viewModel = viewModel
        self.textColor = textColor
        self.progressColor = progressColor
        self.delegate = delegate
        self.asDrawn = asDrawn
    }

    private func updateVote(for candidate: MessagePollCandidateViewModel, voted: Bool) {
        Task {

            let hasVotedToNone: Bool = self.viewModel?.candidates.contains { $0.uuid == .uuidOfPollCandidateNone && $0.hasVoted } ?? false

            var voteStatus: VoteSentStatus = .canBeSent
            if let expirationDate = viewModel?.expirationDate, Date.now >= expirationDate {
                voteStatus = .pollFinished
            } else if candidate.uuid != .uuidOfPollCandidateNone, hasVotedToNone {
                voteStatus = .blockedByNone
            }
            try await delegate?.userWantsToUpdatePollVote(self, pollCandidateUUID: candidate.uuid, voted: voted, voteSentStatus: voteStatus)
        }
    }

    fileprivate struct CandidateToggleView: ObvAccessibilityProvidableView {
        let viewModel: MessagePollViewModel
        let candidate: MessagePollCandidateViewModel
        let onChange: (Bool) -> ()

        /// Said while a finger is on this answer, and again when it leaves — see ``MessagePollContentViewDelegate/aFingerIsOnAnAnswerOfThePoll(_:)``, which is where
        /// this goes and why anything wants to know.
        let aFingerIsOnIt: (Bool) -> ()

        let textColor: Color
        let progressColor: Color

        /// See ``MessagePollContentView/asDrawn``. An answer is searchable, so an answer must be able to show a match.
        let asDrawn: (String) -> AttributedString

        /// **Left as plain text on purpose.** What is read aloud is the answer, and a highlight is a thing seen rather than a thing said.
        var accessibilityAttributes: ObvAccessibilityAttributes {

            var traits: [AccessibilityTraits] = [.isButton]
            var value: String = "\(Int(candidate.totalPercent))%"

            if candidate.hasVoted {
                traits.append(.isSelected)
                value += ", " + String(localizedInThisBundle: "ACCESSIBILITY_POLL_HAS_VOTED")
            }

            return .init(label: candidate.text,
                         value: value,
                         actions: nil,
                         hint: nil,
                         traits: traits)
        }

        init(for candidate: MessagePollCandidateViewModel,
             viewModel: MessagePollViewModel,
             textColor: Color,
             progressColor: Color,
             asDrawn: @escaping (String) -> AttributedString,
             aFingerIsOnIt: @escaping (Bool) -> () = { _ in },
             onChange: @escaping (Bool) -> ()) {
            self.candidate = candidate
            self.viewModel = viewModel
            self.onChange = onChange
            self.aFingerIsOnIt = aFingerIsOnIt
            self.textColor = textColor
            self.progressColor = progressColor
            self.asDrawn = asDrawn
        }

        func color(for candidate: MessagePollCandidateViewModel) -> Color? {

            if let index = viewModel.candidates.firstIndex(of: candidate) {
                let colorIndex = index % Color.pollColors.count
                return Color.pollColors[colorIndex]
            }

            return nil
        }

        var body: some View {
            // **Not the automatic style, and that is not cosmetic.** The automatic style inside a `List` row makes a button the *row's* button rather than a tap
            // target of its own, so an answer tapped in the SwiftUI discussion screen never fired at all and the tap fell through to the poll behind it. Every
            // button on that screen — the play control of a recording, its rate capsule, a location's itinerary — is careful about the same thing.
            //
            // It keeps `.plain`, and says separately **while a finger is on it** — see ``MessagePollContentViewDelegate/aFingerIsOnAnAnswerOfThePoll(_:)`` for who
            // wants to know. A `ButtonStyle` reading `configuration.isPressed` was tried first and measured wrong: inside a `List` row that state arrives some
            // 385ms after the touch, which is far too late for the question being asked. A long press of the answer's own reports at touch-down, is never held long
            // enough to fire, and — unlike a `DragGesture` — does not stop the reader scrolling with a thumb over the answers.
            Button(action: {
                onChange(!candidate.hasVoted)
            }) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle()
                            .stroke(textColor, lineWidth: 1)
                        if candidate.hasVoted {
                            Image(systemIcon: .checkmarkCircleFill)
                                .resizable()
                                .foregroundStyle(textColor)
                        }
                    }
                    .frame(width: 20, height: 20)
                    VStack(alignment: .leading) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(asDrawn(candidate.text))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true) // Used to force text to display in multiline
                            Spacer()
                            Text(verbatim: "\(Int(candidate.totalPercent))%")
                                .font(.footnote)
                                .foregroundStyle(textColor.opacity(0.75))
                        }

                        ProgressView(value: candidate.totalPercent, total: 100.0)
                            .progressViewStyle(LargerProgressViewStyle(tintColor: color(for: candidate) ?? progressColor, backgroundColor: textColor.opacity(0.3)))
                            .frame(height: 8.0)
                    }
                }
                // **The whole row, and not only what is drawn in it.** A stroked `Circle` is hit-testable on its 1pt outline and nowhere else, and the empty space of
                // an `HStack` is not hit-testable at all — so without this, tapping the middle of the circle, or the gap beside the text, missed the answer entirely
                // and fell through to whatever sits behind the poll.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onLongPressGesture(minimumDuration: Self.longerThanAnybodyWillHold) {
                // Never reached, and nothing would belong here if it were: this gesture is a witness, not an action.
                assertionFailure()
            } onPressingChanged: { pressing in
                aFingerIsOnIt(pressing)
            }
        }

        /// An hour, so the gesture above never fires.
        private static let longerThanAnybodyWillHold: TimeInterval = 3600

    }

    public var body: some View {

        if let viewModel {
            VStack(alignment: .leading, spacing: 0.0) {
                Text(asDrawn(viewModel.question))
                    .fontWeight(.bold)

                Text(viewModel.multipleChoice ? "poll_message_multiple_choice" : "poll_message_no_multiple_choice")
                    .font(.footnote)
                    .foregroundStyle(textColor.opacity(0.75))
                    .padding(.top, 4.0)
                    .padding(.bottom, 8.0)

                ForEach(viewModel.candidates) { candidate in
                    CandidateToggleView(for: candidate,
                                        viewModel: viewModel,
                                        textColor: textColor,
                                        progressColor: progressColor,
                                        asDrawn: asDrawn,
                                        aFingerIsOnIt: { delegate?.aFingerIsOnAnAnswerOfThePoll($0) }) { newValue in
                        updateVote(for: candidate, voted: newValue)
                    }
                    .obvAccessibleComponent()
                    .padding(.vertical, 8.0)
                }

                if let expirationDate = viewModel.expirationDate {
                    if expirationDate <= Date.now {
                        (
                            Text(Image(systemIcon: .clock))
                            + Text(" ") +
                            Text("poll_message_expiration_date_expired")
                        )
                        .padding(.vertical, 8.0)
                        .font(.caption)
                        .foregroundStyle(textColor.opacity(0.75))
                    } else {
                        (
                            Text(Image(systemIcon: .clock))
                            + Text(" ") +
                            Text("poll_message_expiration_date")
                            + Text(" ")
                            + Text(verbatim: viewModel.expirationDateFormatted)
                        )
                        .padding(.vertical, 8.0)
                        .font(.caption)
                        .foregroundStyle(textColor.opacity(0.75))
                    }
                }

                if viewModel.totalNumberOfResponses > 0 {
                    (Text("poll_message_voters_count") + Text(verbatim: " (\(viewModel.totalNumberOfResponses))"))
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.top, 8.0)
                } else {
                    Text("poll_message_voters_count")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.top, 8.0)
                }
            }
            .font(.body)
            .foregroundStyle(textColor)
            // **Behind the poll, and not around it.** Tapping the poll shows the whole of it, and tapping one answer votes for it — two wishes that were competing
            // for the same tap while this gesture sat on the stack *containing* the answers. Which of them won depended on the host: a `Button` wins inside a UIKit
            // hosting controller, and this gesture wins inside a `List` row, where a poll in the SwiftUI discussion screen lives — so voting from the bubble there
            // opened the results instead. Put behind the content, the question does not arise: a tap lands on the front-most view that can take it, which is a
            // `Button` when there is one under the finger and this backdrop everywhere else. `Text` is not hit-testable, so the question, the dates and the counts
            // still lead to the poll.
            .background {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task {
                            try await delegate?.userWantsToDisplayPollView()
                        }
                    }
            }
        } else {
            ProgressView()
                .tint(textColor)
                .padding()
        }
    }

}


// MARK: - What the view asks of whoever shows it

/// What a poll drawn in a bubble asks of its screen.
///
/// Both discussion screens implement it, and neither implements it in a *view*: casting a vote needs the version arithmetic that only the persistence layer can do,
/// and refusing one needs a toast, which is UIKit.
@MainActor
public protocol MessagePollContentViewDelegate: AnyObject {

    /// The reader tapped an answer. `voteSentStatus` says whether the vote may be sent at all — the view decides that, holding the poll's expiry and knowing whether
    /// "None" is chosen — leaving the implementation to send it, or to explain why it did not.
    func userWantsToUpdatePollVote(_ view: MessagePollContentView,
                                   pollCandidateUUID: UUID,
                                   voted: Bool,
                                   voteSentStatus: VoteSentStatus) async throws

    /// The reader tapped the poll itself, and wants the whole of it: the chart, the votes, and who has yet to vote.
    func userWantsToDisplayPollView() async throws

    /// A finger has landed on one of the answers, or has left it.
    ///
    /// **Nothing has to implement this**, and the legacy screen does not: it exists for a screen that draws a poll *inside* something with a press gesture of its
    /// own, and needs to know that the finger belongs to an answer rather than to whatever is around it. Finding 18 of the discussion screen's 2026-08-30 review —
    /// where holding an answer shrank the whole message as though a long press were beginning, which on an answer it never becomes.
    func aFingerIsOnAnAnswerOfThePoll(_ isOnAnAnswer: Bool)

}


public extension MessagePollContentViewDelegate {

    /// Nothing, for the screens that draw a poll with nothing around it to confuse.
    func aFingerIsOnAnAnswerOfThePoll(_ isOnAnAnswer: Bool) {}

}


/// Whether a vote can be sent, decided before anything is asked of the app.
///
/// The message a refusal deserves is **not** here: it is a toast, so it belongs to whoever can show one. This says only what the reason is.
public enum VoteSentStatus: Sendable {
    case canBeSent
    case pollFinished
    case blockedByNone
}


// MARK: - The models

public struct MessagePollViewModel: Sendable, Hashable, Equatable {

    let question: String
    let multipleChoice: Bool
    let candidates: [MessagePollCandidateViewModel]
    let expirationDate: Date?
    let totalNumberOfResponses: Int

    public init(question: String, multipleChoice: Bool, candidates: [MessagePollCandidateViewModel], expirationDate: Date?, totalNumberOfResponses: Int) {
        self.question = question
        self.multipleChoice = multipleChoice
        self.candidates = candidates
        self.expirationDate = expirationDate
        self.totalNumberOfResponses = totalNumberOfResponses
    }

    var expirationDateFormatted: String {
        guard let expirationDate else { return "" }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short

        return dateFormatter.string(from: expirationDate)
    }

}


public struct MessagePollCandidateViewModel: Sendable, Hashable, Equatable, Identifiable {

    let uuid: UUID
    let text: String

    /// Whether the *reader* has chosen this answer. Already resolved by whoever built the model: a reader who chose "None" shows as having chosen nothing else, which
    /// is a rule about votes rather than about drawing.
    let hasVoted: Bool

    /// Out of a hundred, and over *voters* rather than over votes — so the answers of a multiple-choice poll need not add up to a hundred.
    let totalPercent: Double

    public init(uuid: UUID, text: String, hasVoted: Bool, totalPercent: Double) {
        self.uuid = uuid
        self.text = text
        self.hasVoted = hasVoted
        self.totalPercent = totalPercent
    }

    public var id: UUID { uuid }

}


private struct LargerProgressViewStyle: ProgressViewStyle {

    var tintColor: Color
    var backgroundColor: Color

    init(tintColor: Color, backgroundColor: Color) {
        self.tintColor = tintColor
        self.backgroundColor = backgroundColor
    }

    func makeBody(configuration: Configuration) -> some View {
        let fractionCompleted = configuration.fractionCompleted ?? 0

        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(backgroundColor)

                Capsule()
                    .fill(tintColor)
                    .frame(width: fractionCompleted * geometry.size.width)

            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}


#if DEBUG

private let candidatesForPreviews: [MessagePollCandidateViewModel] = [
    .init(uuid: UUID(), text: "15 Juin", hasVoted: true, totalPercent: 8),
    .init(uuid: UUID(), text: "16 Juin", hasVoted: true, totalPercent: 28),
    .init(uuid: UUID(), text: "17 Juin", hasVoted: false, totalPercent: 64),
    .init(uuid: UUID(), text: "18 Juin", hasVoted: false, totalPercent: 0),
]

#Preview {
    MessagePollContentView(viewModel: MessagePollViewModel(question: "Bla bla bla bla bla ?",
                                                           multipleChoice: false,
                                                           candidates: candidatesForPreviews,
                                                           expirationDate: Date.now.addingTimeInterval(3600),
                                                           totalNumberOfResponses: 4),
                           textColor: Color(UIColor.label),
                           progressColor: Color(UIColor.label).opacity(0.5),
                           delegate: nil)
    .padding()
}

#endif

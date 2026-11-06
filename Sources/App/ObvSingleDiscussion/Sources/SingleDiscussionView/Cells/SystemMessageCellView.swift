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
import CoreData
import ObvDesignSystem
import ObvSystemIcon


/// Something the discussion says about itself rather than something anybody wrote: a contact joined a group, a call was missed, the shared settings changed — the
/// legacy `SystemMessageCell`.
///
/// **The sentence is the app's and the drawing is this module's.** There are twenty-odd kinds of these, each with its own wording, and every one of those wordings is
/// already computed by `PersistedMessageSystem.textBodyWithoutTimestamp` — which reads the reader's settings where it has to, as the introductory message does for its
/// long and short forms. Repeating that here would be a second place to get it wrong. What this module decides is what a reader *sees*: a centred pill, white on a
/// colour that says what kind of thing happened, with the date under it.
public struct SystemMessageCellView: View {

    public struct Model: Equatable, Sendable {

        /// What it says, already worded and already localized — `textBodyWithoutTimestamp` on the legacy screen.
        let text: String

        /// What kind of thing happened, which is the colour of the pill. See ``Tint``.
        let tint: Tint

        /// When it happened, drawn under the pill. Nil for the messages the legacy screen gives no date to.
        let timestamp: Date?

        /// The day this message opens, when it is the first of its day, and nil otherwise. A system message sections a discussion exactly as any other message does.
        /// See ``DateSeparatorView``.
        let dateSeparator: Date?

        /// What a change of the discussion's shared settings did, shown under its sentence, and empty for every other kind. See ``Expiration``.
        let expirations: [Expiration]

        /// What tapping this message asks for, and nil for the many that answer nothing. See ``TappableSystemMessage``.
        let tappable: TappableSystemMessage?

        public init(text: String, tint: Tint, timestamp: Date?, dateSeparator: Date?, expirations: [Expiration] = [], tappable: TappableSystemMessage? = nil) {
            self.text = text
            self.tint = tint
            self.timestamp = timestamp
            self.dateSeparator = dateSeparator
            self.expirations = expirations
            self.tappable = tappable
        }

        /// One of the three things a change of the shared settings can have set, drawn under the sentence as an icon and, for two of them, a duration.
        ///
        /// **The icon is this module's and the duration is the app's**: what a flame or an hourglass means is a matter of drawing, while turning seconds into "2
        /// hours" in the reader's language is `DurationFormatter`, which the app owns. The legacy cell builds the same three from `expirationJSON`.
        public enum Expiration: Equatable, Sendable {
            case readOnce
            case visibility(duration: String)
            case existence(duration: String)
        }

        /// The colour of the pill, which the legacy cell picks per category.
        ///
        /// Four cases and not twenty: the categories are the app's business, and what reaches a view is what the reader can tell apart — something about a group or
        /// about safety in green, something to be careful about in orange, something wrong in red, a call in purple.
        public enum Tint: Equatable, Sendable {
            case green
            case orange
            case red
            case purple
        }

    }

    private let model: Model

    /// Which row this is, or **nil** for the sentence the discussion opens with: that one is drawn outside the list's rows, is not a message, and has no context
    /// menu to offer. See ``AMessageThatCanBeLifted``.
    private let cellIdentifier: SingleDiscussionView.CellIdentifier?

    /// What is asked of the app when one of these is tapped. Only the few that answer a tap ever use it.
    private let actions: any SingleDiscussionCellViewActions

    public init(model: Model, cellIdentifier: SingleDiscussionView.CellIdentifier?, actions: any SingleDiscussionCellViewActions) {
        self.model = model
        self.cellIdentifier = cellIdentifier
        self.actions = actions
    }

    public var body: some View {
        // Tappable only when there is something to ask for — a settings change to show, a permission to request, the people this discussion is with. The many that
        // answer nothing stay inert, as they are on the legacy screen. `.buttonStyle(.plain)`, without which a `List` row takes the tap for itself.
        if let tappable = model.tappable {
            Button {
                Task { await actions.userWantsToActOnSystemMessage(tappable) }
            } label: {
                whatTheDiscussionSays
            }
            .buttonStyle(.plain)
        } else {
            whatTheDiscussionSays
        }
    }


    private var whatTheDiscussionSays: some View {
        // Centred, at most 80% of the width, with the date under the pill and pulled to its trailing edge — the arrangement of `SystemMessageCellContentView`, whose
        // main stack is `.trailing` inside a centred, width-limited frame.
        VStack(alignment: .trailing, spacing: MessageBubbleMetrics.gap) {
            // **The cap is here and not inside the pill**, and that is the whole of why — see ``MessageItself``.
            AtMostAFractionOfTheOfferedWidth(fraction: MessageBubbleMetrics.maxWidthRatio) {
                MessageItself(model: model)
            }
            // What the context menu lifts. A system message has one too — a call log offers to call back, and any of them can be deleted. See
            // ``AMessageThatCanBeLifted``.
            .canBeLiftedOutOfTheDiscussion(cellIdentifier, showing: .systemMessage(model), hangingFrom: .centre, dataSource: nil, actions: actions)
            if let timestamp = model.timestamp {
                MessageTimestampView(timestamp: timestamp)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }


    /// The pill, and nothing the cell draws around it — which here means neither the date under it nor the cap on how wide it may be.
    ///
    /// **A view of its own rather than a computed property, because it is drawn twice**: once in the transcript, and once more by ``MessageContextMenuOverlay`` as
    /// the copy that is lifted. See ``ReceivedMessageCellView/MessageItself``, which says the same.
    ///
    /// **The width cap is deliberately outside this, and leaving it in truncated the copy.** A system message is the one thing on this screen whose published
    /// bounds are its *own* size rather than the row's — which is what lets the context menu's card centre on the pill instead of on an invisible full-width box.
    /// The overlay then redraws the copy in a frame of exactly that width, and a proportional layout inside it would take its fraction a **second** time: offered
    /// the row's width R the pill takes W, and offered W it would take 0.8·W. What that looks like is a lifted pill reading "Alice has joined t…". Outside, the
    /// pill is offered W and takes W, which is the width it already had. Nothing proportional may live inside a view that is redrawn at its own measured size.
    struct MessageItself: View {

        let model: SystemMessageCellView.Model

        var body: some View {
            VStack(spacing: MessageBubbleMetrics.gap) {
                Text(verbatim: model.text)
                    .font(.body)
                if let expirations {
                    expirations
                        .font(.callout)
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Color(UIColor.white))
            .padding(.horizontal, MessageBubbleMetrics.horizontalInset)
            .padding(.vertical, MessageBubbleMetrics.verticalInset)
            .background(model.tint.color, in: MessageBubbleMetrics.shape)
        }


        /// What a change of the shared settings set, as one line of text under the sentence: an icon per thing set, and the duration beside two of them.
        ///
        /// **One `Text` built by concatenation**, and not a row of views, because that is what it is: the legacy cell builds a single attributed string with the
        /// symbols as attachments, joined by four spaces, and lets it centre and wrap as one label. Symbols inside a `Text` also keep the line exactly one line box
        /// tall — see ``MessageEditedBadgeView``.
        private var expirations: Text? {
            var line: Text?
            for expiration in model.expirations {
                let piece: Text = switch expiration {
                case .readOnce:
                    Text(Image(systemIcon: .flameFill))
                case .visibility(duration: let duration):
                    Text(Image(systemIcon: .eyes)) + Text(verbatim: " \(duration)")
                case .existence(duration: let duration):
                    Text(Image(systemIcon: .timer)) + Text(verbatim: " \(duration)")
                }
                line = line.map({ $0 + Text(verbatim: SystemMessageCellView.gapBetweenTheExpirations) + piece }) ?? piece
            }
            return line
        }

    }


    /// The four spaces the legacy cell joins its expiration labels with.
    private static let gapBetweenTheExpirations = "    "

}


/// A system message the reader may tap, and what tapping it asks for.
///
/// Most of them answer nothing — a contact joined a group, a message was wiped remotely — and carry none of this. The few that do lead somewhere the app owns: a
/// screen, a permission, a settings page.
public struct TappableSystemMessage: Equatable, Sendable {

    /// Which message was tapped. Two of the requests below need it to find the discussion it belongs to.
    public let identifier: Identifier

    /// What the reader is asking for by tapping it.
    public let request: Request

    public init(identifier: Identifier, request: Request) {
        self.identifier = identifier
        self.request = request
    }

    public enum Identifier: Hashable, Sendable {
        /// The object ID of a `PersistedMessageSystem`, enforced by the data source — this module knows nothing of the persistence layer.
        case objectID(_ objectID: NSManagedObjectID)
        case forPreview(_ uuid: UUID)
    }

    public enum Request: Equatable, Sendable {

        /// The message says the shared settings changed; the reader wants to see what they now are.
        case showTheSharedSettings

        /// The message says a call was refused because Olvid had no permission to use the microphone; the reader wants to grant it.
        case askForPermissionToUseTheMicrophone

        /// The message says a call was refused because this device is set not to take them; the reader wants that setting.
        case showTheSettingsForCalls

        /// The message says who is in the group now; the reader wants the group itself — the legacy screen answers this one by behaving as if the title had been
        /// tapped.
        case showWhoTheDiscussionIsWith

    }

}


extension SystemMessageCellView.Model.Tint {

    var color: Color {
        switch self {
        case .green: return Color(AppTheme.shared.colorScheme.green)
        case .orange: return Color(AppTheme.shared.colorScheme.orange)
        case .red: return Color(AppTheme.shared.colorScheme.red)
        case .purple: return Color(AppTheme.shared.colorScheme.purple)
        }
    }

}


#if DEBUG

#Preview {
    VStack(spacing: 8) {
        ForEach(Array(SystemMessageCellView.Model.sampleData.enumerated()), id: \.offset) { _, model in
            SystemMessageCellView(model: model, cellIdentifier: nil, actions: singleDiscussionCellViewDataSourceForPreviews)
        }
    }
    .padding()
}

#endif

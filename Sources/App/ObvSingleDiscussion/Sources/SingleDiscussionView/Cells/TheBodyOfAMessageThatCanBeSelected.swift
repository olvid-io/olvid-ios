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

#if targetEnvironment(macCatalyst)

import SwiftUI
import UIKit


/// The body of a message, drawn by a `UITextView` so that a reader on a Mac can **select it**, Catalyst only.
///
/// **Why it is not one line.** The step was scoped around `.textSelection(.enabled)`, and **that modifier is inert in this app on Catalyst**: measured on the
/// body, on a plain `Text` in a row beside the message, and on one in an overlay outside the `List` altogether — three positions, no selection from a drag
/// and none from a double-click. It is not the `List` and not this screen's gestures. The control that closes it is the shipping screen: **legacy's
/// `TextBubble` selects by dragging in this very app**, being a `UITextView` with `isSelectable = true`. A text view carries its own text interaction; a
/// SwiftUI `Text` has only what it is given, and here it is given nothing.
///
/// **A drop-in for the `Text` it replaces, not a transcription of legacy's metrics.** The bubble, its corners, its padding and the width cap of
/// ``AtMostAFractionOfTheOfferedWidth`` all stay SwiftUI and stay where they are — this sits *inside* them. That is why `textContainerInset` and
/// `lineFragmentPadding` are both zeroed: a text view insets its text by 5pt of line-fragment padding by default, which legacy absorbs into its own
/// constraints and which here would re-wrap every message on the platform. **Nothing about the transcript may change.**
///
/// **iOS and iPadOS never see this**, the whole file being behind `targetEnvironment(macCatalyst)`, which is what makes the step affordable: only one
/// platform's arbitration has to be re-walked.
///
/// **The taps are legacy's arrangement, and they do not settle the question that is open.** Legacy disables the text view's own single- and double-tap
/// recognisers and leaves only `UITextInteractionNameLinkTap`, transcribed below. **That governs touch, not the mouse.** On a Mac, double-clicking a word in
/// a bubble selects it whatever UIKit's recognisers are doing — legacy's own `hitTest` comment says why: *"the macOS NSTextView layer … processes mouseDown
/// independently"*.
///
/// **The collision was real and is settled: on a Mac, a double-click selects a word.** Decided 2026-08-30, and it is what already ships — Step 54 put the
/// double tap behind `#if !targetEnvironment(macCatalyst)`, withdrawing 22a's react and 56's edit on that platform only. A Mac reader loses nothing they
/// cannot reach: the menu offers both, a right-click away. **The lesson stands even though the question closed**: the platform's behaviour was never ours to
/// choose by switching a recogniser off, and pretending otherwise is what the taps above must not do.
struct TheBodyOfAMessageThatCanBeSelected: UIViewRepresentable {

    /// The body as it is to be drawn — already carrying its block intents, its links and mentions, and the search highlight. Styled in **both**
    /// scopes; see ``AttributedString/inTheAttributesAUITextViewReads(colour:)`` for why that matters here.
    let body: AttributedString

    let style: MessageBubbleStyle

    /// What a tap on a link leads to. Not `openURL`: the app decides what a URL means, an Olvid link being something it opens itself rather than
    /// handing to a browser — which is what the SwiftUI branch arranges with an `OpenURLAction` and what this arranges through the delegate.
    let actions: any SingleDiscussionCellViewActions

    func makeUIView(context: Context) -> AViewThatKeepsTheSecondaryClickFromTheText {

        let textView = ATextViewWhoseSelectionCanBeSuppressed()

        textView.isEditable = false
        // **`true` even though nothing here is edited**, and legacy's comment says the second reason: it is what the data detector needs.
        textView.isSelectable = true
        // So the view reports the height its text needs and the row can size itself around it, rather than scrolling inside a box.
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        // Both, and both matter — see the note above about being a drop-in. Legacy zeroes only the first because its own constraints absorb the rest.
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        // Let the attributed string decide what a link looks like, as legacy does: ours are already coloured by `withLinksAndMentionsEmphasised`.
        textView.linkTextAttributes = [:]
        textView.adjustsFontForContentSizeCategory = true
        textView.tintColor = Self.theColourOfTheSelection(style)

        // A text view is happy to be any width; the bubble around it is not. Without this it fights the width the cap gives it.
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        textView.delegate = context.coordinator

        // **Legacy's arrangement, and the whole of how selection coexists with this screen's gestures.** Everything the text view would do with a tap
        // is switched off except following a link; the press, the double tap and the ticks of select mode are then untouched, and a drag still selects.
        Self.leavesOnlyTheLinkTapEnabled(on: textView)

        return AViewThatKeepsTheSecondaryClickFromTheText(around: textView)

    }


    func updateUIView(_ view: AViewThatKeepsTheSecondaryClickFromTheText, context: Context) {
        let textView = view.theText
        context.coordinator.actions = actions
        let attributed = NSAttributedString(body.inTheAttributesAUITextViewReads(colour: Self.theColourOfTheText(style)))
        // Compared before being written: `attributedText` re-lays the text out, and this runs on every update of a cell that is otherwise unchanged.
        if textView.attributedText != attributed {
            textView.attributedText = attributed
        }
        textView.tintColor = Self.theColourOfTheSelection(style)
    }


    /// The height this body needs at the width the bubble is giving it.
    ///
    /// **Answered by the text view rather than by an intrinsic size**, which is what makes it behave inside a self-sizing row: the width comes from the
    /// proposal, and the height is whatever the text needs at that width. This screen has already paid for getting heights
    /// wrong in a `List` — a body losing a whole line to a *stale* proposal, and half a point of change discarding an entire layout — so this must
    /// never answer anything but the height its text truly occupies.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: AViewThatKeepsTheSecondaryClickFromTheText, context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingCompressedSize.width
        guard width > 0, width < .greatestFiniteMagnitude else { return nil }
        let fits = view.theText.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: min(fits.width, width), height: fits.height)
    }


    func makeCoordinator() -> TheLinksOfASelectableBody {
        TheLinksOfASelectableBody(actions: actions)
    }


    // MARK: What the text view is allowed to do with a touch

    /// Disables every tap recogniser the text view installs for itself except the one that follows a link — **legacy's own lines**, at
    /// `TextBubble.swift:183`.
    ///
    /// **What it does not do is govern the mouse.** These are UIKit's recognisers; on Catalyst the Mac's own text layer answers a click independently,
    /// which is why a double-click still selects a word on the shipping screen. This is transcribed because legacy has it and because it is what keeps
    /// a *touch* from being taken by the text — and because a recogniser installed later, which a text view does add as it is configured and moved into
    /// a window, is not caught by a single pass at construction. That is a known limit of copying this, not a claim that it is airtight.
    ///
    /// The recognisers are found by name, which is as brittle as it sounds and is what legacy does: `UITextInteractionNameLinkTap` is not API. If a
    /// future SDK renames it, links stop being tappable inside a bubble — noisy enough to be noticed, and it fails towards *nothing happens* rather
    /// than towards a wrong action.
    private static func leavesOnlyTheLinkTapEnabled(on textView: UITextView) {

        let taps = (textView.gestureRecognizers ?? []).compactMap { $0 as? UITapGestureRecognizer }
        for tap in taps where tap.numberOfTapsRequired == 1 || tap.numberOfTapsRequired == 2 {
            tap.isEnabled = false
        }
        taps.first(where: { $0.name == "UITextInteractionNameLinkTap" })?.isEnabled = true

        // **And its long presses, which is not legacy's line but is needed here** — walked on a Mac, 2026-08-26: with these left alone, the menu of Step 21
        // appeared only once the button was **released**, where everywhere else on this screen it opens while the press is still held. The text view's own
        // long press is what delays it: our menu is a *SwiftUI* gesture and takes no part in UIKit's arbitration, so it cannot win a race it is not in —
        // which is the same fact Step 41 turned on, met from a third side.
        //
        // Safe on this platform, and only on this platform: what selects text with a **mouse** is the Mac's own text layer, not these recognisers, which
        // exist for a finger. Nothing here is compiled anywhere a finger can reach.
        for press in (textView.gestureRecognizers ?? []).compactMap({ $0 as? UILongPressGestureRecognizer }) {
            press.isEnabled = false
        }

    }


    // MARK: The two colours

    /// The colour of the text itself, which the attributed string carries per run and the view carries as a default.
    private static func theColourOfTheText(_ style: MessageBubbleStyle) -> UIColor {
        switch style {
        case .sent: return .white
        case .received: return .label
        }
    }


    /// What the selection highlight is drawn in — `tintColor`, and it has to adapt in **both** directions.
    ///
    /// Legacy's reasoning, kept because it is not obvious and was clearly arrived at by looking: on a message **sent**, the bubble is the Olvid blue,
    /// which is light in light mode and dark in dark mode, so the highlight goes dark-on-light and light-on-dark. On one **received**, the bubble is a
    /// translucent fill, where `systemBlue` reads in light mode and disappears against the dark one, so it becomes white there.
    private static func theColourOfTheSelection(_ style: MessageBubbleStyle) -> UIColor {
        switch style {
        case .sent:
            return UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.7, alpha: 1) : .white }
        case .received:
            return UIColor { $0.userInterfaceStyle == .dark ? .white : .systemBlue }
        }
    }

}


// MARK: - Giving the secondary click back to the message

/// A text view that lets a **secondary click** reach the message when there is nothing selected — see ``TheBodyOfAMessageThatCanBeSelected``.
///
/// **Legacy's two-layer defence, transcribed**, from `TextBubble.hitTest(_:with:)`. Without it, right-clicking a bubble on a Mac selects the word under
/// the pointer before the menu opens, and the word stays selected after it is dismissed — measured 2026-08-26, and the reader's verdict was *"not
/// great, but the right click must show the menu"*.
///
/// Both layers are needed and legacy says why: the macOS text layer **processes the click independently** of UIKit, so suppressing the selection is not
/// enough on its own, and refusing the hit is not enough either.
///
/// - **Suppress the selection**, so the Mac layer cannot set one behind UIKit's back. Held for one turn of the run loop, which is all the click takes.
/// - **Refuse the hit**, so the event walks up to the cell — where Step 55's `UIContextMenuInteraction` is waiting, and the menu opens as it does
///   anywhere else on a message.
///
/// **And only when nothing is selected.** With a selection, the click belongs to the text: the system's own menu — Copy, Look Up, Share — is the right
/// answer, and taking it away to show ours would make selecting text pointless.
final class AViewThatKeepsTheSecondaryClickFromTheText: UIView {

    let theText: ATextViewWhoseSelectionCanBeSuppressed

    init(around textView: ATextViewWhoseSelectionCanBeSuppressed) {
        self.theText = textView
        super.init(frame: .zero)
        addSubview(textView)
        textView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        theText.sizeThatFits(size)
    }

    /// **The whole reason this container exists**, and the first attempt put it on the text view itself, which is too late.
    ///
    /// Measured on a Mac, 2026-08-26: with the override on the text view, a right-click still selected the word under the pointer and still opened the
    /// **system's** text menu — even over bare bubble with no character beneath it. By the time a view's own `hitTest` is consulted, the Mac's text layer
    /// has already claimed the click. Legacy hangs the same override on `TextBubble`, the view *containing* its text view, and that is the difference: the
    /// event has to be taken **before it can descend**.
    ///
    /// Two layers, both of them legacy's, and it says why they are both needed — the macOS layer *"processes mouseDown independently"*:
    ///
    /// - **Suppress the selection**, so that layer cannot set one behind UIKit's back. For one turn of the run loop, which is all a click takes.
    /// - **Return `self`**, so the hit lands on this view rather than on the text — and this view is inside the row's cell, where Step 55's
    ///   `UIContextMenuInteraction` is waiting. The menu then opens exactly as it does on any other part of a message.
    ///
    /// **Only when nothing is selected.** With a selection the click belongs to the text, and the system's own menu — Copy, Look Up, Share — is the right
    /// answer to it; taking that away would make selecting text pointless.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {

        guard let event, event.buttonMask.contains(.secondary) else {
            return super.hitTest(point, with: event)
        }

        guard self.point(inside: point, with: event) else { return nil }

        guard theText.selectedRange.length == 0 else {
            return super.hitTest(point, with: event)
        }

        theText.theSelectionIsBeingSuppressed = true
        DispatchQueue.main.async { [weak self] in
            self?.theText.theSelectionIsBeingSuppressed = false
        }

        return self

    }

}


/// The text view itself, which does nothing of its own accord except refuse to have a selection set while
/// ``AViewThatKeepsTheSecondaryClickFromTheText`` is sending a secondary click past it.
final class ATextViewWhoseSelectionCanBeSuppressed: UITextView {

    /// Set for the instant a secondary click is being routed past this view — see the container above, which is the only thing that writes it.
    fileprivate var theSelectionIsBeingSuppressed = false

    override var selectedRange: NSRange {
        get { super.selectedRange }
        set {
            guard !theSelectionIsBeingSuppressed else { return }
            super.selectedRange = newValue
        }
    }

}


// MARK: - Following a link

/// What happens when a link inside a message is tapped — see ``TheBodyOfAMessageThatCanBeSelected``.
///
/// **The app decides what a URL means**, so nothing here is handed to the system: an Olvid invitation is not an ordinary page. The SwiftUI branch says
/// the same thing through an `OpenURLAction`; this says it through the delegate, and the two must not come to disagree.
final class TheLinksOfASelectableBody: NSObject, UITextViewDelegate {

    fileprivate var actions: any SingleDiscussionCellViewActions

    fileprivate init(actions: any SingleDiscussionCellViewActions) {
        self.actions = actions
    }

    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        let actions = self.actions
        Task { await actions.userWantsToOpenURLFromAMessage(URL) }
        return false
    }

}


// MARK: - The attributes a text view can actually read

extension AttributedString {

    /// The same string, with what this screen's styling puts in **SwiftUI's** attribute scope repeated in **UIKit's**.
    ///
    /// **`NSAttributedString(_:)` drops what it cannot map**, and SwiftUI's `foregroundColor`, `backgroundColor`, `underlineStyle` and `font` are
    /// exactly that — so a body converted without this arrives in the text view as unstyled text: no link colour, no bold mention, no search
    /// highlight. Legacy never meets it, writing `source.uiKit.foregroundColor` from the start.
    ///
    /// **Repeated rather than replaced, and that is the point.** The same `AttributedString` is drawn by a `Text` on every other platform and by a
    /// `UITextView` here, so it must carry both accounts of itself; writing only the UIKit one would leave the SwiftUI rendering bare. One definition,
    /// two readers — the same reasoning that has `MessageContextMenuOverlay` draw the *very same views* the cell draws rather than a copy of them.
    ///
    /// The base font and colour are set for the whole string first, as legacy does, and per-run styling then overrides where it applies.
    func inTheAttributesAUITextViewReads(colour: UIColor) -> AttributedString {

        var result = self

        result.uiKit.font = UIFont.preferredFont(forTextStyle: .body)
        result.uiKit.foregroundColor = colour

        for run in result.runs {
            let range = run.range
            if let swiftUIColour = run.foregroundColor {
                result[range].uiKit.foregroundColor = UIColor(swiftUIColour)
            }
            if let background = run.backgroundColor {
                result[range].uiKit.backgroundColor = UIColor(background)
            }
            if run.underlineStyle != nil {
                result[range].uiKit.underlineStyle = .single
                // Legacy underlines a link in the text's own colour rather than the system's.
                if let swiftUIColour = run.foregroundColor {
                    result[range].uiKit.underlineColor = UIColor(swiftUIColour)
                }
            }
            // A mention is the one run this screen makes bold — see `MentionInAMessage`.
            if run.font != nil {
                let descriptor = UIFont.preferredFont(forTextStyle: .body).fontDescriptor
                if let bold = descriptor.withSymbolicTraits(.traitBold) {
                    result[range].uiKit.font = UIFont(descriptor: bold, size: 0)
                }
            }
        }

        return result

    }

}

#endif

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
import MessageUI
import ObvUI
import ObvDesignSystem
import ObvSystemIcon
import ObvAppCoreConstants
import OlvidUtils


/// Where the inbox maintenance is started, and what it is doing while it runs.
///
/// All of it is localized, figures included, for the reason ``ObvInboxDrainReport/groupsForDisplay`` gives: the reader is an ordinary user who was asked
/// to tap a button and wait, and a report arriving in French is still readable by us.
struct InboxMaintenanceView: View {

    @ObservedObject var model: InboxMaintenanceModel

    @State private var isEmailComposerViewPresented = false
    @State private var hudCategory: HUDView.Category? = nil

    /// The report of the run that has just ended, or nil while one is running or none has been asked for.
    ///
    /// Read from the state rather than carried in a `@State` of its own, so that there is one copy of it and the mail cannot be built from a stale one.
    private var finishedReport: ObvInboxDrainReport? {
        guard case .finished(let report) = model.state else { return nil }
        return report
    }

    var body: some View {
        ZStack {
            Form {

                Section {
                    Text(String(localized: "Olvid keeps the messages it receives in an inbox until the app has stored them and the server has been told it can let them go. It normally clears that inbox out a little at a time, while your device is charging. On a device that has received a very large number of messages, that can fall a long way behind. This does the work now."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                switch model.state {

                case .notStarted:

                    Section {
                        Button {
                            model.userWantsToStartTheInboxMaintenance()
                        } label: {
                            Label("Catch up now", systemIcon: .playFill)
                        }
                    } footer: {
                        // Both halves of this are things the reader has to be told *before* they tap, not after: the run ends if they leave, and a run of this
                        // length on battery is worth warning about. Measured: ten thousand messages took fourteen and a half minutes.
                        Text(String(localized: "This can take several minutes, or much longer if a great many messages are waiting. Keep this screen open while it runs — leaving it stops the work — and plug your device in if you can."))
                    }

                case .running:

                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                ProgressView()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(localized: "Catching up…"))
                                    // The bar completes once for each phase, and without this the second start looks like the first having failed.
                                    Text(model.whatIsHappening.localizedDescription)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            if let progress = model.progress {
                                // One bar, always determinate, always rising. An indeterminate bar draws an empty track, which cannot be told from a
                                // determinate bar stuck at nought, and a reader watched one for three minutes and concluded the run had stalled. No bar
                                // at all rather than a bar at nought: a run has no position until the app has stored its first message of the backlog.
                                if let fraction = progress.fraction {
                                    ProgressView(value: fraction)
                                        // Eased across the gap between two readings rather than stepping once a second. Slightly shorter than the refresh
                                        // interval, so it has settled before the next figure arrives.
                                        .animation(.easeInOut(duration: 0.8), value: fraction)
                                }
                                // The rolling transition belongs on the numbers only: `numericText` animates a view's whole text, so on *"1,234 of 5,678"*
                                // it would take the words with it. Each figure is therefore its own `Text`, and the order of words and figures comes from
                                // the translation, since Japanese and Korean put the total first. A `Text` cannot carry a transition inside a `+`
                                // concatenation, hence the stack; the baseline alignment keeps a number level with prose that has wrapped.
                                let pieces = Self.piecesOfTheCount(progress: progress)
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                                        switch piece {
                                        case .words(let words):
                                            Text(verbatim: words)
                                        case .count(let count):
                                            Text(verbatim: count)
                                                // Keyed on the figure itself, so each number animates when *it* changes: keyed on `done` alone, a total that
                                                // moved while the count stood still would jump rather than roll.
                                                .contentTransition(.numericText())
                                                .animation(.easeInOut(duration: 0.8), value: count)
                                        }
                                    }
                                }
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                // Not decoration: without it the text re-measures as the digits change and the whole line twitches sideways, which is far more
                                // distracting than the transition is pleasing.
                                .monospacedDigit()
                            }
                        }
                    } header: {
                        Text(String(localized: "Progress"))
                    } footer: {
                        // Said out loud, because a bar that sits around halfway for minutes invites the reader to think it is stuck: the server does not
                        // answer *how many are waiting*, only *was that the last page*, so until it says yes there is no total to name and the count is the
                        // figure that means something.
                        Text(String(localized: "Olvid cannot tell how many messages are waiting until the server has sent the last of them, so there is no total to show until then. Keep this screen open — leaving it stops the work, and whatever has been done so far is kept."))
                    }

                    if !model.figures.isEmpty {
                        Section(String(localized: "Details")) {
                            ForEach(model.figures) { figure in
                                FigureRow(figure: figure)
                            }
                        }
                    }

                case .finished(let report):

                    Section {
                        Label {
                            // `verbatim`, because the outcome has already been localized by the report and must not be looked up a second time as a key.
                            Text(verbatim: report.outcomeForDisplay)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemIcon: .checkmarkCircleFill)
                        }
                    }

                    // Above the figures rather than below them: the report is six groups long, and a button after a page of scrolling is a button nobody
                    // presses. What is sent is the whole report.
                    Section {
                        if ObvEmailComposerView.canSendEmail() {
                            Button {
                                isEmailComposerViewPresented = true
                            } label: {
                                Label("Send this report by email", systemIcon: .envelope)
                            }
                        } else {
                            // No mail account on this device, so there is no composer to open — which is also why this is invisible on a simulator. Give the
                            // address instead, as the engine diagnostics screen does, rather than leaving the reader with no way to reach us.
                            HStack {
                                Text(verbatim: ObvAppCoreConstants.toEmailForSendingInitializationFailureErrorMessage)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = report.textForSharing
                                    showThenHideHUD(.checkmark)
                                } label: {
                                    Image(systemIcon: .docOnDoc)
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        // Deliberately the same sentence the engine diagnostics screen uses, rather than a new one saying the same thing: it is already
                        // translated into all thirteen languages, and the promise it makes is identical.
                        Text(String(localized: "These figures describe the state of this device only. They contain no messages, no file names and no contacts."))
                    }

                    ForEach(report.groupsForDisplay) { group in
                        Section(group.title) {
                            ForEach(group.figures) { figure in
                                FigureRow(figure: figure)
                            }
                        }
                    }

                    Section {
                        Button {
                            model.userWantsToStartTheInboxMaintenance()
                        } label: {
                            Label("Run it again", systemIcon: .playFill)
                        }
                    }

                }

            }
            // Above the form so that it is not clipped by it, as the report screen and the diagnostics screen both do.
            if let hudCategory {
                HUDView(category: hudCategory)
                    .zIndex(1)
            }
        }
        .onDisappear {
            // **Said by the view rather than by the hosting controller**, so that the behaviour lives with the thing that knows it happened. It is not the
            // whole story on its own — `onDisappear` does not fire when the app is backgrounded — which is why the controller also listens for that.
            model.theScreenIsGoingAway()
        }
        .obvEmailComposerView(isPresented: $isEmailComposerViewPresented, model: emailModel, delegate: self)
    }


    private var emailModel: ObvEmailComposerView.Model {
        .init(subject: "Olvid inbox maintenance report",
              toRecipients: [ObvAppCoreConstants.toEmailForSendingInitializationFailureErrorMessage],
              messageBody: [
                "Olvid version: \(ObvAppCoreConstants.fullVersion)",
                "Device model: \(UIDevice.current.preciseModel)",
                "System: \(UIDevice.current.systemVersion)",
                "",
                // Empty rather than absent when there is no report: the button that presents this only exists in the finished state, so this cannot be
                // reached without one — and an empty body is a better failure than a crash if that ever stops being true.
                finishedReport?.textForSharing ?? "",
              ].joined(separator: "\n"))
    }


    @MainActor
    private func showThenHideHUD(_ category: HUDView.Category) {
        Task {
            hudCategory = category
            try? await Task.sleep(seconds: 1)
            hudCategory = nil
        }
    }


    // MARK: The count, in the order the reader's language puts it

    /// One run of the progress caption: either words, which never animate, or a figure, which does.
    fileprivate enum CountPiece {
        case words(String)
        case count(String)
    }


    /// The caption broken into the pieces the translation asks for, in its order.
    ///
    /// Two sentences, because there are two things to say: a count against a total once the server has finished, and a count on its own while it has not.
    private static func piecesOfTheCount(progress: InboxMaintenanceModel.ProgressSnapshot) -> [CountPiece] {
        if let total = progress.total {
            return pieces(ofLocalizedFormat: String(localized: "%1$@ of %2$@",
                                                    comment: "How far the catch-up has got, as a count against a total, e.g. '1,234 of 5,678'. Both are numbers and either may come first."),
                          filling: [progress.done.formatted(), total.formatted()])
        } else {
            // No total named while the server may still have pages, because there is not an honest one — but the count moves every second, and it is the
            // figure that actually tells a reader the run is alive.
            return pieces(ofLocalizedFormat: String(localized: "%@ stored so far — more still arriving",
                                                    comment: "How far the catch-up has got when the total is not yet known. The placeholder is a number."),
                          filling: [progress.done.formatted()])
        }
    }


    /// Splits a localized format into its words and its filled placeholders, in the order that translation put them, so the translator stays in charge of
    /// the order and the animation stays on the numbers.
    ///
    /// Understands `%@` and `%1$@`. A placeholder naming a position nobody filled becomes empty rather than crashing, since a translation cannot be trusted
    /// to be well-formed.
    private static func pieces(ofLocalizedFormat format: String, filling counts: [String]) -> [CountPiece] {

        var pieces = [CountPiece]()
        var startOfTheWords = format.startIndex
        var nextUnnumberedPosition = 0

        // Extended delimiters, so that the `/` of a bare regex literal cannot be read as division — which the compiler manages and the indexer does not,
        // leaving the file marked with errors it does not have.
        for placeholder in format.matches(of: #/%(?:([0-9]+)\$)?@/#) {

            let words = String(format[startOfTheWords..<placeholder.range.lowerBound])
            if !words.isEmpty { pieces.append(.words(words)) }

            let position: Int
            if let numbered = placeholder.output.1, let parsed = Int(numbered) {
                position = parsed - 1
            } else {
                position = nextUnnumberedPosition
                nextUnnumberedPosition += 1
            }
            pieces.append(.count(counts.indices.contains(position) ? counts[position] : ""))

            startOfTheWords = placeholder.range.upperBound

        }

        let remainingWords = String(format[startOfTheWords...])
        if !remainingWords.isEmpty { pieces.append(.words(remainingWords)) }

        return pieces

    }

}


// MARK: - Implementing ObvEmailComposerViewDelegate

extension InboxMaintenanceView: ObvEmailComposerViewDelegate {

    func emailComposerViewDidFinish(_ view: ObvEmailComposerView, result: Result<MFMailComposeResult, any Error>) {
        isEmailComposerViewPresented = false
        let hudCategoryToShow: HUDView.Category
        switch result {
        case .success(.cancelled):
            return
        case .success:
            hudCategoryToShow = .checkmark
        case .failure:
            hudCategoryToShow = .xmark
        }
        Task {
            // Let the mail composer sheet finish its dismissal animation before showing the HUD
            try? await Task.sleep(seconds: 0.5)
            showThenHideHUD(hudCategoryToShow)
        }
    }

}


/// One label and its value. A row of its own so that the running and finished states cannot drift apart.
private struct FigureRow: View {

    let figure: ObvInboxDrainReport.Figure

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(figure.label)
            Text(figure.value)
                .font(.footnote)
                .foregroundStyle(.secondary)
                // Several of these are sentences rather than numbers, and a value that matters must not be silently truncated.
                .fixedSize(horizontal: false, vertical: true)
                // Most of these are counts that change once a second while a run is going, and they roll for the same reason the one above does. The few
                // that are words rather than numbers — *Yes*, *No* — simply cross-fade, which is what this transition does when it finds nothing to count.
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.8), value: figure.value)
        }
    }

}

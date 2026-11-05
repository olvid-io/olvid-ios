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
import ObvTypes
import ObvUI
import ObvDesignSystem
import ObvSystemIcon
import ObvAppCoreConstants
import OlvidUtils


protocol EngineDiagnosticsViewActionsDelegate: AnyObject {
    @MainActor func getAsyncStreamOfEngineDiagnostics() throws -> AsyncStream<ObvEngineDiagnostic>
    @MainActor func getLastInboxDrainReport() -> ObvInboxDrainReport?
}


/// Shows what the engine can say about the state of its own inbox, and lets the reader send it to us.
///
/// This screen exists because there are faults we cannot otherwise see: two readers reporting a stuck attachment and a message that takes ten seconds to
/// arrive have between them half a dozen possible causes, and nothing on the device distinguishes them. The figures are streamed rather than fetched in one
/// go, so the screen fills as they are found — on a device holding a large backlog that is the difference between visible progress and a spinner.
struct EngineDiagnosticsView: View {

    let actions: EngineDiagnosticsViewActionsDelegate

    @State private var diagnostics: [ObvEngineDiagnostic] = []
    /// What the last drain of the engine's inbox achieved. Read from the app's own storage, not from the engine's stream: the engine knows nothing about a
    /// background task having run, and the figures below are the app's account of it.
    @State private var lastInboxDrainReport: ObvInboxDrainReport?
    @State private var isMeasuring = false
    @State private var isEmailComposerViewPresented = false
    /// What a reader asked for while the figures were still being measured. Non-nil presents the alert, which says why nothing happened and
    /// offers to do that one thing anyway. The buttons stay live rather than disabled, because a disabled button explains nothing, and a report
    /// sent early once lost the rows that would have classified a reader's backlog.
    @State private var actionRefusedWhileMeasuring: ActionOnTheFigures?

    private enum ActionOnTheFigures {
        case copy
        case mail
    }
    @State private var hudCategory: HUDView.Category? = nil

    var body: some View {
        ZStack {
            Form {

                ForEach(groups, id: \.section) { group in
                    Section(group.section.rawValue) {
                        // Identified by label rather than by position: every figure's label is unique within a measurement and stays the same across one,
                        // so a row keeps its identity when a refresh replaces its value.
                        ForEach(group.diagnostics, id: \.label) { diagnostic in
                            EngineDiagnosticRowView(diagnostic: diagnostic)
                        }
                    }
                }

                // Its own Section rather than more `ObvEngineDiagnostic` cases: those are what the *engine* can say about itself, and this is the app's
                // account of a background task it ran. Not gated on `showExperimentalFeature`: the inbox maintenance is something every reader can be
                // asked to run, and a report they can see on one screen and not send from this one invites "it said it had finished" with nothing to
                // check against.
                Section(String(localized: "Last inbox maintenance run")) {
                    if let lastInboxDrainReport {
                        ForEach(lastInboxDrainReport.summaryForDisplay) { figure in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(figure.label)
                                Text(figure.value)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        Text(String(localized: "The inbox has not been cleared out on this device yet."))
                            .foregroundStyle(.secondary)
                    }
                }

                if isMeasuring {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(String(localized: "Measuring…"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    if ObvEmailComposerView.canSendEmail() {
                        Button {
                            guard !isMeasuring else { actionRefusedWhileMeasuring = .mail; return }
                            perform(.mail)
                        } label: {
                            Label("Send these figures by email", systemIcon: .envelope)
                        }
                    } else {
                        // No mail account is set up on this device, so there is no composer to open — which is also why this button is invisible on a
                        // simulator. Give the address instead, as the subscription screen does, rather than leaving the reader with no way to reach us.
                        HStack {
                            Text(verbatim: ObvAppCoreConstants.toEmailForSendingInitializationFailureErrorMessage)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button {
                                UIPasteboard.general.string = ObvAppCoreConstants.toEmailForSendingInitializationFailureErrorMessage
                                showThenHideHUD(.checkmark)
                            } label: {
                                Image(systemIcon: .docOnDoc)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(String(localized: "These figures describe the state of this device only. They contain no messages, no file names and no contacts."))
                }

            }
            if let hudCategory {
                HUDView(category: hudCategory)
                    .zIndex(1)
            }
        }
        .task { await measure() }
        .refreshable { await measure() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard !isMeasuring else { actionRefusedWhileMeasuring = .copy; return }
                    perform(.copy)
                } label: {
                    Image(systemIcon: .docOnDoc)
                }
                .accessibilityLabel(Text(String(localized: "Copy these figures")))
            }
        }
        .alert(Text(String(localized: "The figures are not complete yet")),
               isPresented: Binding(get: { actionRefusedWhileMeasuring != nil }, set: { if !$0 { actionRefusedWhileMeasuring = nil } }),
               presenting: actionRefusedWhileMeasuring) { action in
            Button(String(localized: "Wait"), role: .cancel) {}
            // The way out for a reader whose measuring never ends. The report then says it was taken early, so nobody reads it as complete.
            Button(action == .copy ? String(localized: "Copy anyway") : String(localized: "Send anyway")) { perform(action) }
        } message: { _ in
            Text(String(localized: "Olvid is still measuring. Please wait until “Measuring…” has disappeared, then send the figures: a report sent now would be missing the ones that matter most."))
        }
        .obvEmailComposerView(isPresented: $isEmailComposerViewPresented, model: emailModel, delegate: self)
    }


    private func perform(_ action: ActionOnTheFigures) {
        switch action {
        case .copy:
            UIPasteboard.general.string = report
            showThenHideHUD(.checkmark)
        case .mail:
            isEmailComposerViewPresented = true
        }
    }


    /// The figures grouped under their headings, in the order the engine sent them.
    ///
    /// No sorting: the engine emits in a fixed order and each heading's figures arrive together, so walking the array is enough — and it keeps the screen
    /// and the emailed report in the same order without either of them having to know what that order is.
    private var groups: [(section: ObvEngineDiagnostic.Section, diagnostics: [ObvEngineDiagnostic])] {

        // **Gathered by section, not by consecutive run.** A `.couldNotCompute` is emitted where the failure happened, interleaved with what succeeded
        // around it, so two failures far apart produced two `Could not be computed` groups — a duplicate id for the `ForEach` below, which keys on the
        // section. SwiftUI drops one, so the screen lost a failure row on the device that had two of them, which is the device this panel is for.
        //
        // Sections keep the order they were **first** seen in, so emission order still decides the layout — the promise made on ``ObvEngineDiagnostic``. A
        // late failure joins the earlier ones rather than opening a section of its own.
        var orderOfFirstAppearance: [ObvEngineDiagnostic.Section] = []
        var diagnosticsPerSection: [ObvEngineDiagnostic.Section: [ObvEngineDiagnostic]] = [:]

        for diagnostic in diagnostics {
            if diagnosticsPerSection[diagnostic.section] == nil {
                orderOfFirstAppearance.append(diagnostic.section)
            }
            diagnosticsPerSection[diagnostic.section, default: []].append(diagnostic)
        }

        return orderOfFirstAppearance.compactMap { section in
            guard let diagnostics = diagnosticsPerSection[section] else { assertionFailure(); return nil }
            return (section, diagnostics)
        }

    }


    @MainActor
    private func measure() async {
        isMeasuring = true
        diagnostics = []
        // Read here rather than in `init`, and re-read on every refresh: a drain may have run since the screen was last opened, and a `View.init` is no
        // place for I/O.
        lastInboxDrainReport = actions.getLastInboxDrainReport()
        do {
            for await diagnostic in try actions.getAsyncStreamOfEngineDiagnostics() {
                diagnostics.append(diagnostic)
            }
        } catch {
            diagnostics = [.couldNotCompute(figure: "The engine's diagnostics", reason: error.localizedDescription)]
        }
        isMeasuring = false
    }


    /// The whole thing as plain text, for the email and for the clipboard.
    ///
    /// The same values the screen shows, in the same order, so the two can never disagree. It opens with the block the other support mails use, and says so
    /// when it was taken before the measuring had finished — a partial report that looks complete is worse than no report, and one reader's mail did lose
    /// every row that would have classified their backlog that way. Both buttons ask the reader to wait first; this line is for the one who cannot.
    private var report: String {
        var lines: [String] = [
            "Olvid version: \(ObvAppCoreConstants.fullVersion)",
            "Device model: \(UIDevice.current.preciseModel)",
            "System: \(UIDevice.current.name) \(UIDevice.current.systemVersion)",
        ]
        for group in groups {
            lines.append("")
            lines.append("--- \(group.section.rawValue) ---")
            for diagnostic in group.diagnostics {
                lines.append("\(diagnostic.label): \(diagnostic.value)")
            }
        }
        if let lastInboxDrainReport {
            // The whole of it here, not the four rows the section above shows: this text is what a reader sends us, and the section is only what fits.
            lines.append("")
            lines.append(lastInboxDrainReport.textForSharing)
        }
        if isMeasuring {
            lines.append("")
            lines.append("(taken before the measuring had finished)")
        }
        return lines.joined(separator: "\n")
    }


    private var emailModel: ObvEmailComposerView.Model {
        .init(subject: "Olvid engine diagnostics",
              toRecipients: [ObvAppCoreConstants.toEmailForSendingInitializationFailureErrorMessage],
              messageBody: report)
    }


    @MainActor
    private func showThenHideHUD(_ category: HUDView.Category) {
        Task {
            hudCategory = category
            try? await Task.sleep(seconds: 1)
            hudCategory = nil
        }
    }

}


// MARK: - Implementing ObvEmailComposerViewDelegate

extension EngineDiagnosticsView: ObvEmailComposerViewDelegate {

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


// MARK: - One figure

private struct EngineDiagnosticRowView: View {

    let diagnostic: ObvEngineDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(diagnostic.label)
            Text(diagnostic.value)
                .font(.footnote)
                .foregroundStyle(.secondary)
                // Some values are several lines — the individual listings, for instance — and a value that matters must not be silently truncated.
                .fixedSize(horizontal: false, vertical: true)
        }
    }

}

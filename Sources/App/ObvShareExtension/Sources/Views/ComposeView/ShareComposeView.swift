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
import ObvAppTypes
import ObvTypes
import ObvDiscussionChooser

/// Main-actor isolated like the other actions protocols of this module: it is called from a button's action.
@MainActor
public protocol ShareComposeViewActions {
    func userWantsToSendMessage(from view: ShareComposeView,
                                shareableItems: [SharedState.ShareableItem],
                                textBody: String,
                                from: ObvCryptoId,
                                to: [ObvDiscussionIdentifier])
}

public struct ShareComposeView: View {
    
    @ObservedObject var sharedState: SharedState
    
    let actions: any ShareComposeViewActions
    
    @FocusState private var isFocused: Bool
    
    private static var horizontalPadding: CGFloat {
        #if targetEnvironment(macCatalyst)
        return 16.0
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 16.0
        } else {
            return 12.0
        }
        #endif
    }
    
    private static let buttonSize: CGFloat = 48.0
    
    @Namespace private var namespace
    
    public var textField: some View {
        TextEditor(text: $sharedState.textBody)
            .scrollContentBackground(.hidden)
            .frame(minHeight: Self.LineLimit.defaultLineHeight,
                   maxHeight: Self.LineLimit.toMaxHeight)
            .focused($isFocused)
            .overlay(alignment: .leading, content: { overlay })
    }
    
    @ViewBuilder
    private var overlay: some View {
        Text(verbatim: "Aa")
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
            .isHidden(self.isFocused || !sharedState.textBody.isEmpty)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 8.0) {
                ZStack(alignment: .center) {
                    if !sharedState.isSending {
                        textField
                            .padding(.top, 6.0)
                    } else {
                        SendingProgressView(progress: sharedState.sendingProgress)
                            .frame(maxWidth: .infinity)
                    }

                }
                .frame(minHeight: 50.0)
                
                ZStack {
                    Spacer(minLength: 0)
                    
                    Button {
                        guard let selectedOwnedCryptoId = sharedState.selectedOwnedCryptoId else { return }
                        
                        actions.userWantsToSendMessage(from: self,
                                                       shareableItems: sharedState.shareableItems,
                                                       textBody: sharedState.textBody,
                                                       from: selectedOwnedCryptoId,
                                                       to: sharedState.selectedDiscussionIdentifiers)
                        
                    } label: {
                        // **The fill is drawn here rather than by a button style, and that is the whole point.**
                        // `.borderedProminent` was measured ignoring its tint once disabled: it draws a system fill,
                        // leaving the arrow as the only legible thing — black on almost-black over the dark glass bar,
                        // and barely there over a light one. Since the disabled state is exactly the state this screen
                        // spends most of its life in (nothing can be sent until a discussion is chosen), the style has
                        // to go. `.disabled(...)` below stays, so the semantics and VoiceOver are unaffected; only the
                        // drawing moves in here.
                        //
                        // The compose bar in `ObvComposition` never had to solve this: it *replaces* the send button
                        // with the record button while the draft is empty (`if isMessageEmpty`), so a disabled
                        // prominent button is a state only this screen can produce.
                        //
                        // `Color.accentColor` rather than a named blue, so this is the same blue as the compose bar's
                        // button by construction — that button resolves `.borderedProminent` against the accent, and
                        // neither the app nor this extension sets one, so both take the default. A hard-coded
                        // `olvidLight` would match today and drift the moment anybody wires up a global accent.
                        //
                        // Only the fill fades: the arrow stays fully white, because fading both would take a light
                        // background's contrast down twice over and the arrow is what says which button this is.
                        Image(systemIcon: .arrowUp)
                            .fontWeight(.bold)
                            .imageScale(.medium)
                            .foregroundStyle(.white)
                            // Wider than it is tall, or a `Capsule` is indistinguishable from a `Circle` — a capsule
                            // whose width equals its height *is* one. These two numbers are the shape: 44 is also the
                            // width Apple asks of a tap target, and the height stays 32 so the button sits in the bar
                            // exactly as it did.
                            .frame(width: 44.0, height: 32.0)
                            .background {
                                Capsule()
                                    .fill(Color.accentColor.opacity(sharedState.canShare ? 1.0 : 0.5))
                            }
                    }
                    .buttonStyle(.plain)
                    // The label now carries a frame of its own, so the whole capsule is hit-testable rather than just
                    // the glyph — the fault the compose bar's send button had to answer with `contentShape` when a
                    // pointer, which is less forgiving than a finger, found only the arrow answered a click. Stated
                    // here so the shape is the control's and not the gap around it.
                    .contentShape(Capsule())
                    .padding(.bottom, Self.buttonSize / 4.0)
                    .disabled(!sharedState.canShare)
                }
            }
            .padding(.horizontal, Self.horizontalPadding)
            .fixedSize(horizontal: false, vertical: true)
        }
        .glassTextFieldStyle(namespace: namespace, cornerRadius: 20.0)
        .frame(minHeight: 50.0)
    }
}

// MARK: - SendingProgressView

/// Shown in place of the text editor once the user taps send, so the two long phases of the send pipeline
/// (transcoding to SD, then waiting for the engine to upload the attachments) report where they are instead
/// of showing an anonymous spinner. Falls back to an indeterminate bar whenever there is no truthful
/// fraction to show.
private struct SendingProgressView: View {

    let progress: SharedState.SendingProgress?

    private var caption: String {
        switch progress {
        case .transcoding(_, let completedItemCount, let totalItemCount):
            // Only worth a count when there is more than one item to get through.
            guard totalItemCount > 1 else { return String(localizedInThisBundle: "SHARE_EXTENSION_PROGRESS_COMPRESSING") }
            // `completedItemCount` is the number *finished*, so show the one in flight as 1-based.
            let currentItem = min(completedItemCount + 1, totalItemCount)
            return String(localizedInThisBundle: "SHARE_EXTENSION_PROGRESS_COMPRESSING_\(currentItem)_OF_\(totalItemCount)")
        case .preparing:
            return String(localizedInThisBundle: "SHARE_EXTENSION_PROGRESS_PREPARING")
        case .uploading, .none:
            return String(localizedInThisBundle: "SHARE_EXTENSION_PROGRESS_SENDING")
        }
    }

    /// Clamped, since neither `AVAssetExportSession.progress` nor the engine's byte counts are contractually
    /// bound to 0...1, and a value outside that range makes `ProgressView` misdraw.
    private var fractionCompleted: Double? {
        guard let fractionCompleted = progress?.fractionCompleted else { return nil }
        return min(max(fractionCompleted, 0.0), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3.0) {
            HStack(spacing: 4.0) {
                Text(verbatim: caption)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let fractionCompleted {
                    // Monospaced digits so the percentage doesn't jitter the caption as it counts up.
                    Text(verbatim: fractionCompleted.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Group {
                if let fractionCompleted {
                    // Animate only *within* a phase, where a growing fraction really is progress.
                    ProgressView(value: fractionCompleted)
                        .animation(.default, value: fractionCompleted)
                } else {
                    ProgressView()
                }
            }
            // Give the bar a fresh identity per phase so a phase change snaps instead of animating. The
            // fraction restarts at zero when the send moves from transcoding to uploading, and interpolating
            // between the two would run the bar all the way back down — reading as progress being lost,
            // when in fact one measurement simply ended and a different one began.
            .id(progress?.phase)
        }
        .progressViewStyle(.linear)
    }
}

extension ShareComposeView {

    @MainActor
    struct LineLimit {
        
        private static let macOS = 15
        private static let iOS = 8
        private static let iPadOS = 8
        
        // Default line height derived from system body font to cap TextEditor height
        static let defaultLineHeight: CGFloat = {
            #if canImport(UIKit)
            return UIFont.preferredFont(forTextStyle: .body).lineHeight
            #else
            return 23.0
            #endif
        }()
        
        static var toMaxHeight: CGFloat {
            let lineLimit: Int
            #if targetEnvironment(macCatalyst)
            lineLimit = Self.macOS
            #else
            lineLimit = UIDevice.current.userInterfaceIdiom == .pad ? Self.iPadOS : Self.iOS
            #endif
            return CGFloat(lineLimit) * defaultLineHeight
        }
    }


}


// MARK: - Previews

#if DEBUG

/// Renders one phase the way it appears in the compose bar, at the width the bar actually gives it.
///
/// `@MainActor` because `SendingProgress` is nested in the main-actor-isolated `SharedState`, so it inherits
/// that isolation and cannot be passed into a `nonisolated` function from the (main-actor) preview bodies.
@MainActor
private func previewOfSendingProgress(_ progress: SharedState.SendingProgress?) -> some View {
    SendingProgressView(progress: progress)
        .padding(.horizontal, 12.0)
        .frame(minHeight: 50.0)
        .frame(maxWidth: 360.0)
}

#Preview("Compressing (one item)") {
    previewOfSendingProgress(.transcoding(fractionCompleted: 0.42, completedItemCount: 0, totalItemCount: 1))
}

#Preview("Compressing (several items)") {
    previewOfSendingProgress(.transcoding(fractionCompleted: 0.68, completedItemCount: 2, totalItemCount: 5))
}

#Preview("Preparing") {
    previewOfSendingProgress(.preparing)
}

#Preview("Sending (no fraction yet)") {
    previewOfSendingProgress(.uploading(fractionCompleted: nil))
}

#Preview("Sending (uploading)") {
    previewOfSendingProgress(.uploading(fractionCompleted: 0.15))
}

/// The state a send with no network sits in: the caption and a bar pinned at zero, rather than an
/// anonymous spinner. Worth eyeballing, since this is the case the indicator exists for.
#Preview("Sending (stalled at 0%)") {
    previewOfSendingProgress(.uploading(fractionCompleted: 0.0))
}

#endif



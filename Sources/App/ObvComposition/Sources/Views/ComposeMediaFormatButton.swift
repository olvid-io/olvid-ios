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
import OSLog
import os
import ObvAppCoreConstants
import ObvAppTypes
import ObvDesignSystem
import ObvSystemIcon


/// The control that says what size this draft's photographs **and videos** will be sent at, and lets the reader change it.
///
/// It lives inside the attachments row, whose height `ComposeView` pins, so that it can never change the bar's height: on the SwiftUI
/// discussion screen an animated change of that height makes `safeAreaInset` reparameterise the scroll view, which no scroll offset can
/// repair. Wherever it moves, it must keep costing no height.
///
/// A `Menu`, four flat options needing nothing more.
struct ComposeMediaFormatButton: View {

    let selection: ComposeViewDataSourceModel.MediaFormatSelection
    let isDisabled: Bool
    let formatTapped: (ObvMediaFormat) -> Void

    /// The short label the button itself carries. `.system(size:)` and not a text style: the badge around it is a fixed size, so a
    /// reader on a large accessibility setting would otherwise have the glyph leave its box. Acceptable here and only here because the
    /// label repeats what the menu says in full.
    private static let fontOfTheBadge: Font = .system(size: 11, weight: .bold)

    /// The chevron saying there is something to choose, a little smaller than the name beside it.
    private static let fontOfTheChevron: Font = .system(size: 8, weight: .bold)

#if DEBUG

    /// Says what building all four rows' strings costs, and how often it is asked for. See the call site.
    ///
    /// **Behind `DEBUG` because it is an instrument and not a feature**, and the question it was put here to answer — why the subtitles
    /// appear late — has not been settled. Deleting it would have thrown away the only thing that can settle it; leaving it in a release
    /// build would ship a `Logger.notice` and a process-wide lock taken every time the menu's content is built. Take it out for good once
    /// the answer is written down, and not before.
    private static func reportTheCostOfBuildingTheRows(selection: ComposeViewDataSourceModel.MediaFormatSelection) {
        let started = Date()
        var characters = 0
        for format in ObvMediaFormat.orderShownInMenu {
            characters += format.titleAndWeight(in: selection).count
            characters += format.purpose.count
        }
        buildCount.withLock { $0 += 1 }
        let count = buildCount.withLock { $0 }
        logger.notice("🏷️ Built the size menu's 4 rows (\(characters, privacy: .public) characters) in \(Int(Date().timeIntervalSince(started) * 1_000_000), privacy: .public) µs — build number \(count, privacy: .public) since launch")
    }

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ComposeMediaFormatButton")
    private static let buildCount = OSAllocatedUnfairLock<Int>(initialState: 0)

#endif

    /// The glyph a row carries: a checkmark for the size in force, and the *same* checkmark drawn in nothing for the three
    /// that are not.
    ///
    /// Every row carries an image so that the rows line up: from iOS 26 a menu draws the glyph leading, and a checkmark on one row alone
    /// indents that row. `labelReservedIconWidth` has no effect on these rows, and a `Picker` would drop their subtitles. The invisible
    /// checkmark (`.clear`, `.alwaysOriginal`) has the real one's metrics, so the column follows the text size.
    private func glyph(for format: ObvMediaFormat) -> Image {
        if format == selection.selected {
            return Image(systemIcon: .checkmark)
        }
        guard let blank = UIImage(systemIcon: .checkmark)?.withTintColor(.clear, renderingMode: .alwaysOriginal) else {
            assertionFailure("The checkmark is a system symbol and cannot be missing")
            return Image(systemIcon: .checkmark)
        }
        // `.original` on the way back in, or SwiftUI treats it as a template and paints the menu's own tint over the nothing.
        return Image(uiImage: blank).renderingMode(.original)
    }

    var body: some View {
        Menu {
            // **Timed once per build of the menu's content, unconditionally — in a debug build.** The subtitles are reported as appearing
            // late, and the two things that could cause it want opposite answers: if building these strings is slow, it is ours to fix —
            // four `String(localized:)` lookups and four `ByteCountFormatter` calls, all on the main thread — and if it is not, the delay
            // is inside how UIKit renders a `UIAction`'s subtitle and no amount of work here will touch it. This line tells them apart,
            // and it also says how many times the menu is rebuilt, which is the third possibility.
#if DEBUG
            let _ = Self.reportTheCostOfBuildingTheRows(selection: selection)
#endif
            // Largest first, so the list reads as a scale.
            ForEach(ObvMediaFormat.orderShownInMenu) { format in
                Button {
                    formatTapped(format)
                } label: {
                    // **Three views, and the menu decides what to do with each.** A `Button` in a menu maps its label's first `Text`
                    // to the item's title, its second to the item's subtitle, and an `Image` to the item's glyph — which is how one
                    // row carries the name, what the size is for, what it weighs, and whether it is the one in force, without any of
                    // it being laid out here. Building the row by hand would fight the menu on every platform it is drawn on. Every
                    // row carries an image, the unselected ones an invisible one, or the glyph's column indents the selected row
                    // alone — see `glyph(for:)`, which is where the two mechanisms that cannot do this are written down.
                    Text(verbatim: format.titleAndWeight(in: selection))
                    Text(verbatim: format.purpose)
                    glyph(for: format)
                }
            }
        } label: {
            // **One `Text`, not an `HStack`.** A symbol beside a word is `Text(Image(...))` rather than an `Image`: an image is laid
            // out as an image, and its box is taller than the line of the font it was given, so a row containing one is taller than a
            // line and the excess lands above the baseline. Concatenated `Text`s stay exactly one line box tall whatever they carry,
            // which is what keeps this capsule the size it looks.
            (Text(verbatim: selection.selected.title)
             + Text(verbatim: " ")
             + Text(Image(systemIcon: .chevronDown)).font(Self.fontOfTheChevron))
                .font(Self.fontOfTheBadge)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
                .overlay(Capsule(style: .continuous).stroke(Color.primary.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(Text("MEDIA_FORMAT_BUTTON_ACCESSIBILITY_LABEL"))
        .accessibilityValue(Text(verbatim: selection.selected.title))
    }

}


extension ObvMediaFormat {

    /// The name shown on the button and at the head of each menu row.
    ///
    /// A rank, never a number of pixels: see ``ObvMediaFormat``. Localised although all four read the same in every shipped language, so
    /// that no translator takes a missing entry for a forgotten one.
    var title: String {
        switch self {
        case .low: return String(localizedInThisBundle: "MEDIA_FORMAT_LOW")
        case .med: return String(localizedInThisBundle: "MEDIA_FORMAT_MED")
        case .hi: return String(localizedInThisBundle: "MEDIA_FORMAT_HI")
        case .max: return String(localizedInThisBundle: "MEDIA_FORMAT_MAX")
        }
    }

    /// What this size is *for*, in a few words.
    ///
    /// **It carries more weight now than it did**, the names having stopped naming pixels: `Hi` against `Max` says which is larger and
    /// nothing about what either is, where `4K` against `Max` at least gestured at a number. This line is what tells the reader why one
    /// would be chosen over the other, and the weight beside it is what makes the choice.
    var purpose: String {
        switch self {
        case .low: return String(localizedInThisBundle: "MEDIA_FORMAT_SUBTITLE_LOW")
        case .med: return String(localizedInThisBundle: "MEDIA_FORMAT_SUBTITLE_MED")
        case .hi: return String(localizedInThisBundle: "MEDIA_FORMAT_SUBTITLE_HI")
        case .max: return String(localizedInThisBundle: "MEDIA_FORMAT_SUBTITLE_MAX")
        }
    }

    /// The name of the size followed by what the whole draft weighs at it — the menu row's title.
    ///
    /// The weight is beside the name, not in the subtitle, so that the four can be compared down one column.
    ///
    /// A weight that includes the estimate of a video's export is marked as approximate. A weight not known yet is shown as being
    /// prepared: it arrives shortly, and the size can be picked before it does.
    func titleAndWeight(in selection: ComposeViewDataSourceModel.MediaFormatSelection) -> String {
        let weight: String
        if let byteCount = selection.totalByteCountForFormat[self] {
            let formattedByteCount = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            if selection.formatsWhoseWeightIsAnEstimate.contains(self) {
                weight = String(localizedInThisBundle: "MEDIA_FORMAT_APPROXIMATE_WEIGHT_\(formattedByteCount)")
            } else {
                weight = formattedByteCount
            }
        } else {
            weight = String(localizedInThisBundle: "MEDIA_FORMAT_PREPARING")
        }
        return "\(title) · \(weight)"
    }

}


#if DEBUG

#Preview {
    VStack(spacing: 16) {
        ComposeMediaFormatButton(selection: .init(selected: .med,
                                                  totalByteCountForFormat: [.max: 2_400_000, .hi: 1_400_000, .med: 450_000, .low: 180_000],
                                                  formatsWhoseWeightIsAnEstimate: []),
                                 isDisabled: false,
                                 formatTapped: { print("[debug] \($0.rawValue)") })
        ComposeMediaFormatButton(selection: .init(selected: .low, totalByteCountForFormat: [:], formatsWhoseWeightIsAnEstimate: []),
                                 isDisabled: false,
                                 formatTapped: { _ in })
        // A draft holding a clip: `max` and the chosen size have a file, and the other two are estimated.
        ComposeMediaFormatButton(selection: .init(selected: .med,
                                                  totalByteCountForFormat: [.max: 214_000_000, .hi: 62_000_000, .med: 31_000_000, .low: 13_000_000],
                                                  formatsWhoseWeightIsAnEstimate: [.hi, .low]),
                                 isDisabled: false,
                                 formatTapped: { _ in })
    }
    .padding()
}

#endif

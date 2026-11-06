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


/// Shown over the text editor while a file is being handed over to the draft, in place of an anonymous spinner.
///
/// The same shape as the share extension's send (`SendingProgressView` in `ObvShareExtension`): a caption, the percentage at the end of
/// the line, and a bar under both. A bar rather than a ring, the whole width of the editor leaving room to say what is taking the time.
///
/// Indeterminate when there is no fraction to show. Also shown, with its own caption, while a send waits for the draft's videos.
struct AttachmentsLoadingProgressView: View {

    let caption: LocalizedStringKey
    let fractionCompleted: Double?

    /// Clamped, `Progress.fractionCompleted` not being contractually bound to 0...1, and a value outside that range makes
    /// `ProgressView` misdraw.
    private var clamped: Double? {
        guard let fractionCompleted else { return nil }
        return min(max(fractionCompleted, 0.0), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3.0) {

            HStack(spacing: 4.0) {
                Text(caption, tableName: "Localizable", bundle: ObvCompositionResources.bundle)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let clamped {
                    // Monospaced digits so the percentage does not jitter the caption as it counts up.
                    Text(verbatim: clamped.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let clamped {
                ProgressView(value: clamped)
                    .animation(.default, value: clamped)
            } else {
                ProgressView()
            }

        }
        .progressViewStyle(.linear)
    }

}


#if DEBUG

#Preview {
    VStack(spacing: 24) {
        AttachmentsLoadingProgressView(caption: "ATTACHMENTS_LOADING_PROGRESS_CAPTION", fractionCompleted: nil)
        AttachmentsLoadingProgressView(caption: "ATTACHMENTS_LOADING_PROGRESS_CAPTION", fractionCompleted: 0.0)
        AttachmentsLoadingProgressView(caption: "ATTACHMENTS_LOADING_PROGRESS_CAPTION", fractionCompleted: 0.42)
        AttachmentsLoadingProgressView(caption: "ATTACHMENTS_LOADING_PROGRESS_CAPTION", fractionCompleted: 1.0)
    }
    .padding()
}

#endif

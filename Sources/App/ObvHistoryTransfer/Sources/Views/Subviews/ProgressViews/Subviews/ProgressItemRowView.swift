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
import ObvSystemIcon


/// Visual state for a progress step's indicator icon.
enum ProgressItemState {
    case inProgress
    case success
    case warning
    case error
}


/// Container shared by all progress item views: renders CheckAndLineView on the left, a bold title row, then optional subtitle content.
struct ProgressItemRowView<Content: View>: View {
    let state: ProgressItemState
    let showLine: Bool
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            CheckAndLineView(state: state, showLine: showLine)
            VStack(alignment: .leading) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                content
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
            }
            .progressItemSpacing(showLine: showLine)
        }
    }
}


/// Subview share accross all progress item views.
private struct CheckAndLineView: View {

    let state: ProgressItemState
    let showLine: Bool

    private var systemIcon: SystemIcon {
        switch state {
        case .inProgress: return .circle
        case .success: return .checkmarkCircleFill
        case .warning: return .exclamationmarkCircleFill
        case .error: return .xmarkCircleFill
        }
    }

    private var systemIconColor: Color {
        switch state {
        case .inProgress: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemIcon: systemIcon)
                .foregroundStyle(systemIconColor)
            Rectangle()
                .frame(width: 2)
                .padding(.vertical, 2)
                .foregroundStyle(.tertiary)
                .opacity(showLine ? 1.0 : 0.0)
        }
    }
}


private struct ProgressItemSpacing: ViewModifier {
    let showLine: Bool
    func body(content: Content) -> some View {
        content.padding(.bottom, showLine ? 16 : 0)
    }
}

private extension View {
    func progressItemSpacing(showLine: Bool) -> some View {
        modifier(ProgressItemSpacing(showLine: showLine))
    }
}

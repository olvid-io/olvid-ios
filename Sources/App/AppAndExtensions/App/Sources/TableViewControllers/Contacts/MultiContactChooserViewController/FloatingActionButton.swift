/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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

import ObvUI
import SwiftUI
import ObvSystemIcon
import ObvDesignSystem


/// Legacy model, shall not be used in the future
final class FloatingButtonModel: ObservableObject {

    let title: String
    let systemIcon: SystemIcon?
    @Published var isEnabled: Bool
    let action: () -> Void

    init(title: String, systemIcon: SystemIcon?, isEnabled: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemIcon = systemIcon
        self.isEnabled = isEnabled
        self.action = action
    }
}


struct FloatingButtonView: View {

    @ObservedObject var model: FloatingButtonModel
    var horizontalPadding: CGFloat = 16.0
    var verticalPadding: CGFloat = 16.0
    var showBackground: Bool = true

    private var content: some View {
        HStack {
            Spacer(minLength: 0)
            OlvidButton(style: .blue,
                        title: Text(model.title),
                        systemIcon: model.systemIcon) {
                guard model.isEnabled else { return }
                model.action()
            }
                        .disabled(!model.isEnabled)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, verticalPadding)
            Spacer(minLength: 0)
        }
    }

    var body: some View {
        VStack {
            Spacer()
            if !showBackground {
                content
            } else {
                content
                    .background(.ultraThinMaterial)
            }
        }
    }
}


struct FloatingActionButton_Previews: PreviewProvider {
    static var enable: FloatingButtonModel {
        FloatingButtonModel(title: "Title", systemIcon: .camera(), isEnabled: true, action: {})
    }
    static var disable: FloatingButtonModel {
        FloatingButtonModel(title: "Title", systemIcon: .camera(), isEnabled: true, action: {})
    }

    static var previews: some View {
        Group {
            FloatingButtonView(model: enable)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .light)
            FloatingButtonView(model: enable)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
            FloatingButtonView(model: disable)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .light)
            FloatingButtonView(model: disable)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
        }
        .previewLayout(.sizeThatFits)

    }
}

/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvCircleAndTitlesView
import ObvDesignSystem

struct PlaceholderForUserCell: View {
    
    let avatarSize: ObvDesignSystem.ObvAvatarSize
    
    @State private var showProgressView: Bool = false
    
    private func onTask() async {
        do {
            try await Task.sleep(seconds: 1)
        } catch {
            return
        }
        showProgressView = true
    }
    
    var body: some View {
        HStack {
            ProfilePictureView(model: .init(
                content: .init(text: nil,
                               icon: .person,
                               profilePicture: nil,
                               showGreenShield: false,
                               showRedShield: false),
                colors: .init(background: nil, foreground: nil),
                circleDiameter: avatarSize.frameSize.width))
            Spacer()
            ProgressView()
                .opacity(showProgressView ? 1 : 0)
            Spacer()
        }
        .task(onTask)
    }
}

#Preview {
    PlaceholderForUserCell(avatarSize: .normal)
}

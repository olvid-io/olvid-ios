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


/// This header view is essentially used during onboarding, or on the new backup views.
public struct ObvHeaderView: View {
    
    let title: String
    let subtitle: String?
    @Binding var isBadgeVisible: Bool
    
    public init(title: String, subtitle: String?, isBadgeVisible: Binding<Bool> = .constant(true)) {
        self.title = title
        self.subtitle = subtitle
        self._isBadgeVisible = isBadgeVisible
    }
    
    private struct BadgeView: View {
        var body: some View {
            Image("olvid-badge", bundle: ObvDesignSystemResources.bundle)
                .resizable()
                .frame(width: 60, height: 60, alignment: .center)
        }
    }
    
    public var body: some View {
        VStack {
            if isBadgeVisible {
                if #available(iOS 17.0, *) {
                    BadgeView()
                        .transition(ObvTwirl())
                        .padding()
                } else {
                    BadgeView()
                        .transition(.scale.combined(with: .opacity))
                        .padding()
                }
            } else {
                BadgeView()
                    .padding()
                    .opacity(0)
            }
            Text(title)
                .multilineTextAlignment(.center)
                .font(.title)
                .padding(.bottom, 4)
            if let subtitle {
                Text(subtitle)
                    .multilineTextAlignment(.center)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
}



// MARK: - Previews





private struct HelperViewForAnimations: View {
    
    @State private var isBadgeVisible = false
    
    private func onAppear() {
        Task {
            try await Task.sleep(seconds: 1)
            withAnimation {
                isBadgeVisible = true
            }
        }
    }
    
    var body: some View {
        ObvHeaderView(
            title: "Welcome!",
            subtitle: "Have we met before?",
            isBadgeVisible: $isBadgeVisible)
        .onAppear(perform: onAppear)
    }
    
}


#Preview("Simple") {
    ObvHeaderView(
        title: "Welcome!",
        subtitle: "Have we met before?")
}

#Preview("Transition effect") {
    HelperViewForAnimations()
}

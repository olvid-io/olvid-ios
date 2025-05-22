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
import ObvDesignSystem


struct ExplanationsSectionView: View {
    
    @Binding var navigationTitle: String
    
    private func showNavigationTitle() {
        navigationTitle = String(localizedInThisBundle: "BACKUP")
    }

    private func hideNavigationTitle() {
        navigationTitle = ""
    }
    
    var body: some View {
        Section {
            
            HStack {
                Spacer()
                VStack {
                    ObvCloudBackupIconView()
                        .frame(width: 64, height: 64)
                        .onDisappear(perform: showNavigationTitle)
                        .onAppear(perform: hideNavigationTitle)
                    Text("BACKUP")
                        .font(.title)
                        .fontWeight(.bold)
                }
                Spacer()
            }
            .listRowSeparator(.hidden)
            .padding(.top)

            Text("YOUR_BACKUP_EXPLANATION")
                .multilineTextAlignment(.center)
                .listRowSeparator(.hidden)

            Text("YOUR_BACKUP_WARNING")
                .multilineTextAlignment(.center)
                .listRowSeparator(.hidden)
                .padding(.bottom)

        }
    }
}


// MARK: - Previews

private struct HelperViewForPreview: View {
    @State private var title = "Backup"
    var body: some View {
        Form {
            ExplanationsSectionView(navigationTitle: $title)
        }
    }
}

#Preview {
    HelperViewForPreview()
}

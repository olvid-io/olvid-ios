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


struct ExplanationsSectionView: View {
    
    let explanation: LocalizedStringKey?

    var body: some View {
        Section {
            VStack {
                HStack {
                    Spacer(minLength: 0)
                    VStack {
                        Image(systemIcon: .repeatCircleFill)
                            .resizable()
                            .frame(width: 48, height: 48)
                            .foregroundStyle(.orange)
                        Text("EXPLANATION_TITLE_HISTORY_TRANSFER")
                            .multilineTextAlignment(.center)
                            .font(.title)
                            .fontWeight(.bold)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .listRowSeparator(.hidden)
                .padding(.top)
                
                if let explanation {
                    HStack {
                        Spacer(minLength: 0)
                        Text(explanation)
                            .multilineTextAlignment(.center)
                            .listRowSeparator(.hidden)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.top)
                }
                
            }
            .padding(.bottom)
        }
    }
    
}


// MARK: - Previews

#if DEBUG

private struct ExplanationsSectionPreview: View {
    
    var body: some View {
        NavigationStack {
            Form {
                ExplanationsSectionView(explanation: "HISTORY_TRANSFER_EXPLANATION")
            }
        }
    }
}


private struct WithoutExplanationsSectionPreview: View {
    
    var body: some View {
        NavigationStack {
            Form {
                ExplanationsSectionView(explanation: nil)
            }
        }
    }
}

#Preview("With explanation") {
    ExplanationsSectionPreview()
}

#Preview("Without") {
    WithoutExplanationsSectionPreview()
}

#endif

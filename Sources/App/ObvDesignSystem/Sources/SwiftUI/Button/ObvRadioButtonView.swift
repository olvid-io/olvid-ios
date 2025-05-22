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


/// This radio button is typically used when the user has to make exactly one choice among several possibilities.
///
/// This is currently used during a group creation, when choosing among the different possible group types,
/// and during the advanced backup setup process, when choosing betweem automatic, manual, or no backup options.
///
/// The preview bellows shows a typical example.
public struct ObvRadioButtonView<T: Equatable>: View {
    
    let value: T
    @Binding var selectedValue: T
    
    public init(value: T, selectedValue: Binding<T>) {
        self.value = value
        self._selectedValue = selectedValue
    }

    private var isSelected: Bool { selectedValue == value }
    
    public var body: some View {
        Image(systemIcon: .circle)
            .font(.system(size: 16))
            .foregroundStyle(isSelected ? .blue : .primary)
            .overlay(alignment: .center) {
                if isSelected {
                    Image(systemIcon: .circleFill)
                        .font(.system(size: 8))
                        .foregroundStyle(.blue)
                        .transition(.scale)
                } else {
                    EmptyView()
                }
            }
    }
    
}











// MARK: - Preview

#if DEBUG

private struct RadioButtonViewExampleUsageView: View {
    
    @State private var choiceMade: Choice?
    
    enum Choice: String, CaseIterable {
        case choice1 = "Choice 1"
        case choice2 = "Choice 2"
        case choice3 = "Choice 3"
    }
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(Choice.allCases, id: \.self) { choice in
                        Button {
                            choiceMade = choice
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                ObvRadioButtonView(value: choice, selectedValue: $choiceMade)
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top) {
                                        Text(verbatim: choice.rawValue)
                                            .font(.headline)
                                        Spacer()
                                    }
                                    Text(verbatim: "Secondary text")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle()) // Trick making the button interactive everywhere
                            .padding()
                        }
                        .buttonStyle(.plain)
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke()
                                .foregroundStyle(choiceMade == choice ? .blue : .secondary)
                                .transition(.identity)
                        }
                        .padding(.horizontal)
                    }
                    Button(action: { choiceMade = nil }) {
                        Text(verbatim: "Clear")
                    }
                    .disabled(choiceMade == nil)
                    Spacer()
                }
            }
            
            
        }
    }
    
}

#Preview {
    RadioButtonViewExampleUsageView()
}

#endif

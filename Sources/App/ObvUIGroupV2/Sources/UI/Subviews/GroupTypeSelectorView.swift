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
import ObvTypes
import ObvAppTypes
import ObvSystemIcon
import ObvDesignSystem


struct GroupTypeSelectorView: View {

    @Binding var selectedGroupTypeValue: GroupTypeValue? // Must be a binding
    @Binding var isReadOnly: Bool // Must be a binding
    @Binding var remoteDeleteAnythingPolicy: ObvGroupType.RemoteDeleteAnythingPolicy // Must be a binding

    private func color(isSelected: Bool) -> Color {
        isSelected ? Color.blue : .secondary.opacity(0.43)
    }
    
    var body: some View {
            
        
        VStack {
            
            
            ForEach(GroupTypeValue.allCases) { groupTypeValue in

                VStack {
                    
                    Button { withAnimation { selectedGroupTypeValue = groupTypeValue } } label: {
                        HStack(alignment: .firstTextBaseline) {
                            ObvRadioButtonView(value: groupTypeValue, selectedValue: $selectedGroupTypeValue)
                            GroupTypeViewCellHeader(model: .init(groupType: groupTypeValue, isSelected: selectedGroupTypeValue == groupTypeValue))
                        }
                        .padding()
                    }
                    .foregroundStyle(.primary)
                    
                    if selectedGroupTypeValue == groupTypeValue {
                        
                        switch groupTypeValue {
                        case .standard:
                            EmptyView()
                        case .managed:
                            EmptyView()
                        case .readOnly:
                            EmptyView()
                        case .advanced:
                            VStack {
                                Divider()

                                ModerationView(systemIcon: .exclamationmarkBubble,
                                              systemIconColor: .white,
                                              backgroundColor: .pink,
                                              text: String(localizedInThisBundle: "DISCUSSION_MODERATION"),
                                              subtext: String(localizedInThisBundle: "DISCUSSION_MODERATION_EXPLANATION"),
                                              remoteDeleteAnythingPolicy: $remoteDeleteAnythingPolicy)
                                
                                Divider()
                                    .padding(.leading, 65)
                                
                                ReadOnlyView(systemIcon: .eye,
                                             systemIconColor: .white,
                                             backgroundColor: .cyan,
                                             text: String(localizedInThisBundle: "READ_ONLY"),
                                             isReadOnly: $isReadOnly)
                                .padding(.bottom)
                            }
                        }
                        
                    }
                    
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 12.0)
                        .stroke(color(isSelected: selectedGroupTypeValue == groupTypeValue), lineWidth: 1.0)
                )
            }
            
            Spacer()
            
        }
    }
    
    
    private struct ModerationView: View {
        @Binding var remoteDeleteAnythingPolicy: ObvGroupType.RemoteDeleteAnythingPolicy // Must be a binding
        let systemIcon: SystemIcon
        let systemIconSize: CGFloat
        let systemIconColor: Color
        let backgroundColor: Color
        let text: String
        let subtext: String
        
        init(systemIcon: SystemIcon, systemIconSize: CGFloat = 17.0, systemIconColor: Color, backgroundColor: Color, text: String, subtext: String, remoteDeleteAnythingPolicy: Binding<ObvGroupType.RemoteDeleteAnythingPolicy>) {
            self.systemIcon = systemIcon
            self.systemIconSize = systemIconSize
            self.systemIconColor = systemIconColor
            self.backgroundColor = backgroundColor
            self.text = text
            self.subtext = subtext
            self._remoteDeleteAnythingPolicy = remoteDeleteAnythingPolicy
        }
        
        var body: some View {
            HStack {
                Image(systemIcon: systemIcon)
                    .font(.system(size: systemIconSize))
                    .tint(systemIconColor)
                    .foregroundStyle(systemIconColor)
                    .frame(width: 29, height: 29)
                    .background(
                        RoundedRectangle(cornerSize: .init(width: 8, height: 8), style: .circular)
                            .foregroundStyle(backgroundColor)
                    )
                    .padding(.horizontal, 4)
                VStack(alignment: .leading) {
                    Text(text)
                        .padding(.horizontal, 4)
                        .foregroundStyle(.primary)
                    Text(subtext)
                        .padding(.horizontal, 4)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Spacer()
                
                Picker(selection: $remoteDeleteAnythingPolicy) {
                    ForEach(ObvGroupType.RemoteDeleteAnythingPolicy.allCases, id: \.self) { policy in
                        switch policy {
                        case .nobody:
                            Text("REMOVE_DELETE_ANYTHING_POLICY_NOBDODY")
                        case .admins:
                            Text("REMOVE_DELETE_ANYTHING_POLICY_ADMINS")
                        case .everyone:
                            Text("REMOVE_DELETE_ANYTHING_POLICY_EVERYONE")
                        }
                    }
                } label: {}

            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }
    
    
    private struct ReadOnlyView: View {
        let systemIcon: SystemIcon
        let systemIconSize: CGFloat
        let systemIconColor: Color
        let backgroundColor: Color
        let text: String
        @Binding var isReadOnly: Bool // Must be a binding
        
        init(systemIcon: SystemIcon, systemIconSize: CGFloat = 17.0, systemIconColor: Color, backgroundColor: Color, text: String, isReadOnly: Binding<Bool>) {
            self.systemIcon = systemIcon
            self.systemIconSize = systemIconSize
            self.systemIconColor = systemIconColor
            self.backgroundColor = backgroundColor
            self.text = text
            self._isReadOnly = isReadOnly
        }

        var body: some View {
            HStack {
                Image(systemIcon: systemIcon)
                    .font(.system(size: systemIconSize))
                    .foregroundStyle(systemIconColor)
                    .tint(systemIconColor)
                    .frame(width: 29, height: 29)
                    .background(
                        RoundedRectangle(cornerSize: .init(width: 8, height: 8), style: .circular)
                            .foregroundStyle(backgroundColor)
                    )
                    .padding(.horizontal, 4)
                Text(text)
                    .padding(.horizontal, 4)
                    .tint(.primary)
                Spacer()
                Toggle(isOn: $isReadOnly) {
                    Text("READ_ONLY")
                }
                .labelsHidden()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        
    }

}

// MARK: - Previews

#if DEBUG

private struct ViewForPreview: View {
    
    @State private var selectedGroupType: GroupTypeValue?
    @State private var isReadOnly = false
    @State private var remoteDeleteAnythingPolicy: ObvGroupType.RemoteDeleteAnythingPolicy = .admins
    
    var body: some View {
        GroupTypeSelectorView(selectedGroupTypeValue: $selectedGroupType,
                              isReadOnly: $isReadOnly,
                              remoteDeleteAnythingPolicy: $remoteDeleteAnythingPolicy)
    }
    
}

#Preview {
    ViewForPreview()
        .padding()
}

#endif

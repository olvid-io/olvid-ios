/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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


public struct ObvSimpleListItemView: View {
    
    private let title: Text
    private let value: Text
    private let valueToCopyOnLongPress: String?
    private let buttonConfig: (title: LocalizedStringKey, titleOfOverlayDisplayedOnTap: LocalizedStringKey, action: () -> Void)?
    
    @State private var showValueCopiedOverlay = false
    @State private var showButtonOverlay = false
    
    public init(title: Text, value: String?, buttonConfig: (title: LocalizedStringKey, titleOfOverlayDisplayedOnTap: LocalizedStringKey, action: () -> Void)? = nil) {
        self.title = title
        self.buttonConfig = buttonConfig
        self.value = Text(value ?? "-")
        self.valueToCopyOnLongPress = value
    }
    
    public init(title: Text, date: Date?) {
        self.title = title
        self.buttonConfig = nil
        if let date = date {
            self.value = Text(date, style: .date)
        } else {
            self.value = Text(verbatim: "-")
        }
        self.valueToCopyOnLongPress = nil
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                title
                    .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                    .font(.headline)
                    .padding(.bottom, 4.0)
                value
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    .font(.body)
                HStack { Spacer() }
            }
            .onTapGesture(count: 2) {
                guard let valueToCopyOnLongPress = self.valueToCopyOnLongPress else { return }
                UIPasteboard.general.string = valueToCopyOnLongPress
                showValueCopiedOverlay.toggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) {
                    showValueCopiedOverlay.toggle()
                }
            }
            .overlay(
                Text("VALUE_COPIED")
                    .font(.system(.callout, design: .rounded))
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    .padding()
                    .background(
                        BlurView(style: .systemUltraThinMaterial).clipShape(Capsule(style: .continuous))
                    )
                    .scaleEffect(showValueCopiedOverlay ? 1.0 : 0.5)
                    .opacity(showValueCopiedOverlay ? 1.0 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: showValueCopiedOverlay)
            )
            if let buttonConfig = self.buttonConfig {
                Button(buttonConfig.title) {
                    showButtonOverlay.toggle()
                    buttonConfig.action()
                    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) {
                        showButtonOverlay.toggle()
                    }
                }
                .buttonStyle(.borderless)
                .padding(.leading, 8)
            }
        }
        .overlay(
            Text(self.buttonConfig?.titleOfOverlayDisplayedOnTap ?? "")
                .font(.system(.callout, design: .rounded))
                .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                .padding()
                .background(
                    BlurView(style: .systemUltraThinMaterial).clipShape(Capsule(style: .continuous))
                )
                .scaleEffect(showButtonOverlay ? 1.0 : 0.5)
                .opacity(showButtonOverlay ? 1.0 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: showButtonOverlay)
        )
    }
}

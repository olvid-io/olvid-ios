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



struct ObvSimpleListItemView: View {
    
    private let title: Text
    private let value: Text
    private let valueToCopyOnLongPress: String?
    
    @State private var showValueCopiedOverlay = false
    
    init(title: Text, value: String?) {
        self.title = title
        self.value = Text(value ?? "-")
        self.valueToCopyOnLongPress = value
    }
    
    init(title: Text, date: Date?) {
        self.title = title
        if let date = date {
            if #available(iOS 14, *) {
                self.value = Text(date, style: .date)
            } else {
                let df = DateFormatter()
                df.locale = Locale.current
                df.doesRelativeDateFormatting = true
                df.timeStyle = .short
                df.dateStyle = .short
                self.value = Text(df.string(from: date))
            }
        } else {
            self.value = Text("-")
        }
        self.valueToCopyOnLongPress = nil
    }
    
    var body: some View {
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
    }
}

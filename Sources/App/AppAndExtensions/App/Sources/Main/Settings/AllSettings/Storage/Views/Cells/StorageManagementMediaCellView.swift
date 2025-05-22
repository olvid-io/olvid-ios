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

@available(iOS 17.0, *)
struct StorageManagementMediaCellView<Model: StorageManagementMediaCellViewModelProtocol>: View {
    
    @State private var hasBeenLoaded: Bool = false
    
    enum CellStyle {
        case small
        case `default`
        
        var font: Font {
            switch self {
            case .small:
                return .caption
            case .default:
                return .callout
            }
        }
        
        var loaderSize: CGFloat {
            switch self {
            case .small:
                return 16
            case .default:
                return 24
            }
        }
    }
    
    var model: Model
    let style: CellStyle
    
    init(model: Model, style: CellStyle = .default) {
        self.model = model
        self.style = style
    }
    
    var body: some View {
        
//        let _ = Self._printChanges() // Use to print changes to observable
        
        ZStack {
            if let image = model.image {
                Color.clear
                    .overlay (
                        image
                            .resizable()
                            .scaledToFill()
                    ).clipped()
            } else {
                if !hasBeenLoaded {
                    AnimatedLoader(strokeWidth: 2.0)
                        .frame(width: style.loaderSize,
                               height: style.loaderSize)
                } else {
                    model.placeHolderImage
                        .resizable()
                        .scaledToFit()
                        .frame(width: style.loaderSize * 2.0,
                               height: style.loaderSize * 2.0)
                        .opacity(0.6)
                        .foregroundStyle(Color(uiColor: .secondarySystemGroupedBackground))
                }
            }
                
            VStack {
                HStack {
                    if let icon = model.expirationIndicatorIcon {
                        icon
                            .foregroundStyle(.red.opacity(0.8))
                            .font(style.font)
                    }
                    Spacer()
                    Text(model.formattedSize)
                        .font(style.font)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 4)
                        .background(.thinMaterial, in: Capsule())
                }
                .padding(4.0)
                
                Spacer()
                
                HStack {
                    if let icon = model.icon, model.image != nil { // we don't want to display icon two times because if thumbnail cannot be loaded, we already display the icon
                        Text(icon)
                            .font(style.font)
                    }
                    
                    Spacer()
                    
                    if let duration = model.duration {
                        Text(duration)
                            .font(style.font)
                    }
                }
                .padding(4.0)
            }
            .foregroundStyle(.white)
        }
        .overlay {
            if model.isSelected {
                VStack() {
                    HStack() {
                        Image(systemIcon: .checkmark)
                            .font(.system(size: 12.0, weight: .bold))
                            .foregroundStyle(Color(uiColor: .label))
                            .padding(.horizontal, 6.0)
                            .padding(.vertical, 6.0)
                            .background(
                                RoundedRectangle(cornerRadius: 6.0)
                                    .fill(.thinMaterial)
                            )
                            .padding(.all, 4.0)
                        Spacer()
                    }
                    Spacer()
                }
                .background(Color.blue.opacity(0.4))
            }
        }
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .task {
            do {
                try await model.onTask()
                self.hasBeenLoaded = true
            } catch {
                self.hasBeenLoaded = true
            }
        }
    }
}

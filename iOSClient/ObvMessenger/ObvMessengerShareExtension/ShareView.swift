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


import ObvUI
import SwiftUI
import ObvUICoreData
import ObvDesignSystem
import ObvSettings


private enum ActiveSheet: Identifiable {
    case discussionsChooser
    case ownedIdentityChooser
    var id: Int { hashValue }
}

struct ShareView: View {

    @ObservedObject var model: ShareViewModel
    @State private var activeSheet: ActiveSheet? = nil
    @State private var isFocused: Bool = true

    /// This height allows to have the same height for both bars. It is acceptable for almost all size categories (available via @Environment(\.sizeCategory) var sizeCategory if required)
    private var barHeight: CGFloat {
        return 50
    }
    
    var body: some View {
        VStack(spacing: 0) {
            topBarView
                .padding()
            Divider()
            textArea
                .padding(.horizontal)
            Divider()
            if let thumbnails = model.thumbnails, !thumbnails.isEmpty {
                attachmentsPreviewView(for: thumbnails)
                    .padding()
                Divider()
            }
            profileSelectionBarView
                .disabled(model.messageIsSending)
                .padding()
                .frame(height: barHeight)
            Divider()
            bottomBarView
                .disabled(model.messageIsSending)
                .padding()
                .frame(height: barHeight)
        }
        .onDisappear(perform: {
            model.viewIsDisappeared()
        })
        .sheet(item: $activeSheet) { item in
            switch item {
            case .discussionsChooser:
                navigationViewPresentingDiscussionView
            case .ownedIdentityChooser:
                navigationViewPresentingOwnedIdentityChooserView
            }
        }
        .disabled(model.isDisabled)
    }
    
    private var topBarView: some View {
        HStack {
            Button(action: {
                model.userWantsToCloseView()
            }) {
                Image(systemIcon: .xmarkCircleFill)
                    .font(Font.system(size: 24, weight: .semibold, design: .default))
                    .foregroundColor(Color(AppTheme.shared.colorScheme.tertiaryLabel))
            }
            .disabled(model.messageIsSending)
            Spacer()
            Image("badge")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
            Spacer()
            Button(action: {
                isFocused = false
                model.userWantsToSendMessages(to: model.selectedDiscussions)
            }) {
                Image(systemIcon: .paperplaneFill)
                    .font(Font.system(size: 24, weight: .semibold, design: .default))
            }
            .disabled(!model.userCanSendsMessages || model.messageIsSending)
        }
    }
    
    private var textArea: some View {
        ZStack {
            TextEditor(text: model.textBinding)
            if model.textBinding.wrappedValue.isEmpty {
                textEditorPlaceholderView
            }
        }
    }
    
    
    /// This is a hack allowing to add a text placeholder view above the TextEditor. Values for the top and leading paddings are best guesses and seem to work for larger text sizes too.
    private var textEditorPlaceholderView: some View {
        VStack {
            HStack {
                Text("YOUR_MESSAGE")
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    .allowsHitTesting(false)
                    .font(.body)
                Spacer()
            }
            Spacer()
        }
    }
    
    private func attachmentsPreviewView(for thumbnails: [ShareViewModel.Thumbnail]) -> some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(thumbnails) { thumbnail in
                    switch thumbnail.value {
                    case .loading:
                        ZStack {
                            RoundedRectangle(cornerRadius: 10.0)
                                .foregroundColor(.secondary)
                                .aspectRatio(1.0, contentMode: .fill)
                            ProgressView()
                        }
                        .frame(height: 100)
                    case .image(let image):
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .cornerRadius(10.0)
                            .frame(height: 100)
                    case .symbol(let icon):
                        ZStack {
                            RoundedRectangle(cornerRadius: 10.0)
                                .stroke(Color.secondary, lineWidth: 1)
                                .foregroundColor(.clear)
                                .aspectRatio(1.0, contentMode: .fill)
                            Image(systemIcon: icon)
                                .font(Font.system(size: 36, weight: .heavy, design: .rounded))
                        }
                        .frame(height: 100)
                    }
                }
            }
        }
    }
    
    private var profileSelectionBarView: some View {
        Button {
            activeSheet = .ownedIdentityChooser
        } label: {
            HStack {
                Text(LocalizedStringKey("SHARE_VIEW_PROFILE_SELECTION_BAR_TITLE"))
                    .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                Spacer()
                CircledInitialsView(configuration: model.selectedOwnedIdentity.circledInitialsConfiguration,
                                    size: .small,
                                    style: ObvMessengerSettings.Interface.identityColorStyle)
                Image(systemIcon: .chevronRight)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
            }
        }
    }
    
    private var bottomBarView: some View {
        Button {
            activeSheet = .discussionsChooser
        } label: {
            HStack {
                Text(LocalizedStringKey("Discussions"))
                    .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                Spacer()
                Text("CHOOSE_OR_\(model.selectedDiscussions.count)_CHOSEN_DISCUSSION")
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                Image(systemIcon: .chevronRight)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
            }
        }
    }
    
    private var navigationViewPresentingOwnedIdentityChooserView: some View {
        NavigationView {
            ownedIdentityChooserView
                .onChange(of: model.selectedOwnedIdentity) { _ in
                    activeSheet = nil
                }
        }
    }
    
    private var ownedIdentityChooserView: some View {
        OwnedIdentityChooserView(currentOwnedCryptoId: model.selectedOwnedIdentity.cryptoId,
                                 ownedIdentities: model.allOwnedIdentities,
                                 delegate: model)
        .navigationBarItems(leading: Button(action: {
            activeSheet = nil
        }, label: {
            Image(systemIcon: .xmarkCircleFill)
                .font(Font.system(size: 24, weight: .semibold, design: .default))
                .foregroundColor(Color(AppTheme.shared.colorScheme.tertiaryLabel))
        }))
    }
    
    
    private var navigationViewPresentingDiscussionView: some View {
        NavigationView {
            DiscussionsView(model: model.discussionsModel,
                            ownedCryptoId: model.selectedOwnedIdentity.cryptoId)
            .navigationBarItems(trailing: Button(action: {
                activeSheet = nil
            }, label: {
                Text(CommonString.Word.Cancel)
            }))
        }
    }
}

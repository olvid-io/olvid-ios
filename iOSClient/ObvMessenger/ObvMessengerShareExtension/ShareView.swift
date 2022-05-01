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
import QuickLookThumbnailing
import MobileCoreServices

protocol ShareViewModelDelegate: AnyObject {
    func closeView()
    func userWantsToSendMessages(to discussions: [PersistedDiscussion]) async
}

fileprivate enum ThumbnailValue {
    case loading
    case symbol(_ symbol: ObvSystemIcon)
    case image(_ image: UIImage)
}

fileprivate struct Thumbnail: Identifiable {
    let index: Int
    let value: ThumbnailValue
    var id: Int { index }
}

final class ShareViewModel: ObservableObject, DiscussionsHostingViewControllerDelegate {

    @Published private(set) var text: String = ""
    @Published private(set) var selectedDiscussions: [PersistedDiscussion] = []
    @Published fileprivate var thumbnails: [Thumbnail]? = nil
    @Published private(set) var selectedOwnedIdentity: PersistedObvOwnedIdentity
    @Published private(set) var messageIsSending: Bool = false
    @Published private(set) var bodyTextHasBeenSet: Bool = false

    private var viewIsClosing: Bool = false
    private(set) var hardlinks: [HardLinkToFyle?]? = nil

    let allOwnedIdentities: [PersistedObvOwnedIdentity]

    init(allOwnedIdentities: [PersistedObvOwnedIdentity]) {
        self.allOwnedIdentities = allOwnedIdentities
        assert(allOwnedIdentities.count == 1)
        self.selectedOwnedIdentity = allOwnedIdentities.first!
    }

    weak var delegate: ShareViewModelDelegate?

    func setSelectedDiscussions(to discussions: [PersistedDiscussion]) {
        self.selectedDiscussions = discussions
    }

    func setBodyTexts(_ bodyTexts: [String]) {
        assert(!self.bodyTextHasBeenSet)
        for bodyText in bodyTexts {
            text.append(bodyText)
        }
        DispatchQueue.main.async {
            self.bodyTextHasBeenSet = true
        }
    }

    func setHardlinks(_ hardlinks: [HardLinkToFyle?]) {
        self.hardlinks = hardlinks
        var thumbnails = [Thumbnail]()
        for index in 0..<hardlinks.count {
            thumbnails += [Thumbnail(index: index, value: .loading)]
        }
        DispatchQueue.main.async {
            withAnimation {
                self.thumbnails = thumbnails
            }
        }
        Task {
            for index in 0..<hardlinks.count {
                guard let hardlink = hardlinks[index] else { assertionFailure(); continue }
                let symbolOrImage = await createThumbnail(hardlink: hardlink)
                DispatchQueue.main.async {
                    withAnimation {
                        self.thumbnails?[index] = Thumbnail(index: index, value: symbolOrImage)
                    }
                }
            }
        }
    }

    var userCanSendsMessages: Bool {
        guard !messageIsSending else { return false }
        return !selectedDiscussions.isEmpty
    }

    var discussionsModel: DiscussionsViewModel {
        let model = DiscussionsViewModel(ownedIdentity: selectedOwnedIdentity,
                                         selectedDiscussions: selectedDiscussions)
        model.delegate = self
        return model
    }

    var textBinding: Binding<String> {
        .init {
            self.text
        } set: {
            // Allow to disable TextField until bodyTexts have been set
            guard self.bodyTextHasBeenSet else { return }
            self.text = $0
        }

    }

    func userWantsToCloseView() {
        guard !viewIsClosing else { return }
        viewIsClosing = true
        delegate?.closeView()
    }

    func viewIsDisappeared() {
        guard !viewIsClosing else { return } // Avoid to execute twice closeView if the user has tap close button
        guard !messageIsSending else { return } // Avoid to execute twice closeView if the user wants to send the message
        delegate?.closeView()
    }

    func userWantsToSendMessages(to discussions: [PersistedDiscussion]) {
        guard !messageIsSending else { return }
        self.messageIsSending = true
        Task {
            await delegate?.userWantsToSendMessages(to: discussions)
        }
    }

    private func createThumbnail(hardlink: HardLinkToFyle?) async -> ThumbnailValue {
        guard let hardlink = hardlink else { return .symbol(.paperclip) }
        guard let hardlinkURL = hardlink.hardlinkURL else { return .symbol(.paperclip) }
        let scale = await UIScreen.main.scale
        let size = CGSize(width: 80, height: 80)
        let request = QLThumbnailGenerator.Request(fileAt: hardlinkURL, size: size, scale: scale, representationTypes: .thumbnail)
        let generator = QLThumbnailGenerator.shared
        do {
            let thumbnail = try await generator.generateBestRepresentation(for: request)
            return .image(thumbnail.uiImage)
        } catch {
            let uti = hardlink.uti
            // See CoreServices > UTCoreTypes
            if ObvUTIUtils.uti(uti, conformsTo: "org.openxmlformats.wordprocessingml.document" as CFString) {
                // Word (docx) document
                return .symbol(.docFill)
            } else if ObvUTIUtils.uti(uti, conformsTo: kUTTypeArchive) {
                // Zip archive
                return .symbol(.rectangleCompressVertical)
            } else if ObvUTIUtils.uti(uti, conformsTo: kUTTypeWebArchive) {
                // Web archive
                return .symbol(.archiveboxFill)
            } else {
                return .symbol(.paperclip)
            }
        }
    }



}

private enum ActiveSheet: Identifiable {
    case discussionsChooser
    var id: Int { hashValue }
}

struct ShareView: View {

    @ObservedObject var model: ShareViewModel
    @State private var activeSheet: ActiveSheet? = nil
    @available(iOSApplicationExtension 15.0, *)
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
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
                    if #available(iOSApplicationExtension 15.0, *) {
                        isFocused = false
                    }
                    model.userWantsToSendMessages(to: model.selectedDiscussions)
                }) {
                    Image(systemIcon: .paperplaneFill)
                        .font(Font.system(size: 24, weight: .semibold, design: .default))
                }
                .disabled(!model.userCanSendsMessages || model.messageIsSending)
            }
            .padding()
            Divider()
            Group {
                if #available(iOSApplicationExtension 15.0, *) {
                    TextEditor(text: model.textBinding)
                        .focused($isFocused)
                } else if #available(iOSApplicationExtension 14.0, *) {
                    TextEditor(text: model.textBinding)
                } else {
                    TextField(LocalizedStringKey("YOUR_MESSAGE"), text: model.textBinding)
                }
            }
            .padding(.horizontal)
            Divider()
            if let thumbnails = model.thumbnails, !thumbnails.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(thumbnails) { thumbnail in
                            switch thumbnail.value {
                            case .loading:
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10.0)
                                        .foregroundColor(.secondary)
                                        .aspectRatio(1.0, contentMode: .fill)
                                    ObvProgressView()
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
                .padding()
                Divider()
            }
            Button {
                activeSheet = .discussionsChooser
            } label: {
                HStack {
                    Text(LocalizedStringKey("Discussions"))
                        .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                    Spacer()
                    Text(String.localizedStringWithFormat(NSLocalizedString("CHOOSE_OR_NUMBER_OF_CHOSEN_DISCUSSION", comment: ""), model.selectedDiscussions.count))
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    Image(systemIcon: .chevronRight)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                }
            }
            .disabled(model.messageIsSending)
            .padding()
        }
        .onAppear {
            if #available(iOSApplicationExtension 15.0, *) {
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                    self.isFocused = true
                }
            }
        }
        .onDisappear(perform: {
            model.viewIsDisappeared()
        })
        .sheet(item: $activeSheet) { item in
            switch item {
            case .discussionsChooser:
                NavigationView {
                    DiscussionsView(model: model.discussionsModel)
                        .navigationBarItems(leading: Button(action: {
                            activeSheet = nil
                        },
                                                            label: {
                            Image(systemIcon: .xmarkCircleFill)
                                .font(Font.system(size: 24, weight: .semibold, design: .default))
                                .foregroundColor(Color(AppTheme.shared.colorScheme.tertiaryLabel))
                        }),
                                            trailing: Button(action: {
                            activeSheet = nil
                        }, label: {
                            Text("Choose")
                        }))
                }
            }
        }
    }
}

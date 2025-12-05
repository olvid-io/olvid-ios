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
import ObvAppTypes
import ObvDesignSystem
import ObvTypes
import CoreData
import ObvCells


public struct SharingProfileViewModel: Sendable, Equatable {

    public enum ScanStep: Sendable {
        case noScan
        case firstScan
    }
    public let fullName: String?
    public let role: String?
    public let urlIdentityRepresentation: URL?
    public let avatarModel: ObvAvatarViewModel
    public let scanStep: ScanStep
    public let isURLScanned: Bool
    
    public init(fullName: String?,
                role: String?,
                urlIdentityRepresentation: URL?,
                avatarModel: ObvAvatarViewModel,
                scanStep: ScanStep,
                isURLScanned: Bool = false) {
        self.urlIdentityRepresentation = urlIdentityRepresentation
        self.avatarModel = avatarModel
        self.fullName = fullName
        self.role = role
        self.scanStep = scanStep
        self.isURLScanned = isURLScanned
    }
}


@MainActor
public protocol ObvSharingProfileViewDataSource {
    func getAsyncStreamOfInvitationFlowViewModel(_ view: SharingProfileView, currentOwnedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<SharingProfileViewModel>)
    func finishAsyncStreamOfInvitationFlowViewModel(_ view: SharingProfileView, streamUUID: UUID)
}


public struct SharingProfileView: View {
    
    let currentOwnedCryptoId: ObvCryptoId
    let router: InvitationFlowRouter

    let actions = [SharingAction.share, .copy]
    
    @State private var streamedViewModel: SharingProfileViewModel?
    
    private var viewModel: SharingProfileViewModel? {
        self.streamedViewModel
    }
    
    init(currentOwnedCryptoId: ObvCryptoId, router: InvitationFlowRouter) {
        self.currentOwnedCryptoId = currentOwnedCryptoId
        self.router = router
    }
    
    enum SharingAction: Int {
        case share
        case copy
        case download
                
        private var image: Image {
            switch self {
            case .share:
                return Image(systemIcon: .squareAndArrowUp)
            case .copy:
                return Image(systemIcon: .link)
            case .download:
                return Image(systemIcon: .squareAndArrowDown)
            }
        }
        
        var actionButton: some View {
            ZStack {
                image
                    .tint(.white)
                    .frame(width: 58, height: 58)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22.0)
                            .stroke(.white.opacity(0.2), lineWidth: 1.0)
                    }
            }
        }
        
        var title: Text {
            switch self {
            case .share:
                return Text("PROFILE_SHARE_TITLE")
            case .copy:
                return Text("PROFILE_COPY_TITLE")
            case .download:
                return Text("PROFILE_DOWNLOAD_TITLE")
            }

        }
    }
    
    @State private var isSuccessfulOwnedIdentityCopyAlertShown: Bool = false
    
    func actionToPerform(for action: SharingAction) {
        guard let urlIdentityRepresentation = viewModel?.urlIdentityRepresentation else { return }
        switch action {
        case .share: () // Do Nothing
        case .copy:
            UIPasteboard.general.string = urlIdentityRepresentation.absoluteString
            isSuccessfulOwnedIdentityCopyAlertShown = true
        case .download:
            print("Download")
        }
    }
    
    @ViewBuilder
    public var content: some View {
        if let viewModel {
            VStack {
                
                Spacer()
                
                VStack(alignment: .center, spacing: 8.0) {
                    ZStack {
                        ObvAvatarView(model: viewModel.avatarModel,
                                      style: .circle,
                                      size: .custom(frameSize: CGSize(width: 200, height: 200)),
                                      dataSource: router.avatarViewDataSource)
                        Circle()
                            .stroke(.white.opacity(0.4), lineWidth: 4.0)
                            .frame(width: 196.0)
                    }
                    .padding(.bottom, 16.0)
                    
                    if let fullName = viewModel.fullName {
                        Text(fullName)
                            .font(.title2)
                            .fontWeight(.heavy)
                    }
                    
                    if let role = viewModel.role {
                        Text(role)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                HStack(alignment: .center, spacing: 24.0) {
                    ForEach(actions, id: \.self) { action in
                        VStack(alignment: .center, spacing: 8.0) {
                            if action == .share, let urlIdentityRepresentation = viewModel.urlIdentityRepresentation {
                                ShareLink(item: urlIdentityRepresentation,
                                          subject: Text("\(viewModel.fullName ?? "") invites you to discuss on Olvid"),
                                          message: Text("\(viewModel.fullName ?? "") invites you to discuss on Olvid. To accept, please click the link")) {
                                    action.actionButton
                                }
                            } else {
                                Button {
                                    actionToPerform(for: action)
                                } label: {
                                    action.actionButton
                                }
                            }
                            
                            action.title
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            }
            .padding(.top, 8.0)
            .padding(.bottom, 50.0)
        } else {
            ProgressView()
                .tint(.white)
        }
    }
    
    public var contentBody: some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if #available(iOS 26.0, *) {
                        Button(role: .close) { router.dismiss() }
                    } else {
                        Button(action: { router.dismiss() }) {
                            Image(systemIcon: .xmark)
                                .foregroundColor(.black)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color(UIColor.white.withAlphaComponent(0.6)))) // Customize the color
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("SHARING_PROFILE_TITLE")
                        .foregroundColor(.white)
                        .font(.headline)
                        .fontWeight(.bold)
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .padding(.horizontal, 24.0)
            .background(.thinMaterial)
            .environment(\.colorScheme, .dark)
            .task(onTaskForAsyncStreamOfInvitationFlowViewModel)
            .alert(String(localizedInThisBundle: "YOUR_ID_WAS_COPIED_TO_CLIPBOARD"), isPresented: $isSuccessfulOwnedIdentityCopyAlertShown, actions: {})
    }
    
    public var body: some View {
        if #available(iOS 16.4, *) {
            contentBody
                .presentationBackground(.clear)
        } else {
            contentBody
        }
    }
}

extension SharingProfileView {
    
    func onTaskForAsyncStreamOfInvitationFlowViewModel() async {
        do {
            let (streamUUID, stream) = try await router.sharingProfileViewDataSource.getAsyncStreamOfInvitationFlowViewModel(self, currentOwnedCryptoId: self.currentOwnedCryptoId)
            for await model in stream {
                withAnimation {
                    self.streamedViewModel = model
                }
            }
            router.sharingProfileViewDataSource.finishAsyncStreamOfInvitationFlowViewModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
}

#if DEBUG

@MainActor
private let minimalDataSourceForPreviews = MinimalDataSourceAndActionsForPreviews()

#Preview {
    NavigationStack {
        SharingProfileView(currentOwnedCryptoId: ObvCryptoId.sampleOwnedCryptoId,
                           router: InvitationFlowRouter.initForPreviews())
    }
}

#endif

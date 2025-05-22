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
import ObvDesignSystem


protocol ProfileRestoredConfirmationViewActionsProtocol: AnyObject {
    @MainActor func restoreProfileBackupFromServerNow(profileBackupFromServerToRestore: ObvProfileBackupFromServer, rawAuthState: Data?) async throws -> ObvRestoredOwnedIdentityInfos
    @MainActor func userWantsToOpenProfile(ownedCryptoId: ObvCryptoId)
    @MainActor func userWantsToRestoreAnotherProfile()
    @MainActor func fetchAvatarImage(profileCryptoId: ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage?
    @MainActor func navigateToErrorViewAsRestorationFailed(error: Error)
}


struct ProfileRestoredConfirmationView: View, ObvAvatarLegacyViewActions {
        
    let model: Model
    let actions: any ProfileRestoredConfirmationViewActionsProtocol
    
    struct Model {
        let profileBackupFromServerToRestore: ObvProfileBackupFromServer
        let rawAuthState: Data?
    }
    
    @State private var restoredOwnedIdentity: ObvRestoredOwnedIdentityInfos?

    
    func fetchAvatarImageOfSize(_ size: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        let profileCryptoId = model.profileBackupFromServerToRestore.ownedCryptoId
        let encodedPhotoServerKeyAndLabel = model.profileBackupFromServerToRestore.parsedData.encodedPhotoServerKeyAndLabel
        return await actions.fetchAvatarImage(profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: size)
    }

    
    private func onTask() async {
        do {
            
            let restoredOwnedIdentity = try await actions.restoreProfileBackupFromServerNow(profileBackupFromServerToRestore: model.profileBackupFromServerToRestore,
                                                                                            rawAuthState: model.rawAuthState)
            withAnimation {
                self.restoredOwnedIdentity = restoredOwnedIdentity
            }
        } catch {
            actions.navigateToErrorViewAsRestorationFailed(error: error)
        }
    }
    
    
    private struct WaitingView: View {
        var body: some View {
            VStack {
                ProgressView()
                    .padding()
                    .progressViewStyle(.circular)
                Text("ONE_MOMENT_PLEASE")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                Text("PLEASE_WAIT_WHILE_WE_RESTORE_YOUR_PROFILE")
                    .multilineTextAlignment(.center)
                    .font(.headline)
            }
        }
    }
    
    
    private struct CheckMark: View {
        var body: some View {
            Image(systemIcon: .checkmarkCircleFill)
                .font(.system(size: 18))
                .foregroundStyle(Color(UIColor.systemGreen))
                .background(
                    ZStack {
                        Circle().foregroundStyle(Color(UIColor.systemBackground))
                        Circle().padding(1).foregroundStyle(Color(.white))
                    }
                )
        }
    }
    
    
    var body: some View {
        if let restoredOwnedIdentity {
            ScrollView {
                
                VStack {
                    
                    HeaderView()
                        .padding(.horizontal)
                        .padding(.bottom)
                    
                    VStack {
                        
                        ObvAvatarLegacyView(model: restoredOwnedIdentity.avatar, actions: self)
                            .overlay(alignment: .topTrailing) {
                                if !restoredOwnedIdentity.isKeycloakManaged {
                                    CheckMark()
                                        .offset(x: 4, y: -4)
                                }
                            }
                        
                        VStack {
                            Text(restoredOwnedIdentity.firstNameThenLastName)
                                .font(.title2)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                            Text(restoredOwnedIdentity.positionAtCompany)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.bottom)
                        
                        Button {
                            actions.userWantsToOpenProfile(ownedCryptoId: restoredOwnedIdentity.ownedCryptoId)
                        } label: {
                            HStack {
                                Spacer(minLength: 0)
                                Text("OPEN_PROFILE")
                                Spacer(minLength: 0)
                            }
                            .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button {
                            actions.userWantsToRestoreAnotherProfile()
                        } label: {
                            HStack {
                                Spacer(minLength: 0)
                                Text("RESTORE_ANOTHER_PROFILE")
                                Spacer(minLength: 0)
                            }
                            .padding()
                        }
                        .buttonStyle(.bordered)
                        
                    }
                    .padding()
                    .background(RoundedRectangle(cornerSize: .init(width: 12, height: 12)).foregroundStyle(Color(UIColor.tertiarySystemFill)))
                    .padding()
                    
                }
                
            }
                
        } else {
            WaitingView()
                .task { await onTask() }
        }
    }
}


// MARK: - Header, checkmark, etc.

private struct HeaderView: View {
    
    @State private var isBadgeVisible = false
    
    private func onAppear() {
        withAnimation(.bouncy(duration: 0.7)) {
            isBadgeVisible = true
        }
    }
    
    private struct CheckMarkImage: View {
        var body: some View {
            Image(systemIcon: .checkmarkCircleFill)
                .font(.system(size: 64))
                .foregroundStyle(Color(UIColor.systemGreen))
                .background(
                    Circle().foregroundStyle(Color(.white))
                        .frame(width: 60, height: 60)
                )
        }
    }
    
    var body: some View {
        VStack {
            ZStack {
                if isBadgeVisible {
                    if #available(iOS 17.0, *) {
                        CheckMarkImage()
                            .transition(CheckMarkTransition())
                    } else {
                        CheckMarkImage()
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                CheckMarkImage()
                    .opacity(0)
            }
            Text("PROFILE_RESTORED")
                .font(.title)
                .padding(.top, 4)
        }
        .onAppear {
            onAppear()
        }
    }
}




@available(iOS 17.0, *)
private struct CheckMarkTransition: Transition {
    public func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(phase.isIdentity ? 1 : 0.5)
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity ? 0 : 20)
    }
}



// MARK: - Previews

#if DEBUG

private final class ActionsForPreviews: ProfileRestoredConfirmationViewActionsProtocol {
    
    func fetchAvatarImage(profileCryptoId: ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        let actions = AvatarActionsForPreviews()
        return await actions.fetchAvatarImage(profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }
    
    
    func restoreProfileBackupFromServerNow(profileBackupFromServerToRestore: ObvProfileBackupFromServer, rawAuthState: Data?) async throws -> ObvRestoredOwnedIdentityInfos {
        try await Task.sleep(seconds: 2)

        // Uncomment to simulate restoration failure
        // throw ObvErrorForPreviews.someError

        let restoredOwnedIdentityInfos = ObvRestoredOwnedIdentityInfos(ownedCryptoId: PreviewsHelper.cryptoIds.first!,
                                                                       firstNameThenLastName: PreviewsHelper.coreDetails.first!.getDisplayNameWithStyle(.firstNameThenLastName),
                                                                       positionAtCompany: PreviewsHelper.coreDetails.first!.getDisplayNameWithStyle(.positionAtCompany),
                                                                       displayedLetter: PreviewsHelper.coreDetails.first!.getDisplayNameWithStyle(.firstNameThenLastName).first ?? "A",
                                                                       isKeycloakManaged: false)
        return restoredOwnedIdentityInfos
        
    }
    
    
    func userWantsToRestoreAnotherProfile() {}
    
    func userWantsToOpenProfile(ownedCryptoId: ObvCryptoId) {}
    
    func navigateToErrorViewAsRestorationFailed(error: any Error) {}
    
    enum ObvErrorForPreviews: Error {
        case someError
    }
    
}


#Preview {
    ProfileRestoredConfirmationView(model: .init(profileBackupFromServerToRestore: ProfileBackupsForPreviews.profileBackups.first!, rawAuthState: nil), actions: ActionsForPreviews())
}


#Preview("Header") {
    HeaderView()
}

#endif

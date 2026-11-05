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
import ObvTypes
import ObvSystemIcon
import ObvAppCoreConstants
import ObvDesignSystem


/// Delegate protocol through which `ScannedServerAndAPIKeyView` requests actions from its coordinator.
///
/// This is the screen shown when, during onboarding, the user scans (or taps, e.g. from the Camera app)
/// an `OlvidURL` carrying a `ServerAndAPIKey` (a license). The view displays the scanned server and the
/// rights granted by the API key, and lets the user accept or decline it.
///
/// We intentionally expose the SwiftUI view's actions protocol directly: the UIKit hosting controller is
/// kept as thin as possible (no protocol of its own) since the onboarding module is moving to full SwiftUI.
///
/// Marked `@MainActor` because all callbacks originate from SwiftUI button taps and are forwarded to the
/// onboarding flow controller, which lives on the main actor.
@MainActor
protocol ScannedServerAndAPIKeyViewActionsProtocol {

    /// Queries the server for the elements (status + permissions) of the scanned API key.
    ///
    /// This works without an owned identity, so it can be called before any profile exists. The returned
    /// `APIKeyElements` drives what the screen displays and gates the "accept" button.
    func queryAPIKeyElements(_ view: ScannedServerAndAPIKeyView, serverAndAPIKey: ServerAndAPIKey) async throws -> APIKeyElements

    /// Called when the user accepts both the scanned custom server (if any) and the usable API key.
    /// Only reachable once the rights have loaded and the key can still be activated.
    func userAcceptsScannedServerAndAPIKey(_ view: ScannedServerAndAPIKeyView, serverAndAPIKey: ServerAndAPIKey)

    /// Called when the user accepts only the scanned custom server, discarding the API key.
    ///
    /// This happens when the scanned key points to a custom server but has already been used (so it can no longer
    /// be activated): we still keep the custom server, but there is nothing to register for the key itself.
    func userAcceptsScannedServerOnly(_ view: ScannedServerAndAPIKeyView, server: URL)

    /// Called when the user declines the scanned key (or otherwise dismisses the screen).
    func userWantsToDismiss(_ view: ScannedServerAndAPIKeyView)

}


struct ScannedServerAndAPIKeyView: View {

    let model: Model
    let actions: ScannedServerAndAPIKeyViewActionsProtocol

    @State private var status: APIKeyElementsQueryStatus = .toQuery


    struct Model {
        let serverAndAPIKey: ServerAndAPIKey
        let defaultServerURL: URL // value of ObvAppCoreConstants.serverURL
        /// `true` when the scanned key points to a server other than the default Olvid server.
        var isUsingCustomServer: Bool {
            self.serverAndAPIKey.server != defaultServerURL
        }
    }


    /// Tracks the asynchronous query of the API key's rights from the server.
    private enum APIKeyElementsQueryStatus {
        case toQuery
        case querying
        case queryFailed
        case queried(apiKeyElements: APIKeyElements)
    }


    /// A single-use key that was already consumed comes back with `.licensesExhausted`.
    private func apiKeyWasAlreadyUsed(_ apiKeyElements: APIKeyElements) -> Bool {
        apiKeyElements.status == .licensesExhausted
    }


    /// What validating the screen with the primary button does, given the loaded rights.
    ///
    /// We always keep a custom server (if the scanned key points to one); we only keep the API key itself when it
    /// has not already been used. So an already-used key on the default server leaves nothing to keep, in which
    /// case the primary button is just a dismiss. `nil` until the rights have loaded (button disabled).
    private enum PrimaryButtonAction {
        case acceptServerAndAPIKey(ServerAndAPIKey)
        case acceptServerOnly(server: URL)
        case dismiss
    }


    private var primaryButtonAction: PrimaryButtonAction? {
        guard case .queried(let apiKeyElements) = status else { return nil }
        if apiKeyWasAlreadyUsed(apiKeyElements) {
            if model.isUsingCustomServer {
                // The key is unusable, but we still keep the custom server it points to.
                return .acceptServerOnly(server: model.serverAndAPIKey.server)
            } else {
                // Nothing to keep: the button is equivalent to the cancel button.
                return .dismiss
            }
        } else {
            return .acceptServerAndAPIKey(model.serverAndAPIKey)
        }
    }


    /// Title and icon of the primary button, reflecting what validating would actually do.
    private var primaryButtonLabel: (titleKey: LocalizedStringKey, systemIcon: SystemIcon) {
        switch primaryButtonAction {
        case .acceptServerAndAPIKey, .none:
            return ("SCANNED_API_KEY_ACCEPT_BUTTON", .checkmarkCircleFill)
        case .acceptServerOnly:
            return ("SCANNED_API_KEY_USE_SERVER_BUTTON", .checkmarkCircleFill)
        case .dismiss:
            return ("SCANNED_API_KEY_CLOSE_BUTTON", .xmarkCircleFill)
        }
    }


    private func primaryButtonTapped() {
        switch primaryButtonAction {
        case .acceptServerAndAPIKey(let serverAndAPIKey):
            actions.userAcceptsScannedServerAndAPIKey(self, serverAndAPIKey: serverAndAPIKey)
        case .acceptServerOnly(let server):
            actions.userAcceptsScannedServerOnly(self, server: server)
        case .dismiss:
            actions.userWantsToDismiss(self)
        case .none:
            break
        }
    }


    private func performQueryIfNeeded() async {
        switch status {
        case .querying, .queried:
            return
        case .toQuery, .queryFailed:
            await performQuery()
        }
    }


    private func performQuery() async {
        withAnimation { status = .querying }
        do {
            let apiKeyElements = try await actions.queryAPIKeyElements(self, serverAndAPIKey: model.serverAndAPIKey)
            withAnimation { status = .queried(apiKeyElements: apiKeyElements) }
        } catch {
            withAnimation { status = .queryFailed }
        }
    }


    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    /// Screen background, matching `OlvidShopView`: a subtle grey behind the cards in light mode,
    /// the plain system background in dark mode (where the cards become the lighter surface).
    private var screenBackgroundColor: Color {
        colorScheme == .dark ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground)
    }

    var body: some View {

        VStack(spacing: 0) {

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    ObvHeaderView(title: "SCANNED_API_KEY_TITLE".localizedInThisBundle,
                                  subtitle: "SCANNED_API_KEY_EXPLANATION".localizedInThisBundle)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 32)

                    ScannedServerView(server: model.serverAndAPIKey.server)
                        .padding(.bottom, 28)

                    SectionHeaderView(titleKey: "SCANNED_API_KEY_PERMISSIONS_SECTION_TITLE")
                        .padding(.bottom, 12)

                    switch status {

                    case .toQuery, .querying:

                        QueryingPermissionsView()

                    case .queryFailed:

                        QueryFailedView { Task { await performQuery() } }

                    case .queried(apiKeyElements: let apiKeyElements):

                        if apiKeyWasAlreadyUsed(apiKeyElements) {
                            APIKeyAlreadyUsedView()
                                .staggeredEntrance(index: 0)
                        } else {
                            VStack(spacing: 12) {
                                PermissionCardView(kind: .secureCalls,
                                                   isGranted: apiKeyElements.permissions.contains(.canCall))
                                    .staggeredEntrance(index: 0)
                                PermissionCardView(kind: .multidevice,
                                                   isGranted: apiKeyElements.permissions.contains(.multidevice))
                                    .staggeredEntrance(index: 1)
                            }
                        }

                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal)
                .padding(.top)
            }

            OlvidButtonNew {
                primaryButtonTapped()
            } label: {
                Label(primaryButtonLabel.titleKey, systemIcon: primaryButtonLabel.systemIcon)
            }
            .disabled(primaryButtonAction == nil)
            .padding()

        }
        .background(screenBackgroundColor)
        .task(performQueryIfNeeded)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                ObvButtonWithCancelRole(action: { actions.userWantsToDismiss(self) })
            }
        }
    }
}


// MARK: - SectionHeaderView

private struct SectionHeaderView: View {

    let titleKey: LocalizedStringKey

    var body: some View {
        Text(titleKey)
            .font(.system(.headline, design: .rounded, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}


// MARK: - StaggeredEntrance

/// A subtle "rise and fade-in" entrance, staggered by `index`, played once when the view appears.
///
/// Used to reveal the API key elements (permission cards, or the already-used notice) when the server query
/// resolves: each card eases up into place a beat after the previous one.
private struct StaggeredEntrance: ViewModifier {

    let index: Int

    @State private var hasAppeared = false

    private var delay: Double { Double(index) * 0.08 }

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 12)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(delay)) {
                    hasAppeared = true
                }
            }
    }
}

private extension View {
    func staggeredEntrance(index: Int) -> some View {
        modifier(StaggeredEntrance(index: index))
    }
}


// MARK: - ScannedServerView

/// Shows the scanned server. The design is identical whether it is the standard or a custom server.
private struct ScannedServerView: View {

    let server: URL

    /// The server URL without its scheme (e.g. `server.example.org` rather than `https://server.example.org`).
    private var serverDisplayString: String {
        var result = server.absoluteString
        if let scheme = server.scheme {
            let prefix = "\(scheme)://"
            if result.hasPrefix(prefix) {
                result.removeFirst(prefix.count)
            }
        }
        return result
    }

    var body: some View {
        ObvCapsuleCard(systemIcon: .serverRack, iconBackgroundColor: .blue) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SCANNED_API_KEY_SERVER_LABEL")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(verbatim: serverDisplayString)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}


// MARK: - PermissionCardView

private struct PermissionCardView: View {

    let kind: Kind
    let isGranted: Bool

    enum Kind {
        case secureCalls
        case multidevice

        var titleKey: LocalizedStringKey {
            switch self {
            case .secureCalls: return "SCANNED_API_KEY_PERMISSION_SECURE_CALLS"
            case .multidevice: return "SCANNED_API_KEY_PERMISSION_MULTIDEVICE"
            }
        }

        var subtitleKey: LocalizedStringKey {
            switch self {
            case .secureCalls: return "SCANNED_API_KEY_PERMISSION_SECURE_CALLS_BODY"
            case .multidevice: return "SCANNED_API_KEY_PERMISSION_MULTIDEVICE_BODY"
            }
        }

        var systemIcon: SystemIcon {
            switch self {
            case .secureCalls: return .phoneFill
            case .multidevice: return .macbookAndIphone
            }
        }

        var color: Color {
            switch self {
            case .secureCalls: return .orange
            case .multidevice: return .green
            }
        }
    }

    var body: some View {
        ObvCapsuleCard(systemIcon: kind.systemIcon,
                    iconBackgroundColor: isGranted ? kind.color : Color(UIColor.systemGray3)) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.titleKey)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text(kind.subtitleKey)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                GrantedBadge(isGranted: isGranted)
            }
        }
        .opacity(isGranted ? 1.0 : 0.5)
    }
}


// MARK: - GrantedBadge

private struct GrantedBadge: View {

    let isGranted: Bool

    var body: some View {
        Image(systemIcon: isGranted ? .checkmarkCircleFill : .xmarkCircleFill)
            .font(.title2)
            .foregroundStyle(isGranted ? Color.green : Color.secondary)
    }
}


// MARK: - QueryingPermissionsView

private struct QueryingPermissionsView: View {

    var body: some View {
        ObvCapsuleCard(systemIcon: .key, iconBackgroundColor: .blue) {
            HStack(spacing: 12) {
                Text("SCANNED_API_KEY_QUERYING_PERMISSIONS")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView()
            }
        }
    }
}


// MARK: - APIKeyAlreadyUsedView

private struct APIKeyAlreadyUsedView: View {

    var body: some View {
        ObvCapsuleCard(systemIcon: .exclamationmarkTriangleFill, iconBackgroundColor: .orange) {
            Text("SCANNED_API_KEY_ALREADY_USED")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}


// MARK: - QueryFailedView

private struct QueryFailedView: View {

    let retryAction: () -> Void

    var body: some View {
        ObvCapsuleCard(systemIcon: .exclamationmarkTriangleFill, iconBackgroundColor: .red) {
            VStack(alignment: .leading, spacing: 12) {
                Text("SCANNED_API_KEY_QUERY_FAILED")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: retryAction) {
                    Label("RETRY", systemIcon: .arrowClockwise)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
        }
    }
}


// MARK: - Previews

private final class ActionsForPreviews: ScannedServerAndAPIKeyViewActionsProtocol {

    enum Outcome {
        case success(APIKeyElements)
        case failure
    }

    private let outcome: Outcome

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func queryAPIKeyElements(_ view: ScannedServerAndAPIKeyView, serverAndAPIKey: ServerAndAPIKey) async throws -> APIKeyElements {
        try? await Task.sleep(seconds: 2.5)
        switch outcome {
        case .success(let elements):
            return elements
        case .failure:
            throw NSError(domain: "ScannedServerAndAPIKeyView.Previews", code: 0)
        }
    }

    func userAcceptsScannedServerAndAPIKey(_ view: ScannedServerAndAPIKeyView, serverAndAPIKey: ServerAndAPIKey) {}

    func userAcceptsScannedServerOnly(_ view: ScannedServerAndAPIKeyView, server: URL) {}

    func userWantsToDismiss(_ view: ScannedServerAndAPIKeyView) {}

}

@MainActor
private func makeModel(customServer: Bool) -> ScannedServerAndAPIKeyView.Model {
    let server = customServer ? URL(string: "https://server.example.org")! : URL.init(string: "https://server.olvid.io")!
    return .init(serverAndAPIKey: .init(server: server, apiKey: UUID()), defaultServerURL: URL.init(string: "https://server.olvid.io")!)
}

#Preview("Both rights, custom server") {
    NavigationStack {
        ScannedServerAndAPIKeyView(
            model: makeModel(customServer: true),
            actions: ActionsForPreviews(outcome: .success(.init(status: .valid, permissions: [.canCall, .multidevice], expirationDate: nil))))
    }
}

#Preview("Calls only, default server") {
    NavigationStack {
        ScannedServerAndAPIKeyView(
            model: makeModel(customServer: false),
            actions: ActionsForPreviews(outcome: .success(.init(status: .valid, permissions: [.canCall], expirationDate: nil))))
    }
}

#Preview("Already used, custom server") {
    NavigationStack {
        ScannedServerAndAPIKeyView(
            model: makeModel(customServer: true),
            actions: ActionsForPreviews(outcome: .success(.init(status: .licensesExhausted, permissions: [], expirationDate: nil))))
    }
}

#Preview("Already used, default server") {
    NavigationStack {
        ScannedServerAndAPIKeyView(
            model: makeModel(customServer: false),
            actions: ActionsForPreviews(outcome: .success(.init(status: .licensesExhausted, permissions: [], expirationDate: nil))))
    }
}

#Preview("Query failed") {
    NavigationStack {
        ScannedServerAndAPIKeyView(
            model: makeModel(customServer: true),
            actions: ActionsForPreviews(outcome: .failure))
    }
}

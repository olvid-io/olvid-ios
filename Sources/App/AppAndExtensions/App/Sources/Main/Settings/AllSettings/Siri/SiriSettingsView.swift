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
import ObvDesignSystem
import Intents

struct SiriSettingsView: View {
    
    @State private var navigationTitle: String = ""
    
    var body: some View {
        Form {
            
            ExplanationSectionView(navigationTitle: $navigationTitle)
            
            SiriToggleView()
            
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

fileprivate struct SiriToggleView: View {
    
    @State private var authorizationStatus: INSiriAuthorizationStatus = .notDetermined
    
    var body: some View {
        Section {
            Button {
                handleAuthorizationAction()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SIRI_AUTHORIZATION")
                        Text(statusDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    statusIcon
                        .foregroundStyle(statusColor)
                }
            }
        }
        .task {
            checkAuthorizationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            checkAuthorizationStatus()
        }
    }
    
    private var statusDescription: String {
        switch authorizationStatus {
        case .notDetermined:
            return String(localized: "SIRI_STATUS_NOT_DETERMINED")
        case .denied:
            return String(localized: "SIRI_STATUS_DENIED")
        case .restricted:
            return String(localized: "SIRI_STATUS_RESTRICTED")
        case .authorized:
            return String(localized: "SIRI_STATUS_AUTHORIZED")
        @unknown default:
            return String(localized: "SIRI_STATUS_UNKNOWN")
        }
    }
    
    private var statusIcon: some View {
        Group {
            switch authorizationStatus {
            case .notDetermined:
                Image(systemIcon: .questionmarkCircleFill)
            case .denied:
                Image(systemIcon: .xmarkCircleFill)
            case .restricted:
                Image(systemIcon: .exclamationmarkTriangleFill)
            case .authorized:
                Image(systemIcon: .checkmarkCircleFill)
            @unknown default:
                Image(systemIcon: .questionmarkCircleFill)
            }
        }
    }
    
    private var statusColor: Color {
        switch authorizationStatus {
        case .notDetermined:
            return .orange
        case .denied:
            return .red
        case .restricted:
            return .gray
        case .authorized:
            return .green
        @unknown default:
            return .gray
        }
    }
    
    private func checkAuthorizationStatus() {
        authorizationStatus = INPreferences.siriAuthorizationStatus()
    }
    
    private func handleAuthorizationAction() {
        switch authorizationStatus {
        case .notDetermined:
            requestSiriAuthorization()
        case .denied, .restricted, .authorized:
            openAppSettings()
        @unknown default:
            requestSiriAuthorization()
        }
    }
    
    private func requestSiriAuthorization() {
        INPreferences.requestSiriAuthorization { status in
            DispatchQueue.main.async {
                authorizationStatus = status
            }
        }
    }
    
    private func openAppSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
}

fileprivate struct ExplanationSectionView: View {
    
    @Binding var navigationTitle: String
    
    private func showNavigationTitle() {
        navigationTitle = String(localized: "Siri")
    }

    private func hideNavigationTitle() {
        navigationTitle = ""
    }
    
    var body: some View {
        Section {
            
            HStack {
                Spacer()
                VStack {
                    SiriIconView()
                        .frame(width: 64, height: 64)
                        .onDisappear(perform: showNavigationTitle)
                        .onAppear(perform: hideNavigationTitle)
                    Text("Siri")
                        .font(.title)
                        .fontWeight(.bold)
                }
                Spacer()
            }
            .listRowSeparator(.hidden)
            .padding(.top)

            Text("SIRI_EXPLANATION")
                .multilineTextAlignment(.center)
                .listRowSeparator(.hidden)

            Text("SIRI_WARNING")
                .multilineTextAlignment(.center)
                .listRowSeparator(.hidden)
                .padding(.bottom)

        }
    }
}

#Preview {
    SiriSettingsView()
}

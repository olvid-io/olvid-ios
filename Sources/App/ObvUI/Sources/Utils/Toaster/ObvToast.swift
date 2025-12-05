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

import Foundation
import SwiftUI
import ObvSystemIcon
import ObvDesignSystem

public struct Toast: Equatable {
    
    var style: ToastStyle
    var message: String
    var duration: Double
    var width: Double
    var actionOnTap: (() -> Void)?
    
    public static func == (lhs: Toast, rhs: Toast) -> Bool {
        return lhs.style == rhs.style &&
        lhs.message == rhs.message &&
        lhs.duration == rhs.duration &&
        lhs.width == rhs.width
    }
    
    public init(style: ToastStyle, message: String, duration: Double = 3, width: Double = .infinity, actionOnTap: (() -> Void)? = nil) {
        self.style = style
        self.message = message
        self.duration = duration
        self.width = width
        self.actionOnTap = actionOnTap
    }
}

public enum ToastStyle {
    case error
    case warning
    case success
    case info
}

extension ToastStyle {
    var themeColor: Color {
        switch self {
        case .error: return Color.red
        case .warning: return Color.orange
        case .info: return Color.blue
        case .success: return Color.green
        }
    }
    
    var icon: SystemIcon {
        switch self {
        case .error: return .xmarkCircleFill
        case .warning: return .exclamationmarkTriangleFill
        case .info: return .infoCircleFill
        case .success: return .checkmarkCircleFill
        }
    }
}

struct ToastView: View {
    
    var style: ToastStyle
    var message: String
    var width: CGFloat = .infinity
    var onCancelTapped: (() -> Void)?
    var onCloseTapped: (() -> Void)?
    
    @State private var shadowRadius: CGFloat = 0
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemIcon: style.icon).imageScale(.large)
                .foregroundColor(style.themeColor)
            if onCancelTapped != nil {
                (Text(message) + Text(verbatim: " - ").bold() + Text("Cancel").bold())
                    .font(Font.callout)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.label))
            } else {
                Text(message)
                    .font(Font.callout)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.label))
            }
            Spacer(minLength: 10)
            
            if let onCloseTapped {
                Button {
                    onCloseTapped()
                } label: {
                    Image(systemIcon: .xmark)
                        .foregroundColor(style.themeColor)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .frame(minWidth: 0, maxWidth: width)
        .background(.ultraThickMaterial)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(style.themeColor.opacity(0.2), lineWidth: 1.0)
        )
        .shadow(color: .black.opacity(0.2),
                radius: shadowRadius,
                x: 0,
                y: 0)
        .onAppear(perform: {
            withAnimation(.linear(duration: 1.5)) {
                shadowRadius = 8
            }
        })
        .onTapGesture {
            if let onCancelTapped {
                onCancelTapped()
            }
        }
    }
}

public struct ToastModifier: ViewModifier {
    
    @Binding var toast: Toast?
    @State private var workItem: DispatchWorkItem?
    
    public func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                ZStack {
                    mainToastView()
                        .offset(y: 32.0)
                }.animation(.spring(), value: toast)
            }
            .onChange(of: toast) { newValue in
                showToast()
            }
    }
    
    @ViewBuilder
    func mainToastView() -> some View {
        if let toast = toast {
            VStack {
                ToastView(style: toast.style,
                          message: toast.message,
                          width: toast.width,
                          onCancelTapped: toast.actionOnTap) {
                    dismissToast()
                }
                          .padding(.horizontal, 16)
                Spacer()
            }
        }
    }
    
    private func showToast() {
        guard let toast = toast else { return }
        
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        if toast.duration > 0 {
            workItem?.cancel()
        }
        
        let task = DispatchWorkItem {
            dismissToast()
        }
        
        workItem = task
        
        DispatchQueue.main.asyncAfter(deadline: .now() + toast.duration, execute: task)
    }
    
    private func dismissToast() {
        withAnimation {
            toast = nil
        }

        workItem?.cancel()
        workItem = nil
    }
}

extension View {
    
    public func toastView(toast: Binding<Toast?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}

@available(iOS 17.0, *)
#Preview("SwiftUI") {
    
    @Previewable @State var toast: Toast? = nil
    
    return ZStack {
        Rectangle()
            .fill(.red)
        
        VStack(spacing: 32) {
            Button {
                toast = Toast(style: .success, message: "Saved.", width: 260) {
                    toast = nil
                }
            } label: {
                Text(verbatim: "Test Success")
            }
            
            Button {
                toast = Toast(style: .info, message: "Btw, t'es génial!")
            } label: {
                Text(verbatim: "Test Info")
            }
            
            Button {
                toast = Toast(style: .warning, message: "Attention ca va exploser!")
            } label: {
                Text(verbatim: "Test Warning")
            }
            
            Button {
                toast = Toast(style: .error, message: "Fatal error, grossière erreur!")
            } label: {
                Text(verbatim: "Test Error")
            }
            
        }
    }
    .toastView(toast: $toast)
}

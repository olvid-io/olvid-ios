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

private struct GlassEffectContainerForIOS26: ViewModifier {
    
    private let spacing: CGFloat
    
    init(spacing: CGFloat) {
        self.spacing = spacing
    }
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            return GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            return content
        }
    }
}

private struct GlassEffectID: ViewModifier {
    
    private let glassEffectID: String?
    private let namespace: Namespace.ID
    
    public init(glassEffectID: String?, namespace: Namespace.ID) {
        self.glassEffectID = glassEffectID
        self.namespace = namespace
    }
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            return content
                .glassEffectID(glassEffectID, in: namespace)
        } else {
            return content
        }
    }
}

private struct GlassTextFieldStyle: ViewModifier {
    
    private let glassEffectID: String?
    private let namespace: Namespace.ID
    private let cornerRadius: CGFloat
    
    public init(glassEffectID: String?, namespace: Namespace.ID, cornerRadius: CGFloat) {
        self.glassEffectID = glassEffectID
        self.namespace = namespace
        self.cornerRadius = cornerRadius
    }
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            return content
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color(uiColor: .systemBackground), lineWidth: 0.5)
                )
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                .glassEffectID(glassEffectID, in: namespace)
        } else {
            return content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.thinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(Color(uiColor: .systemBackground).opacity(0.5))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color(uiColor: .systemBackground), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        }
    }
}

private struct GlassButtonStyle: ViewModifier {
    
    private let glassEffectID: String?
    private let tintColor: Color?

    public init(glassEffectID: String?, tintColor: Color? = nil) {
        self.glassEffectID = glassEffectID
        self.tintColor = tintColor
    }
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            return content
                .overlay(
                    Circle()
                        .strokeBorder(tintColor != nil ? .clear : Color(uiColor: .systemBackground), lineWidth: 0.5)
                )
                .glassEffect(tintColor != nil ? .regular.tint(tintColor!.opacity(0.15)).interactive() : .regular.interactive(), in: .circle)
                .foregroundStyle(tintColor != nil ? tintColor! : Color(uiColor: .label))
        } else {
            return content
                .foregroundStyle(tintColor != nil ? tintColor! : Color(uiColor: .label))
                .background(
                      Circle()
                          .fill(.thinMaterial)
                          .overlay(
                              Capsule(style: .continuous)
                                .fill(Color(uiColor: .systemBackground).opacity(0.5))
                          )
                  )
                .overlay(
                    Circle()
                        .strokeBorder(Color(uiColor: .systemBackground), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        }
    }
}


private struct EphemeralStyleModifier: ViewModifier {
    
    private let isEphemeral: Bool
    private let cornerRadius: CGFloat

    public init(isEphemeral: Bool, cornerRadius: CGFloat) {
        self.isEphemeral = isEphemeral
        self.cornerRadius = cornerRadius
    }
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .allowsHitTesting(false)
                    .opacity(isEphemeral ? 1.0 : 0.0)
            )
    }
}

extension View {
    
    public func glassTextFieldStyle(glassEffectID: String? = nil, namespace: Namespace.ID, cornerRadius: CGFloat = 25.0) -> some View {
        self.modifier(GlassTextFieldStyle(glassEffectID: glassEffectID, namespace: namespace, cornerRadius: cornerRadius))
    }
    
    public func glassButtonStyle(glassEffectID: String? = nil, tintColor: Color? = nil) -> some View {
        self.modifier(GlassButtonStyle(glassEffectID: glassEffectID, tintColor: tintColor))
    }
    
    public func glassEffectContainer(spacing: CGFloat = 8.0) -> some View {
        self.modifier(GlassEffectContainerForIOS26(spacing: spacing))
    }
    
    public func glassEffectID(glassEffectID: String?, namespace: Namespace.ID) -> some View {
        self.modifier(GlassEffectID(glassEffectID: glassEffectID, namespace: namespace))
    }
    
    public func ephemeralStyle(isEphemeral: Bool, cornerRadius: CGFloat) -> some View {
        self.modifier(EphemeralStyleModifier(isEphemeral: isEphemeral, cornerRadius: cornerRadius))
    }
}

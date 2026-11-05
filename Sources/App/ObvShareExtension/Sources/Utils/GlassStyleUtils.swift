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
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

private struct GlassButtonStyle: ViewModifier {

    private let tintColor: Color?

    public init(tintColor: Color? = nil) {
        self.tintColor = tintColor
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .overlay(
                    Circle()
                        .strokeBorder(tintColor != nil ? .clear : Color(uiColor: .systemBackground), lineWidth: 0.5)
                )
                .glassEffect(tintColor != nil ? .regular.tint(tintColor!.opacity(0.15)).interactive() : .regular.interactive(), in: .circle)
                .foregroundStyle(tintColor != nil ? tintColor! : Color(uiColor: .label))
        } else {
            content
                .foregroundStyle(tintColor != nil ? tintColor! : Color(uiColor: .label))
                .background(
                      Circle()
                          .fill(.thinMaterial)
                          .overlay(
                              // Same shape as the material below it. Equivalent to a `Capsule` only while the
                              // frame is square, which is not something this modifier can rely on.
                              Circle()
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

private struct GlassRoundedRectangleStyle: ViewModifier {

    private let tintColor: Color?
    private let cornerRadius: CGFloat

    public init(tintColor: Color? = nil, cornerRadius: CGFloat = 0) {
        self.tintColor = tintColor
        self.cornerRadius = cornerRadius
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(tintColor != nil ? .clear : Color(uiColor: .systemBackground), lineWidth: 0.5)
                )
                .glassEffect(tintColor != nil ? .regular.tint(tintColor!.opacity(0.15)).interactive() : .regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                .foregroundStyle(tintColor != nil ? tintColor! : Color(uiColor: .label))
        } else {
            content
                .foregroundStyle(tintColor != nil ? tintColor! : Color(uiColor: .label))
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.thinMaterial)
                        .overlay(
                            // Must be the same shape as the material below it. A `Capsule` here would round
                            // to half the height — far more than `cornerRadius` on anything but a pill-shaped
                            // view — leaving the material visible past the tint at the four corners.
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
            content
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color(uiColor: .systemBackground), lineWidth: 0.5)
                )
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                .glassEffectID(glassEffectID, in: namespace)
        } else {
            content
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

extension View {

    public func glassTextFieldStyle(glassEffectID: String? = nil, namespace: Namespace.ID, cornerRadius: CGFloat = 25.0) -> some View {
        self.modifier(GlassTextFieldStyle(glassEffectID: glassEffectID, namespace: namespace, cornerRadius: cornerRadius))
    }

    public func glassButtonStyle(tintColor: Color? = nil) -> some View {
        self.modifier(GlassButtonStyle(tintColor: tintColor))
    }

    public func glassRoundedRectangleStyle(tintColor: Color? = nil, cornerRadius: CGFloat = 0) -> some View {
        self.modifier(GlassRoundedRectangleStyle(tintColor: tintColor, cornerRadius: cornerRadius))
    }

    public func glassEffectContainer(spacing: CGFloat = 8.0) -> some View {
        self.modifier(GlassEffectContainerForIOS26(spacing: spacing))
    }

}

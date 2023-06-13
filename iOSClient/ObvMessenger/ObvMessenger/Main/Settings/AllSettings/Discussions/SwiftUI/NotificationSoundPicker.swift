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
  

import AudioToolbox
import ObvUI
import ObvUICoreData
import SwiftUI
import UI_SystemIcon
import UI_SystemIcon_SwiftUI


struct NotificationSoundPicker<Content: View>: View {

    @Binding var selection: OptionalNotificationSound
    let showDefault: Bool
    let content: (OptionalNotificationSound) -> Content

    var body: some View {
        NavigationLink(destination: NotificationSoundList(selection: $selection,
                                                          content: content,
                                                          showDefault: showDefault)) {
            HStack {
                ObvLabel("NOTIFICATION_SOUNDS_LABEL", systemIcon: .musicNoteList)
                Spacer()
                content(selection)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
            }
        }
    }
}


extension NotificationSound.Category {
    var iconColor: Color {
        switch self {
        case .neutral: return .gray
        case .alarm: return .red
        case .animal: return .green
        case .toy: return .yellow
        }
    }
}

struct NotificationSoundList<Content: View>: View {

    @Binding var selection: OptionalNotificationSound
    let content: (OptionalNotificationSound) -> Content
    let showDefault: Bool

    @State private var isCollapsed = false

    func sectionForNeutral(with category: NotificationSound.Category) -> some View {
        var sounds: [OptionalNotificationSound] = []
        sounds += NotificationSound.allCases.compactMap({ sound in
            guard sound != .none else { return nil }
            guard !sound.isPolyphonic else { return nil }
            guard category == sound.category else { return nil }
            return OptionalNotificationSound.some(sound)
        })
        return InnerNotificationSoundList(icon: (category.icon, category.iconColor),
                                          title: category.title,
                                          subtitle: nil,
                                          sounds: sounds,
                                          selection: $selection,
                                          content: content)
    }

    fileprivate var defaultSounds: [OptionalNotificationSound] {
        var sounds: [OptionalNotificationSound] = [.some(.none)]
        sounds += [.some(.system)]
        if showDefault {
            sounds += [.none]
        }
        return sounds
    }

    var body: some View {
        Form {
            InnerNotificationSoundList(icon: nil,
                                       title: nil,
                                       subtitle: nil,
                                       sounds: defaultSounds,
                                       selection: $selection,
                                       content: content)
            sectionForNeutral(with: .neutral)
            sectionForNeutral(with: .alarm)
            sectionForNeutral(with: .animal)
            sectionForNeutral(with: .toy)
            InnerNotificationSoundList(icon: (.musicNoteList, .blue),
                                       title: NSLocalizedString("NOTIFICATION_SOUNDS_TITLE_POLYPHONIC", comment: ""),
                                       subtitle: NSLocalizedString("NOTIFICATION_SOUNDS_SUBTITLE_POLYPHONIC", comment: ""),
                                       sounds: NotificationSound.allCases.compactMap({ sound in
                guard sound != .none else { return nil }
                guard sound.isPolyphonic else { return nil }
                return OptionalNotificationSound.some(sound)
            }),
                                       selection: $selection,
                                       content: content)
        }
        .obvNavigationTitle(Text("NOTIFICATION_SOUNDS_LABEL"))
    }
}

struct InnerNotificationSoundList<Content: View>: View {
    let icon: (SystemIcon, Color)?
    let title: String?
    let subtitle: String?
    let sounds: [OptionalNotificationSound]
    @Binding var selection: OptionalNotificationSound
    let content: (OptionalNotificationSound) -> Content

    @State private var isCollapsed = false

    var body: some View {
        Section {
            if title != nil || subtitle != nil {
                HStack {
                    VStack(alignment: .leading, spacing: 4.0) {
                        HStack {
                            if let title = title {
                                if let (icon, color) = icon {
                                    Image(systemIcon: icon)
                                        .foregroundColor(color)
                                }
                                Text(title)
                                    .font(.headline)
                            }
                        }
                        if let subtitle = subtitle {
                            HStack {
                                if let (icon, color) = icon {
                                    Image(systemIcon: icon)
                                        .foregroundColor(color)
                                        .opacity(0)
                                }
                                Text(subtitle)
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    Spacer()
                    VStack {
                        Spacer()
                        Image(systemIcon: .chevronDown)
                            .foregroundColor(.blue)
                            .rotationEffect(isCollapsed ? .degrees(-90) : .zero)
                        Spacer()
                    }
                }
                .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
                .onTapGesture { withAnimation { isCollapsed.toggle() } }
            }
            if !isCollapsed {
                List {
                    ForEach(sounds, id: \.self) { sound in
                        HStack {
                            content(sound)
                            Spacer()
                            if sound == selection {
                                Image(systemIcon: .checkmark)
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
                        .onTapGesture {
                            selection = sound
                            guard let notificationSound = sound.value ?? ObvMessengerSettings.Discussions.notificationSound else { return }
                            if case NotificationSound.system = notificationSound {
                                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                            } else {
                                Task {
                                    if notificationSound.isPolyphonic {
                                        NotificationSoundPlayer.shared.play(sound: notificationSound, note: Note.random(), category: .playback)
                                    } else {
                                        NotificationSoundPlayer.shared.play(sound: notificationSound, category: .playback)
                                    }
                                }
                            }


                        }
                    }
                }
            }
        }
    }
}

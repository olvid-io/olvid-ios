import ProjectDescription
import Foundation

public extension TargetDependency {
    enum Engine {
        public static let bigInt: TargetDependency = .project(target: "BigInt", path: .relativeToRoot("Engine"))

        public static let jws: TargetDependency = .project(target: "JWS", path: .relativeToRoot("Engine"))

        public static let obvBackupManager: TargetDependency = .project(target: "ObvBackupManager", path: .relativeToRoot("Engine"))

        public static let obvChannelManager: TargetDependency = .project(target: "ObvChannelManager", path: .relativeToRoot("Engine"))

        public static let obvCrypto: TargetDependency = .project(target: "ObvCrypto", path: .relativeToRoot("Engine"))

        public static let obvDatabaseManager: TargetDependency = .project(target: "ObvDatabaseManager", path: .relativeToRoot("Engine"))

        public static let obvEncoder: TargetDependency = .project(target: "ObvEncoder", path: .relativeToRoot("Engine"))

        public static let obvEngine: TargetDependency = .project(target: "ObvEngine", path: .relativeToRoot("Engine"))

        public static let obvFlowManager: TargetDependency = .project(target: "ObvFlowManager", path: .relativeToRoot("Engine"))

        public static let obvIdentityManager: TargetDependency = .project(target: "ObvIdentityManager", path: .relativeToRoot("Engine"))

        public static let obvMetaManager: TargetDependency = .project(target: "ObvMetaManager", path: .relativeToRoot("Engine"))

        public static let obvNetworkFetchManager: TargetDependency = .project(target: "ObvNetworkFetchManager", path: .relativeToRoot("Engine"))

        public static let obvNetworkSendManager: TargetDependency = .project(target: "ObvNetworkSendManager", path: .relativeToRoot("Engine"))

        public static let obvNotificationCenter: TargetDependency = .project(target: "ObvNotificationCenter", path: .relativeToRoot("Engine"))

        public static let obvOperation: TargetDependency = .project(target: "ObvOperation", path: .relativeToRoot("Engine"))

        public static let obvProtocolManager: TargetDependency = .project(target: "ObvProtocolManager", path: .relativeToRoot("Engine"))

        public static let obvServerInterface: TargetDependency = .project(target: "ObvServerInterface", path: .relativeToRoot("Engine"))

        public static let obvTypes: TargetDependency = .project(target: "ObvTypes", path: .relativeToRoot("Engine"))
    }

    enum Modules {
        public enum Components {
            public static let textInputShortcutsResultView: TargetDependency = .project(target: "Components_TextInputShortcutsResultView", path: .relativeToRoot("Modules/Components/TextInputShortcutsResultView"))
        }

        public enum Discussions {

            public enum Mentions {
                public enum AutoGrowingTextView {
                    public static let textViewDelegateProxy: TargetDependency = .project(target: "Discussions_Mentions_AutoGrowingTextView_TextViewDelegateProxy", path: .relativeToRoot("Modules/Discussions"))
                }

                public enum Builders {
                    public static let buildersShared: TargetDependency = .project(target: "_Discussions_Mentions_Builders_Shared", path: .relativeToRoot("Modules/Discussions"))

                    /// Please don't use me directly, you shouldn't need to
                    public static let _builderInternals: TargetDependency = .project(target: "_Discussions_Mentions_Builder_Internals", path: .relativeToRoot("Modules/Discussions"))

                    public static let composeMessage: TargetDependency = .project(target: "Discussions_Mentions_ComposeMessageBuilder", path: .relativeToRoot("Modules/Discussions"))

                    public static let textBubble: TargetDependency = .project(target: "Discussions_Mentions_TextBubbleBuilder", path: .relativeToRoot("Modules/Discussions"))
                }
            }

            public static let attachmentsDropView: TargetDependency = .project(target: "Discussions_AttachmentsDropView", path: .relativeToRoot("Modules/Discussions"))

            public static let scrollToBottomButton: TargetDependency = .project(target: "Discussions_ScrollToBottomButton", path: .relativeToRoot("Modules/Discussions"))
        }

        public enum UI {

            public enum CircledInitialsView {
                public static let configuration: TargetDependency = .project(target: "UI_CircledInitialsView_CircledInitialsConfiguration", path: .relativeToRoot("Modules/UI"))
            }

	    public static let systemIcon: TargetDependency = .project(target: "UI_SystemIcon", path: .relativeToRoot("Modules/UI"))

            public static let systemIconSwiftUI: TargetDependency = .project(target: "UI_SystemIcon_SwiftUI", path: .relativeToRoot("Modules/UI"))

            public static let systemIconUIKit: TargetDependency = .project(target: "UI_SystemIcon_UIKit", path: .relativeToRoot("Modules/UI"))

        }

        public enum Platform {
            public static let base: TargetDependency = .project(target: "Platform_Base", path: .relativeToRoot("Modules/Platform"))

            public static let combineAdditions: TargetDependency = .project(target: "Platform_Combine_Additions", path: .relativeToRoot("Modules/Platform"))

            public static let uiKitAdditions: TargetDependency = .project(target: "Platform_UIKit_Additions", path: .relativeToRoot("Modules/Platform"))

            public static let sequenceKeyPathSorting: TargetDependency = .project(target: "Platform_Sequence_KeyPathSorting", path: .relativeToRoot("Modules/Platform"))

            public static let nsItemProviderUTTypeBackport: TargetDependency = .project(target: "Platform_NSItemProvider_UTType_Backport", path: .relativeToRoot("Modules/Platform"))
        }

        public static let coreDataStack: TargetDependency = .project(target: "CoreDataStack", path: .relativeToRoot("Modules"))

        public static let obvUI: TargetDependency = .project(target: "ObvUI", path: .relativeToRoot("Modules"))

        public static let obvUICoreData: TargetDependency = .project(target: "ObvUICoreData", path: .relativeToRoot("Modules"))

        public static let olvidUtils: TargetDependency = .project(target: "OlvidUtils", path: .relativeToRoot("Modules"))
    }
}

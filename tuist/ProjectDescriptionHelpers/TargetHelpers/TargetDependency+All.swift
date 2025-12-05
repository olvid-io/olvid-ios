import ProjectDescription

extension TargetDependency {

    public struct Olvid {
        
        public struct Shared {
            public static let obvTypes = TargetDependency.project(target: "ObvTypes", path: .olvidPath("ObvTypes", in: .shared))
            public static let olvidUtils = TargetDependency.project(target: "OlvidUtils", path: .olvidPath("OlvidUtils", in: .shared))
            public static let obvCoreDataStack = TargetDependency.project(target: "ObvCoreDataStack", path: .olvidPath("ObvCoreDataStack", in: .shared))
            public static let obvNetworkStatus = TargetDependency.project(target: "ObvNetworkStatus", path: .olvidPath("ObvNetworkStatus", in: .shared))
            public static let obvAccessibility = TargetDependency.project(target: "ObvAccessibility", path: .olvidPath("ObvAccessibility", in: .shared))
            public static let obvOwnedIdentityChooser = TargetDependency.project(target: "ObvOwnedIdentityChooser", path: .olvidPath("ObvOwnedIdentityChooser", in: .shared))
            public static let obvSharedDataSources = TargetDependency.project(target: "ObvSharedDataSources", path: .olvidPath("ObvSharedDataSources", in: .shared))
        }
        
        public struct Engine {
            public static let obvEngine = TargetDependency.project(target: "ObvEngine", path: .olvidPath("ObvEngine", in: .engine))
            public static let obvCrypto = TargetDependency.project(target: "ObvCrypto", path: .olvidPath("ObvCrypto", in: .engine))
            public static let obvBigInt = TargetDependency.project(target: "ObvBigInt", path: .olvidPath("ObvBigInt", in: .engine))
            public static let obvEncoder = TargetDependency.project(target: "ObvEncoder", path: .olvidPath("ObvEncoder", in: .engine))
            public static let obvOperation = TargetDependency.project(target: "ObvOperation", path: .olvidPath("ObvOperation", in: .engine))
            public static let obvJWS = TargetDependency.project(target: "ObvJWS", path: .olvidPath("ObvJWS", in: .engine))
            public static let obvMetaManager = TargetDependency.project(target: "ObvMetaManager", path: .olvidPath("ObvMetaManager", in: .engine))
            public static let obvBackupManager = TargetDependency.project(target: "ObvBackupManager", path: .olvidPath("ObvBackupManager", in: .engine))
            public static let obvBackupManagerNew = TargetDependency.project(target: "ObvBackupManagerNew", path: .olvidPath("ObvBackupManagerNew", in: .engine))
            public static let obvChannelManager = TargetDependency.project(target: "ObvChannelManager", path: .olvidPath("ObvChannelManager", in: .engine))
            public static let obvFlowManager = TargetDependency.project(target: "ObvFlowManager", path: .olvidPath("ObvFlowManager", in: .engine))
            public static let obvIdentityManager = TargetDependency.project(target: "ObvIdentityManager", path: .olvidPath("ObvIdentityManager", in: .engine))
            public static let obvServerInterface = TargetDependency.project(target: "ObvServerInterface", path: .olvidPath("ObvServerInterface", in: .engine))
            public static let obvNetworkFetchManager = TargetDependency.project(target: "ObvNetworkFetchManager", path: .olvidPath("ObvNetworkFetchManager", in: .engine))
            public static let obvNetworkSendManager = TargetDependency.project(target: "ObvNetworkSendManager", path: .olvidPath("ObvNetworkSendManager", in: .engine))
            public static let obvNotificationCenter = TargetDependency.project(target: "ObvNotificationCenter", path: .olvidPath("ObvNotificationCenter", in: .engine))
            public static let obvProtocolManager = TargetDependency.project(target: "ObvProtocolManager", path: .olvidPath("ObvProtocolManager", in: .engine))
            public static let obvSyncSnapshotManager = TargetDependency.project(target: "ObvSyncSnapshotManager", path: .olvidPath("ObvSyncSnapshotManager", in: .engine))
            public static let obvDatabaseManager = TargetDependency.project(target: "ObvDatabaseManager", path: .olvidPath("ObvDatabaseManager", in: .engine))
        }
        
        public struct App {
            public static let obvSidebar = TargetDependency.project(target: "ObvSidebar", path: .olvidPath("ObvSidebar", in: .app))
            public static let obvSubscription = TargetDependency.project(target: "ObvSubscription", path: .olvidPath("ObvSubscription", in: .app))
            public static let obvOnboarding = TargetDependency.project(target: "ObvOnboarding", path: .olvidPath("ObvOnboarding", in: .app))
            public static let obvPollFeature = TargetDependency.project(target: "ObvPollFeature", path: .olvidPath("ObvPollFeature", in: .app))
            public static let obvKeycloakManager = TargetDependency.project(target: "ObvKeycloakManager", path: .olvidPath("ObvKeycloakManager", in: .app))
            public static let obvAppTypes = TargetDependency.project(target: "ObvAppTypes", path: .olvidPath("ObvAppTypes", in: .app))
            public static let obvUICoreData = TargetDependency.project(target: "ObvUICoreData", path: .olvidPath("ObvUICoreData", in: .app))
            public static let obvLocation = TargetDependency.project(target: "ObvLocation", path: .olvidPath("ObvLocation", in: .app))
            public static let obvLicenceActivationFlow = TargetDependency.project(target: "ObvLicenceActivationFlow", path: .olvidPath("ObvLicenceActivationFlow", in: .app))
            public static let obvInvitationFlow = TargetDependency.project(target: "ObvInvitationFlow", path: .olvidPath("ObvInvitationFlow", in: .app))
            public static let obvAppBackup = TargetDependency.project(target: "ObvAppBackup", path: .olvidPath("ObvAppBackup", in: .app))
            public static let obvUICoreDataStructs = TargetDependency.project(target: "ObvUICoreDataStructs", path: .olvidPath("ObvUICoreDataStructs", in: .app))
            public static let obvAppCoreConstants = TargetDependency.project(target: "ObvAppCoreConstants", path: .olvidPath("ObvAppCoreConstants", in: .app))
            public static let obvUIGroupV1 = TargetDependency.project(target: "ObvUIGroupV1", path: .olvidPath("ObvUIGroupV1", in: .app))
            public static let obvUIGroupV2 = TargetDependency.project(target: "ObvUIGroupV2", path: .olvidPath("ObvUIGroupV2", in: .app))
            public static let obvAppNavigation = TargetDependency.project(target: "ObvAppNavigation", path: .olvidPath("ObvAppNavigation", in: .app))
            public static let obvUIGroupSharedBetweenV1AndV2 = TargetDependency.project(target: "ObvUIGroupSharedBetweenV1AndV2", path: .olvidPath("ObvUIGroupSharedBetweenV1AndV2", in: .app))
            public static let obvDiscussionsList = TargetDependency.project(target: "ObvDiscussionsList", path: .olvidPath("ObvDiscussionsList", in: .app))
            public static let obvGroupsList = TargetDependency.project(target: "ObvGroupsList", path: .olvidPath("ObvGroupsList", in: .app))
            public static let obvSingleDiscussion = TargetDependency.project(target: "ObvSingleDiscussion", path: .olvidPath("ObvSingleDiscussion", in: .app))
            public static let obvProfilePictureBarButtonItem = TargetDependency.project(target: "ObvProfilePictureBarButtonItem", path: .olvidPath("ObvProfilePictureBarButtonItem", in: .app))
            public static let obvUI = TargetDependency.project(target: "ObvUI", path: .olvidPath("ObvUI", in: .app))
            public static let obvDesignSystem = TargetDependency.project(target: "ObvDesignSystem", path: .olvidPath("ObvDesignSystem", in: .app))
            public static let obvSettings = TargetDependency.project(target: "ObvSettings", path: .olvidPath("ObvSettings", in: .app))
            public static let obvAppDatabase = TargetDependency.project(target: "ObvAppDatabase", path: .olvidPath("ObvAppDatabase", in: .app))
            public static let obvSystemIcon = TargetDependency.project(target: "ObvSystemIcon", path: .olvidPath("ObvSystemIcon", in: .app))
            public static let obvSingleContact = TargetDependency.project(target: "ObvSingleContact", path: .olvidPath("ObvSingleContact", in: .app))
            public static let obvSingleOwnedIdentity = TargetDependency.project(target: "ObvSingleOwnedIdentity", path: .olvidPath("ObvSingleOwnedIdentity", in: .app))
            public static let obvCells = TargetDependency.project(target: "ObvCells", path: .olvidPath("ObvCells", in: .app))
            public static let obvCommunicationInteractor = TargetDependency.project(target: "ObvCommunicationInteractor", path: .olvidPath("ObvCommunicationInteractor", in: .app))
            public struct Discussions {
                public struct Mentions {
                    public struct AutoGrowingTextView {
                        public static let textViewDelegateProxy = TargetDependency.project(target: "Discussions_Mentions_AutoGrowingTextView_TextViewDelegateProxy", path: .olvidPath("Discussions", in: .app))
                    }
                    public struct Builders {
                        public static let composeMessage = TargetDependency.project(target: "Discussions_Mentions_ComposeMessageBuilder", path: .olvidPath("Discussions", in: .app))
                        public static let buildersShared = TargetDependency.project(target: "_Discussions_Mentions_Builders_Shared", path: .olvidPath("Discussions", in: .app))
                    }
                }
                public static let scrollToBottomButton = TargetDependency.project(target: "ObvDiscussionsScrollToBottomButton", path: .olvidPath("Discussions", in: .app))
            }
            public struct Platform {
                public static let uiKitAdditions = TargetDependency.project(target: "ObvPlatformUIKitAdditions", path: .olvidPath("Platform", in: .app))
                public static let base = TargetDependency.project(target: "ObvPlatformBase", path: .olvidPath("Platform", in: .app))
            }
            public struct UI {
                public static let obvCircledInitials: TargetDependency = .project(target: "ObvUIObvCircledInitials", path: .olvidPath("UI", in: .app))
                public static let obvPhotoButton: TargetDependency = .project(target: "ObvUIObvPhotoButton", path: .olvidPath("UI", in: .app))
                public static let obvImageEditor: TargetDependency = .project(target: "ObvImageEditor", path: .olvidPath("UI", in: .app))
                public static let obvScannerHostingView: TargetDependency = .project(target: "ObvScannerHostingView", path: .olvidPath("UI", in: .app))
                public static let obvCircleAndTitlesView: TargetDependency = .project(target: "ObvCircleAndTitlesView", path: .olvidPath("UI", in: .app))
            }
            public struct Components {
                public static let textInputShortcutsResultView: TargetDependency = .project(target: "ObvComponentsTextInputShortcutsResultView", path: .olvidPath("Components/TextInputShortcutsResultView", in: .app))
                public static let obvEmojiUtils: TargetDependency = .project(target: "ObvEmojiUtils", path: .olvidPath("Components/ObvEmojiUtils", in: .app))
            }
            public struct ObvUserNotifications {
                public static let types: TargetDependency = .project(target: "ObvUserNotificationsTypes", path: .olvidPath("ObvUserNotifications", in: .app))
                public static let database: TargetDependency = .project(target: "ObvUserNotificationsDatabase", path: .olvidPath("ObvUserNotifications", in: .app))
                public static let sounds: TargetDependency = .project(target: "ObvUserNotificationsSounds", path: .olvidPath("ObvUserNotifications", in: .app))
                public static let creator: TargetDependency = .project(target: "ObvUserNotificationsCreator", path: .olvidPath("ObvUserNotifications", in: .app))
            }
            public struct ObvAppInbox {
                public static let types: TargetDependency = .project(target: "ObvAppInboxTypes", path: .olvidPath("ObvAppInbox", in: .app))
                public static let database: TargetDependency = .project(target: "ObvAppInboxDatabase", path: .olvidPath("ObvAppInbox", in: .app))
                public static let service: TargetDependency = .project(target: "ObvAppInboxService", path: .olvidPath("ObvAppInbox", in: .app))
            }
            public struct ThirdParty {
                public static let confettiSwiftUI: TargetDependency = .project(target: "ConfettiSwiftUI", path: .olvidPath("ThirdParty/ConfettiSwiftUI", in: .app))
            }
        }
        
    }
    
}

import ProjectDescription
import Foundation

extension Target {

    public enum Error: Swift.Error {
        case missingResources

        case invalidPrefix(path: String)
    }

    private static func iOSTarget(
        name: String,
        product: ProjectDescription.Product,
        productName: String? = nil,
        bundleId: String,
        deploymentTarget: DeploymentTarget? = Constants.deploymentTarget,
        infoPlist: ProjectDescription.InfoPlist? = .default,
        sources: ProjectDescription.SourceFilesList? = nil,
        resources: ProjectDescription.ResourceFileElements? = nil,
        copyFiles: [ProjectDescription.CopyFilesAction]? = nil,
        headers: ProjectDescription.Headers? = nil,
        entitlements: ProjectDescription.Path? = nil,
        scripts: [ProjectDescription.TargetScript] = [],
        dependencies: [ProjectDescription.TargetDependency] = [],
        settings: ProjectDescription.Settings? = nil,
        coreDataModels: [ProjectDescription.CoreDataModel] = [],
        environment: [String : String] = [:],
        launchArguments: [ProjectDescription.LaunchArgument] = [],
        additionalFiles: [ProjectDescription.FileElement] = []
    ) -> Self {
        return self.init(
            name: name,
            platform: .iOS,
            product: product,
            productName: productName,
            bundleId: bundleId,
            deploymentTarget: deploymentTarget,
            infoPlist: infoPlist,
            sources: sources,
            resources: resources,
            copyFiles: copyFiles,
            headers: headers,
            entitlements: entitlements,
            scripts: scripts,
            dependencies: dependencies,
            settings: settings,
            coreDataModels: coreDataModels,
            environment: environment,
            launchArguments: launchArguments,
            additionalFiles: additionalFiles
        )
    }

    public static func mainApp(
        name: String,
        deploymentTarget: DeploymentTarget = Constants.deploymentTarget,
        infoPlist: InfoPlist,
        sources: SourceFilesList,
        resources: ResourceFileElements,
        entitlements: Path,
        scripts: [ProjectDescription.TargetScript] = [],
        dependencies: [TargetDependency],
        settings: ProjectDescription.Settings,
        coreDataModels: [ProjectDescription.CoreDataModel],
        additionalFiles: [ProjectDescription.FileElement] = []
    ) -> Self {
        return .iOSTarget(
            name: name,
            product: .app,
            productName: name,
            bundleId: Constants.baseAppBundleIdentifier.appending("$(OLVID_PRODUCT_BUNDLE_IDENTIFIER_SERVER_SUFFIX)"),
            deploymentTarget: deploymentTarget,
            infoPlist: infoPlist,
            sources: sources,
            resources: resources,
            entitlements: entitlements,
            scripts: scripts,
            dependencies: dependencies,
            settings: settings,
            coreDataModels: coreDataModels,
            additionalFiles: additionalFiles
        )
    }

    public static func sampleApp(
        name: String,
        deploymentTarget: DeploymentTarget = Constants.deploymentTarget,
        sources: SourceFilesList,
        resources: ResourceFileElements,
        dependencies: [TargetDependency]
    ) -> Self {
        let infoPlist: InfoPlist = .extendingDefault(with: [
            "UILaunchStoryboardName": "LaunchScreen"
        ])

        return .iOSTarget(
            name: name.appending("Sample"),
            product: .app,
            productName: name.appending("Sample"),
            bundleId: _sampleAppBundleIdentifier(for: name),
            deploymentTarget: deploymentTarget,
            infoPlist: infoPlist,
            sources: sources,
            resources: resources,
            dependencies: dependencies
        )
    }

    public static func appExtension(
        name: String,
        bundleIdentifier: String,
        deploymentTarget: DeploymentTarget = Constants.deploymentTarget,
        infoPlist: InfoPlist,
        sources: SourceFilesList,
        resources: ResourceFileElements,
        entitlements: Path?,
        dependencies: [TargetDependency],
        settings: Settings,
        coreDataModels: [ProjectDescription.CoreDataModel]
    ) -> Self {
        return .iOSTarget(
            name: name,
            product: .appExtension,
            productName: name,
            bundleId: bundleIdentifier,
            deploymentTarget: deploymentTarget,
            infoPlist: infoPlist,
            sources: sources,
            resources: resources,
            entitlements: entitlements,
            dependencies: dependencies,
            settings: settings,
            coreDataModels: coreDataModels
        )
    }

    public static func swiftLibrary(
        name: String,
        isExtensionSafe: Bool,
        sources: SourceFilesList,
        dependencies: [TargetDependency] = [],
        resources: ResourceFileElements = [],
        coreDataModels: [CoreDataModel] = [],
        additionalFiles: [ProjectDescription.FileElement] = []
    ) -> Self {
        return .iOSTarget(
            name: name,
            product: .framework, //we'll use dynamic frameworks for now until we use swiftgen/sourcery
            productName: name,
            bundleId: _bundleIdentifier(for: name),
            infoPlist: .default,
            sources: sources,
            resources: resources,
            dependencies: dependencies,
            settings: ._baseSwiftLibrarySettings(moduleName: name, isExtensionSafe: isExtensionSafe),
            coreDataModels: coreDataModels,
            additionalFiles: additionalFiles
        )
    }

    public static func swiftLibraryTests(
        name: String,
        sources: SourceFilesList,
        dependencies: [TargetDependency],
        resources: ResourceFileElements) -> Self {
            return .iOSTarget(name: name,
                              product: .unitTests,
                              productName: name,
                              bundleId: _bundleIdentifier(for: name),
                              infoPlist: .default,
                              sources: sources,
                              resources: resources,
                              dependencies: dependencies)
        }

    public static func objectiveCLibrary(
        name: String,
        isExtensionSafe: Bool,
        sources: SourceFilesList,
        headers: Headers,
        dependencies: [TargetDependency],
        resources: ResourceFileElements,
        coreDataModels: [CoreDataModel] = [],
        additionalFiles: [ProjectDescription.FileElement] = []
    ) -> Self {
        return .iOSTarget(
            name: name,
            product: .framework, //we'll use dynamic frameworks for now until we use swiftgen/sourcery
            productName: name,
            bundleId: _bundleIdentifier(for: name),
            infoPlist: .default,
            sources: sources,
            resources: resources,
            headers: headers,
            dependencies: dependencies,
            settings: ._baseFrameworkSettings(moduleName: name, isExtensionSafe: isExtensionSafe),
            coreDataModels: coreDataModels,
            additionalFiles: additionalFiles
        )
    }

    private static func _bundleIdentifier(for name: String) -> String {
        let name = name.replacingOccurrences(of: "_", with: "-")

        return Constants.baseAppBundleIdentifier + name
    }

    private static func _sampleAppBundleIdentifier(for name: String) -> String {
        let name = name.replacingOccurrences(of: "_", with: "-")

        return (Constants.sampleAppBaseBundleIdentifier as NSString).appendingPathExtension(name.trimmingCharacters(in: .init(charactersIn: ".")))!
    }
}
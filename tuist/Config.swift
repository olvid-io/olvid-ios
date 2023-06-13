import ProjectDescription
import Foundation

let xcodeVersionFileVersion = try! {
    let currentPath = (#file as NSString).deletingLastPathComponent

    let xcodesVersionFilePath = currentPath.appending("/../.xcode-version")

    guard FileManager.default.fileExists(atPath: xcodesVersionFilePath) else {
        fatalError("expected \(xcodesVersionFilePath) to exist")
    }

    return try String(contentsOfFile: xcodesVersionFilePath)
}()

let config = Config(
    compatibleXcodeVersions: .exact(.init(stringLiteral: xcodeVersionFileVersion)),
    generationOptions: .options(resolveDependenciesWithSystemScm: true)
)

// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import ArgumentParser
import Translation

@available(macOS 15.0, *)
@main
struct TranslatorSwift: ParsableCommand {
    
    @Option(help: "Specify the url of an .xcstrings file")
    public var pathToXcstringsFile: String

    @Option(help: "Specify your Mistral API key")
    public var mistralApiKey: String?

    public func run() throws {
        
        Task {
            do {
                try await asyncRun()
            } catch {
                print("FAILURE: \(error)")
            }
            // Exit the script after async work is done
            Foundation.exit(0)
        }
        
        RunLoop.main.run()

    }
    
    
    private func asyncRun() async throws {
        
        print("Hello, world! \(pathToXcstringsFile)")
        
        // Obtain a valid URL to the xcstrings file
        
        let urlToXcstringsFile: URL
        
        do {
            let parsingResult = parsePathToXcstringsFile()
            
            switch parsingResult {
            case .failure:
                print("Error: The provided path to the .xcstrings file is invalid or the file does not exist.")
                return
            case .success(urlOfXcstringsFile: let url):
                print("Success: The provided path to the .xcstrings file is valid and the file exists. URL: \(url)")
                urlToXcstringsFile = url
            }
        }
        
        // Parse the .xcstrings file
        
        let stringCatalog: StringsCatalog
        do {
            stringCatalog = try parseXCStrings(urlToXcstringsFile: urlToXcstringsFile)
        } catch {
            print("Parsing failed: \(error)")
            return
        }
        
        // Initalizing a translation session
        
//        let sourceLanguage: Locale.Language = .init(identifier: "en")
//        let targetLanguage: Locale.Language = .init(identifier: "fr")
//        
//        let availability = LanguageAvailability()
//        
//        let isTranslationAvailable = await availability.status(from: sourceLanguage, to: targetLanguage)
//        
//        print("Translation is available: \(isTranslationAvailable)")
//        
//        let translationSessionConfiguration = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
//        
//        let tot = TranslationSession.init(installedSource: sourceLanguage, target: targetLanguage)

        if let mistralApiKey {
            
            let translator = TranslatorMistral(apiKey: mistralApiKey, sourceLanguage: .englishUS, targetLanguage: .french)
            
            for (_, stringEntry) in stringCatalog.strings {
                for (lang, localizationEntry) in stringEntry.localizations {
                    guard lang == "en" else { continue }
                    guard let sourceText = localizationEntry.stringUnit?.value else { continue }
                    if let translatedText = try? await translator.translate(sourceText) {
                        print(sourceText, " ----> ", translatedText)
                    }
                }
            }

            
        }
        
        if let mistralApiKey {
            
            let translator = TranslatorMistral(apiKey: mistralApiKey, sourceLanguage: .englishUS, targetLanguage: .italian)
            
            for (_, stringEntry) in stringCatalog.strings {
                for (lang, localizationEntry) in stringEntry.localizations {
                    guard lang == "en" else { continue }
                    guard let sourceText = localizationEntry.stringUnit?.value else { continue }
                    if let translatedText = try? await translator.translate(sourceText) {
                        print(sourceText, " ----> ", translatedText)
                    }
                }
            }

            
        }

        
    }


    
    
    
    enum PathToXcstringsFileParsingResult {
        case failure
        case success(urlOfXcstringsFile: URL)
    }

    private func parsePathToXcstringsFile() -> PathToXcstringsFileParsingResult {
        let url = URL(fileURLWithPath: self.pathToXcstringsFile)
        if FileManager.default.fileExists(atPath: url.path) {
            return .success(urlOfXcstringsFile: url)
        } else {
            return .failure
        }
    }

    
    // Parse the .xcstrings file
    func parseXCStrings(urlToXcstringsFile url: URL) throws -> StringsCatalog {
        let data = try Data(contentsOf: url)
        let catalog = try JSONDecoder().decode(StringsCatalog.self, from: data)
        return catalog
    }

}




struct StringsCatalog: Codable {
    let sourceLanguage: String
    let strings: [String: StringEntry]
    let version: String

    struct StringEntry: Codable {
        let localizations: [String: LocalizationEntry]

        struct LocalizationEntry: Codable {
            let stringUnit: StringUnit?

            struct StringUnit: Codable {
                let state: String
                let value: String
            }
            
        }
    }
}



enum Language: String {
    case englishUS = "en-US"
    case french = "fr-FR"
    case italian = "it-IT"
    
    var name: String {
        switch self {
        case .englishUS:
            return "English (\(self.rawValue)"
        case .french:
            return "French (\(self.rawValue)"
        case .italian:
            return "Italian (\(self.rawValue)"
        }
    }
}


@available(macOS 15.0, *)
struct TranslatorMistral {
    
    let apiKey: String
    let sourceLanguage: Language
    let targetLanguage: Language
    
    private let endpoint = "https://api.mistral.ai/v1/chat/completions"

    func translate(_ sentence: String) async throws -> String {
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt: String = """
            You are a professional translator and you are used to work with mobile application frameworks.
            You have to translate a string from an iOS instant messaging application.
            The original string is in \(sourceLanguage.name) and you have to translate them in \(targetLanguage.name).
            The number of characters of the rewturned string shall be close to that of the original string, as it
            will be inclued in a user interface. Do not give any explanation, only return the translation.
            Preserve the input format. Never return a parenthesis, unless there is one in the original string.
            
            Here is the sentence to translate: \(sentence)
            """
        
        // Prepare the request body
        let requestBody: [String: Any] = [
            "model": "mistral-tiny", // or another available model
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ObvError.error
        }
        
        return content

    }
    
    enum ObvError: Error {
        case error
    }
    
}

import Foundation
import SwiftUI
import UIKit

enum PerformanceLogStore {
    struct SessionFiles {
        let jsonURL: URL
        let textURL: URL

        var exportURLs: [URL] {
            [textURL, jsonURL].filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    static let directoryName = "PerformanceLogs"

    static func logsDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let logsDirectoryURL = documentsURL.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
        return logsDirectoryURL
    }

    static func createSessionFiles(date: Date = Date()) throws -> SessionFiles {
        let directoryURL = try logsDirectoryURL()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stem = "performance_\(formatter.string(from: date))_\(UUID().uuidString.prefix(8))"
        let jsonURL = directoryURL.appendingPathComponent(stem).appendingPathExtension("jsonl")
        let textURL = directoryURL.appendingPathComponent(stem).appendingPathExtension("txt")

        guard FileManager.default.createFile(atPath: jsonURL.path, contents: nil),
              FileManager.default.createFile(atPath: textURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        return SessionFiles(jsonURL: jsonURL, textURL: textURL)
    }

    static func existingLogURLs() -> [URL] {
        guard let directoryURL = try? logsDirectoryURL() else { return [] }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { ["jsonl", "txt"].contains($0.pathExtension.lowercased()) }
    }

    static func latestSessionFiles() -> SessionFiles? {
        let urls = existingLogURLs()
        guard !urls.isEmpty else { return nil }

        let latestURL = urls.max { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]).contentModificationDate)
                ?? (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate)
                ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]).contentModificationDate)
                ?? (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate)
                ?? .distantPast
            return lhsDate < rhsDate
        }

        guard let latestURL else { return nil }
        let stem = latestURL.deletingPathExtension().lastPathComponent
        let directoryURL = latestURL.deletingLastPathComponent()
        let jsonURL = directoryURL.appendingPathComponent(stem).appendingPathExtension("jsonl")
        let textURL = directoryURL.appendingPathComponent(stem).appendingPathExtension("txt")
        return SessionFiles(jsonURL: jsonURL, textURL: textURL)
    }

    static func exportURLsForLatestSession() -> [URL] {
        latestSessionFiles()?.exportURLs ?? []
    }

    @discardableResult
    static func deleteAllLogs() throws -> Int {
        let urls = existingLogURLs()
        for url in urls {
            try FileManager.default.removeItem(at: url)
        }
        return urls.count
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

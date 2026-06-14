import Foundation

enum FileDeletionService {
    struct DeletionResult {
        let succeeded: [URL]
        let failed: [(URL, Error)]
    }

    static func moveToTrash(urls: [URL]) -> DeletionResult {
        var succeeded: [URL] = []
        var failed: [(URL, Error)] = []

        for url in urls {
            do {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                succeeded.append(url)
            } catch {
                failed.append((url, error))
            }
        }

        return DeletionResult(succeeded: succeeded, failed: failed)
    }
}

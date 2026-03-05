import UIKit

enum AvatarStore {
    private static let fileName = "player-avatar.jpg"
    private static let legacyUserDefaultsKey = "playerHeadImage"

    static func load() -> UIImage? {
        if let image = loadFromDisk() {
            return image
        }

        guard
            let data = UserDefaults.standard.data(forKey: legacyUserDefaultsKey),
            let image = UIImage(data: data),
            let migrated = save(image)
        else {
            return nil
        }

        UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey)
        return migrated
    }

    @discardableResult
    static func save(_ image: UIImage) -> UIImage? {
        guard
            let prepared = preparedAvatar(from: image),
            let data = prepared.jpegData(compressionQuality: 0.82),
            let url = storageURL()
        else {
            return nil
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: url, options: .atomic)
            return prepared
        } catch {
            return prepared
        }
    }

    static func preparedAvatar(from image: UIImage, pixelSize: CGFloat = 256) -> UIImage? {
        guard pixelSize > 0 else { return nil }
        guard image.size.width > 0, image.size.height > 0 else { return nil }

        let squareLength = min(image.size.width, image.size.height)
        let cropOrigin = CGPoint(
            x: (image.size.width - squareLength) / 2,
            y: (image.size.height - squareLength) / 2
        )
        let cropRect = CGRect(origin: cropOrigin, size: CGSize(width: squareLength, height: squareLength))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: pixelSize, height: pixelSize),
            format: format
        )
        let scale = pixelSize / squareLength

        return renderer.image { _ in
            image.draw(
                in: CGRect(
                    x: -cropRect.origin.x * scale,
                    y: -cropRect.origin.y * scale,
                    width: image.size.width * scale,
                    height: image.size.height * scale
                )
            )
        }
    }

    private static func loadFromDisk() -> UIImage? {
        guard let url = storageURL(), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private static func storageURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("VipeRun", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}

import AVFoundation
import UIKit
import UniformTypeIdentifiers
import os.log

private let log = Logger(subsystem: "com.snapgrid.ios.ShareExtension", category: "Share")

class ShareViewController: UIViewController {

    private let appGroupID = "group.com.snapgrid"

    private var statusLabel: UILabel!
    private var spinner: UIActivityIndicatorView!
    private var iconLabel: UILabel!
    private var card: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        processShareInput()
    }

    // MARK: - UI

    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        card = UIView()
        card.backgroundColor = UIColor.systemBackground
        card.layer.cornerRadius = 16
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        iconLabel = UILabel()
        iconLabel.text = "⊞"
        iconLabel.font = .systemFont(ofSize: 32, weight: .medium)
        iconLabel.textAlignment = .center
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(iconLabel)

        spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        card.addSubview(spinner)

        statusLabel = UILabel()
        statusLabel.text = "Saving to SnapGrid…"
        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        statusLabel.textColor = .label
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 220),

            iconLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            iconLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),

            spinner.topAnchor.constraint(equalTo: iconLabel.bottomAnchor, constant: 16),
            spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            statusLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24),
        ])
    }

    // MARK: - Process Shared Input

    private func processShareInput() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            completeWithError("Nothing to save")
            return
        }

        let providers = items.flatMap { $0.attachments ?? [] }

        log.info("[\(providers.count)] provider(s)")
        for (i, provider) in providers.enumerated() {
            log.info("  [\(i)] \(provider.registeredTypeIdentifiers.joined(separator: ", "))")
        }

        // Strategy 1: Direct image attachment
        if let imageProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            log.info("Strategy: direct image provider")
            loadImageFromProvider(imageProvider)
            return
        }

        // Strategy 2: URL attachment (image URL from Safari/X)
        if let urlProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            log.info("Strategy: URL provider")
            loadImageFromURL(urlProvider)
            return
        }

        completeWithError("This content doesn't contain an image or video link")
    }

    // MARK: - Image Loading Strategies

    private func loadImageFromProvider(_ provider: NSItemProvider) {
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
            if let image = object as? UIImage {
                log.info("loadObject(UIImage) OK: \(Int(image.size.width))x\(Int(image.size.height))")
                DispatchQueue.main.async { self?.saveImage(image) }
                return
            }
            log.info("loadObject(UIImage) failed: \(error?.localizedDescription ?? "nil"), trying data representation")
            self?.loadImageViaDataRepresentation(from: provider)
        }
    }

    private func loadImageViaDataRepresentation(from provider: NSItemProvider) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, error in
            if let data {
                log.info("loadDataRep: \(data.count) bytes")

                if let image = UIImage(data: data) {
                    log.info("loadDataRep: raw image OK")
                    DispatchQueue.main.async { self?.saveImage(image) }
                    return
                }

                // Some apps (e.g. X/Twitter) wrap image data in a binary plist
                if data.prefix(8) == Data("bplist00".utf8) {
                    log.info("loadDataRep: bplist detected, unarchiving")
                    if let image = self?.unarchiveImage(from: data) {
                        DispatchQueue.main.async { self?.saveImage(image) }
                        return
                    }
                }

                // Scan for embedded JPEG/PNG within the raw bytes
                if let image = self?.extractEmbeddedImage(from: data) {
                    log.info("loadDataRep: found embedded image")
                    DispatchQueue.main.async { self?.saveImage(image) }
                    return
                }
            } else {
                log.info("loadDataRep: no data, err=\(error?.localizedDescription ?? "nil")")
            }

            // Try specific image subtypes (jpeg, png, webp, gif, heic)
            self?.loadImageViaSubtype(from: provider)
        }
    }

    private func loadImageViaSubtype(from provider: NSItemProvider) {
        let subtypes: [(String, String)] = [
            (UTType.jpeg.identifier, "jpeg"),
            (UTType.png.identifier, "png"),
            (UTType.webP.identifier, "webp"),
            (UTType.gif.identifier, "gif"),
            (UTType.heic.identifier, "heic"),
        ]
        let conforming = subtypes.filter { provider.hasItemConformingToTypeIdentifier($0.0) }
        log.info("Subtype fallback: conforming=\(conforming.map { $0.1 })")

        guard let first = conforming.first else {
            // No specific subtypes — try loadItem as final fallback
            loadImageViaLoadItem(from: provider)
            return
        }

        provider.loadDataRepresentation(forTypeIdentifier: first.0) { [weak self] data, error in
            if let data, let image = UIImage(data: data) {
                log.info("Subtype \(first.1) loadDataRep OK: \(data.count)b")
                DispatchQueue.main.async { self?.saveImage(image) }
                return
            }

            // loadFileRepresentation as last file-based attempt
            provider.loadFileRepresentation(forTypeIdentifier: first.0) { [weak self] tempURL, error in
                if let tempURL,
                   let data = try? Data(contentsOf: tempURL),
                   let image = UIImage(data: data) {
                    log.info("Subtype \(first.1) loadFileRep OK: \(data.count)b")
                    DispatchQueue.main.async { self?.saveImage(image) }
                    return
                }
                log.error("All image loading strategies exhausted")
                DispatchQueue.main.async {
                    self?.completeWithError("Couldn't read the image data")
                }
            }
        }
    }

    private func loadImageViaLoadItem(from provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, error in
            log.info("loadItem fallback: type=\(type(of: item)), err=\(error?.localizedDescription ?? "nil")")
            var image: UIImage?
            if let data = item as? Data {
                image = UIImage(data: data)
            } else if let url = item as? URL {
                if url.isFileURL {
                    image = UIImage(contentsOfFile: url.path)
                } else if let data = try? Data(contentsOf: url) {
                    image = UIImage(data: data)
                }
            }
            DispatchQueue.main.async {
                if let image {
                    self?.saveImage(image)
                } else {
                    self?.completeWithError("Couldn't read the image data")
                }
            }
        }
    }

    // MARK: - Binary Plist / Embedded Image Parsing

    private func unarchiveImage(from data: Data) -> UIImage? {
        if let image = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIImage.self, from: data) {
            return image
        }
        if let imageData = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSData.self, from: data) {
            return UIImage(data: imageData as Data)
        }
        if let url = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: data),
           let fileURL = url as URL?,
           fileURL.isFileURL,
           let imageData = try? Data(contentsOf: fileURL) {
            return UIImage(data: imageData)
        }
        return nil
    }

    private func extractEmbeddedImage(from data: Data) -> UIImage? {
        let bytes = [UInt8](data)
        // JPEG: FF D8 FF
        if let offset = findSignature([0xFF, 0xD8, 0xFF], in: bytes) {
            let subdata = data.subdata(in: offset..<data.count)
            if let image = UIImage(data: subdata) { return image }
        }
        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if let offset = findSignature([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], in: bytes) {
            let subdata = data.subdata(in: offset..<data.count)
            if let image = UIImage(data: subdata) { return image }
        }
        return nil
    }

    private func findSignature(_ signature: [UInt8], in bytes: [UInt8]) -> Int? {
        guard bytes.count >= signature.count else { return nil }
        outer: for i in 0...(bytes.count - signature.count) {
            for j in 0..<signature.count {
                if bytes[i + j] != signature[j] { continue outer }
            }
            return i
        }
        return nil
    }

    // MARK: - URL-based Loading

    private func loadImageFromURL(_ provider: NSItemProvider) {
        _ = provider.loadObject(ofClass: URL.self) { [weak self] object, error in
            guard let url = object else {
                log.error("loadObject(URL) failed: \(error?.localizedDescription ?? "nil")")
                DispatchQueue.main.async { self?.completeWithError("Couldn't read the shared link") }
                return
            }
            log.info("URL: \(url.absoluteString)")

            // Check for X / Twitter video URLs first
            if TwitterVideoService.isTwitterURL(url) {
                log.info("Detected X/Twitter URL, extracting media")
                DispatchQueue.main.async {
                    self?.statusLabel.text = "Downloading from X…"
                }
                self?.downloadTwitterMedia(from: url)
                return
            }

            self?.downloadImage(from: url)
        }
    }

    private func downloadTwitterMedia(from tweetURL: URL) {
        Task {
            do {
                let result = try await TwitterVideoService.extractMediaURL(from: tweetURL)

                let mediaURL: URL
                switch result {
                case .video(let url): mediaURL = url
                case .image(let url): mediaURL = url
                }
                log.info("Media URL resolved: \(mediaURL.absoluteString.prefix(100))")

                let (data, response) = try await URLSession.shared.data(from: mediaURL)
                let http = response as? HTTPURLResponse
                log.info("Media download: HTTP \(http?.statusCode ?? 0), \(data.count)b")

                guard let http, (200...299).contains(http.statusCode) else {
                    throw TwitterVideoService.TwitterError.apiRequestFailed(
                        (response as? HTTPURLResponse)?.statusCode ?? 0
                    )
                }

                switch result {
                case .video:
                    await MainActor.run { self.saveVideo(data) }
                case .image:
                    guard let image = UIImage(data: data) else {
                        throw TwitterVideoService.TwitterError.malformedResponse
                    }
                    await MainActor.run { self.saveImage(image) }
                }
            } catch {
                log.error("Twitter media extraction failed: \(error.localizedDescription)")
                await MainActor.run { self.completeWithError(error.localizedDescription) }
            }
        }
    }

    private func downloadImage(from url: URL) {
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            let http = response as? HTTPURLResponse
            log.info("fetch: HTTP \(http?.statusCode ?? 0), type=\(http?.value(forHTTPHeaderField: "Content-Type") ?? "?"), \(data?.count ?? 0)b")

            guard let data else {
                DispatchQueue.main.async { self?.completeWithError("Download failed") }
                return
            }

            if let image = UIImage(data: data) {
                DispatchQueue.main.async { self?.saveImage(image) }
                return
            }

            // Not an image — try extracting og:image from HTML
            if let html = String(data: data, encoding: .utf8),
               let ogImageURL = self?.extractOGImage(from: html) {
                log.info("Found og:image: \(ogImageURL.absoluteString.prefix(80))")
                self?.downloadImage(from: ogImageURL)
                return
            }

            DispatchQueue.main.async { self?.completeWithError("This link doesn't contain an image") }
        }
        task.resume()
    }

    private func extractOGImage(from html: String) -> URL? {
        let pattern = #"<meta[^>]*property\s*=\s*"og:image"[^>]*content\s*=\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            let altPattern = #"<meta[^>]*content\s*=\s*"([^"]+)"[^>]*property\s*=\s*"og:image""#
            guard let altRegex = try? NSRegularExpression(pattern: altPattern, options: .caseInsensitive),
                  let altMatch = altRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let altRange = Range(altMatch.range(at: 1), in: html) else {
                return nil
            }
            return URL(string: String(html[altRange]))
        }
        return URL(string: String(html[range]))
    }

    // MARK: - Save to App Group Shared Container

    private func saveImage(_ image: UIImage) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: self.appGroupID
            ) else {
                DispatchQueue.main.async {
                    self.completeWithError("App Group not available")
                }
                return
            }

            let pendingDir = containerURL.appendingPathComponent("pending", isDirectory: true)
            let imagesDir = pendingDir.appendingPathComponent("images", isDirectory: true)
            let metadataDir = pendingDir.appendingPathComponent("metadata", isDirectory: true)

            let fm = FileManager.default
            try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            try? fm.createDirectory(at: metadataDir, withIntermediateDirectories: true)

            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
            let random = String((0..<7).map { _ in chars.randomElement()! })
            let id = "img_\(timestamp)_\(random)"

            guard let pngData = image.pngData() else {
                DispatchQueue.main.async {
                    self.completeWithError("Couldn't process the image")
                }
                return
            }

            let width = Int(image.size.width * image.scale)
            let height = Int(image.size.height * image.scale)

            let imageURL = imagesDir.appendingPathComponent("\(id).png")
            do {
                try pngData.write(to: imageURL, options: .atomic)
            } catch {
                DispatchQueue.main.async {
                    self.completeWithError("Couldn't save the image")
                }
                return
            }

            let sidecar = ShareSidecarMetadata(
                id: id,
                type: "image",
                width: width,
                height: height,
                createdAt: Date(),
                duration: nil,
                spaceId: nil,
                imageContext: nil,
                imageSummary: nil,
                patterns: nil
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let metadataURL = metadataDir.appendingPathComponent("\(id).json")
            if let jsonData = try? encoder.encode(sidecar) {
                try? jsonData.write(to: metadataURL, options: .atomic)
            }

            DispatchQueue.main.async {
                self.completeWithSuccess()
            }
        }
    }

    // MARK: - Save Video

    private func saveVideo(_ videoData: Data) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: self.appGroupID
            ) else {
                await MainActor.run { self.completeWithError("App Group not available") }
                return
            }

            let pendingDir = containerURL.appendingPathComponent("pending", isDirectory: true)
            let imagesDir = pendingDir.appendingPathComponent("images", isDirectory: true)
            let metadataDir = pendingDir.appendingPathComponent("metadata", isDirectory: true)

            let fm = FileManager.default
            try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            try? fm.createDirectory(at: metadataDir, withIntermediateDirectories: true)

            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
            let random = String((0..<7).map { _ in chars.randomElement()! })
            let id = "vid_\(timestamp)_\(random)"

            let videoURL = imagesDir.appendingPathComponent("\(id).mp4")
            do {
                try videoData.write(to: videoURL, options: .atomic)
            } catch {
                await MainActor.run { self.completeWithError("Couldn't save the video") }
                return
            }

            // Extract dimensions and duration from the saved file
            let asset = AVURLAsset(url: videoURL)
            var width = 0
            var height = 0
            var duration: Double?

            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                let size = try? await track.load(.naturalSize)
                let transform = try? await track.load(.preferredTransform)
                if let size, let transform {
                    let transformed = size.applying(transform)
                    width = Int(abs(transformed.width))
                    height = Int(abs(transformed.height))
                }
            }
            let cmDuration = try? await asset.load(.duration)
            if let cmDuration, cmDuration.isValid && !cmDuration.isIndefinite {
                duration = CMTimeGetSeconds(cmDuration)
            }

            log.info("Video dimensions: \(width)x\(height), duration: \(duration ?? 0)s")

            let sidecar = ShareSidecarMetadata(
                id: id,
                type: "video",
                width: width,
                height: height,
                createdAt: Date(),
                duration: duration,
                spaceId: nil,
                imageContext: nil,
                imageSummary: nil,
                patterns: nil
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let metadataURL = metadataDir.appendingPathComponent("\(id).json")
            if let jsonData = try? encoder.encode(sidecar) {
                try? jsonData.write(to: metadataURL, options: .atomic)
            }

            log.info("Saved video: \(id).mp4, \(videoData.count) bytes")
            await MainActor.run { self.completeWithSuccess() }
        }
    }

    // MARK: - Completion

    private func completeWithSuccess() {
        spinner.stopAnimating()
        iconLabel.text = "✓"
        statusLabel.text = "Saved!"

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func completeWithError(_ message: String) {
        log.error("Share failed: \(message)")
        spinner.stopAnimating()
        iconLabel.text = "✗"
        statusLabel.text = message
        statusLabel.numberOfLines = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.extensionContext?.cancelRequest(
                withError: NSError(domain: "com.snapgrid.share", code: 1)
            )
        }
    }
}

// MARK: - Sidecar Model (matches Mac app's MetadataSidecarService format)

private struct ShareSidecarMetadata: Codable {
    let id: String
    let type: String
    let width: Int
    let height: Int
    let createdAt: Date
    let duration: Double?
    let spaceId: String?
    let imageContext: String?
    let imageSummary: String?
    let patterns: [ShareSidecarPattern]?
}

private struct ShareSidecarPattern: Codable {
    let name: String
    let confidence: Double
}

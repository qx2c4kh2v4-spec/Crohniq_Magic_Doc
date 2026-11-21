import AppKit
import Photos
import SwiftUI

final class PhotoLibrary: ObservableObject {
    static let shared = PhotoLibrary()

    @Published private(set) var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var panoramas: [PHAsset] = []
    @Published private(set) var appleWallpapers: [URL] = []

    private var requestingAuthorization = false
    private var didLoad = false
    private var didLoadWallpapers = false

    func refresh(force: Bool = false) {
        if force || !didLoadWallpapers {
            appleWallpapers = Self.loadAppleWallpapers()
            didLoadWallpapers = true
        }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorization = status

        guard status == .authorized || status == .limited else {
            assets = []
            panoramas = []
            guard status == .notDetermined, !requestingAuthorization else { return }
            requestingAuthorization = true
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
                DispatchQueue.main.async {
                    self?.requestingAuthorization = false
                    self?.authorization = status
                    self?.refresh(force: true)
                }
            }
            return
        }

        guard force || !didLoad else { return }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 500
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var fetched: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in fetched.append(asset) }
        assets = fetched

        var fetchedPanoramas: [PHAsset] = []
        let panoramaCollections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumPanoramas,
            options: nil
        )
        if let collection = panoramaCollections.firstObject {
            let panoramaOptions = PHFetchOptions()
            panoramaOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            panoramaOptions.fetchLimit = 500
            let panoramaResult = PHAsset.fetchAssets(in: collection, options: panoramaOptions)
            panoramaResult.enumerateObjects { asset, _, _ in fetchedPanoramas.append(asset) }
        }

        for asset in fetched {
            let ratio = CGFloat(asset.pixelWidth) / CGFloat(max(asset.pixelHeight, 1))
            if ratio >= 1.8 {
                if !fetchedPanoramas.contains(where: { $0.localIdentifier == asset.localIdentifier }) {
                    fetchedPanoramas.append(asset)
                }
            }
        }
        panoramas = fetchedPanoramas
        didLoad = true
    }

    func requestImage(for asset: PHAsset, size: CGSize, completion: @escaping (NSImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            DispatchQueue.main.async { completion(image) }
        }
    }

    static func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!)
    }

    private static func loadAppleWallpapers() -> [URL] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/System/Library/Desktop Pictures", isDirectory: true),
            URL(fileURLWithPath: "/Library/Desktop Pictures", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Desktop Pictures", isDirectory: true)
        ]
        let imageExtensions: Set<String> = ["heic", "jpeg", "jpg", "png", "tif", "tiff"]
        var wallpapers = Set<URL>()

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [],
                errorHandler: { url, error in
                    NSLog("Could not read Apple wallpaper at %@: %@", url.path, error.localizedDescription)
                    return true
                }
            ) else { continue }

            for case let url as URL in enumerator
            where imageExtensions.contains(url.pathExtension.lowercased()) {
                wallpapers.insert(url)
            }
        }

        return wallpapers.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }
}

struct PhotoThumbnail: View {
    let asset: PHAsset
    let targetSize: CGSize
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Theme.tileHi)
                    .overlay { Image(systemName: "photo").foregroundStyle(Theme.secondary) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: asset.localIdentifier + "\(Int(targetSize.width))x\(Int(targetSize.height))") {
            PhotoLibrary.shared.requestImage(for: asset, size: targetSize) { image = $0 }
        }
    }
}

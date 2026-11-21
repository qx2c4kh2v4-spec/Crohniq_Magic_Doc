import AppKit
import Photos
import SwiftUI

final class PhotoLibrary: ObservableObject {
    static let shared = PhotoLibrary()

    @Published private(set) var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var assets: [PHAsset] = []

    private var requestingAuthorization = false
    private var didLoad = false

    func refresh(force: Bool = false) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorization = status

        guard status == .authorized || status == .limited else {
            assets = []
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
        options.fetchLimit = 48
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var fetched: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in fetched.append(asset) }
        assets = fetched
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

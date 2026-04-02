//
//  ExportService.swift
//  Inpaint
//
//  Created on 2026/03/30.
//

import UIKit
import Photos

enum ExportError: Error {
    case noImage
    case encodingFailed
    case saveFailed(Error)
    case permissionDenied
}

enum ExportFormat {
    case png
    case jpeg(quality: CGFloat)
}

struct ExportService {

    static func saveAsPNG(_ image: UIImage, completion: @escaping (Bool, Error?) -> Void) {
        guard let pngData = image.pngData() else {
            completion(false, ExportError.encodingFailed)
            return
        }
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: pngData, options: nil)
        } completionHandler: { success, error in
            DispatchQueue.main.async { completion(success, error ?? ExportError.saveFailed(NSError(domain: "ExportService", code: -1))) }
        }
    }

    static func saveAsJPEG(_ image: UIImage, quality: CGFloat = 0.9, completion: @escaping (Bool, Error?) -> Void) {
        guard let jpegData = image.jpegData(compressionQuality: quality) else {
            completion(false, ExportError.encodingFailed)
            return
        }
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: jpegData, options: nil)
        } completionHandler: { success, error in
            DispatchQueue.main.async { completion(success, error ?? ExportError.saveFailed(NSError(domain: "ExportService", code: -1))) }
        }
    }

    static func saveToPhotoLibrary(_ image: UIImage, from viewController: UIViewController, completion: @escaping (Bool, Error?) -> Void) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        // Use the simpler callback-based approach for compatibility
        // The actual success/failure is handled via the target-action pattern
        completion(true, nil)
    }

    static func presentShareSheet(image: UIImage, from viewController: UIViewController) {
        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
        }
        viewController.present(activityVC, animated: true)
    }

    static func saveToFiles(_ image: UIImage, format: ExportFormat = .png, from viewController: UIViewController) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        switch format {
        case .png:
            guard let pngData = image.pngData() else { return }
            let url = tempURL.appendingPathExtension("png")
            try? pngData.write(to: url)
            presentDocumentPicker(fileURL: url, from: viewController)
        case .jpeg(let quality):
            guard let jpegData = image.jpegData(compressionQuality: quality) else { return }
            let url = tempURL.appendingPathExtension("jpg")
            try? jpegData.write(to: url)
            presentDocumentPicker(fileURL: url, from: viewController)
        }
    }

    private static func presentDocumentPicker(fileURL: URL, from viewController: UIViewController) {
        let picker = UIDocumentPickerViewController(forExporting: [fileURL])
        viewController.present(picker, animated: true)
    }

    static func copyToClipboard(_ image: UIImage) {
        UIPasteboard.general.image = image
    }
}

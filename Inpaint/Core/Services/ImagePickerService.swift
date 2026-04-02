//
//  ImagePickerService.swift
//  Inpaint
//
//  Created on 2026/03/30.
//

import UIKit
import PhotosUI

final class ImagePickerService: NSObject {

    private var completion: ((UIImage?) -> Void)?

    func pickImage(from viewController: UIViewController, completion: @escaping (UIImage?) -> Void) {
        self.completion = completion

        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        viewController.present(picker, animated: true)
    }
}

extension ImagePickerService: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else {
            completion?(nil)
            completion = nil
            return
        }

        provider.loadObject(ofClass: UIImage.self) { [weak self] image, _ in
            DispatchQueue.main.async {
                self?.completion?(image as? UIImage)
                self?.completion = nil
            }
        }
    }
}

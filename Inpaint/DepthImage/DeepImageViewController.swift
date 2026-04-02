//
//  DeepImageViewController.swift
//  Inpaint
//
//  Created by wudijimao on 2023/12/25.
//

import UIKit
import Vision
import CoreML
import SnapKit

// 图片生成深度图
class DeepImageViewController: BaseEditingViewController {

    // Core ML 模型
    lazy var prediction: MiDaSImageDepthPrediction = MiDaSImageDepthPrediction()

    var lama: LaMaFP16_512?
    private var depthData: [Float]?
    private var depthImage: UIImage?
    private var depthSceneVC: DepthImageSenceViewController?
    private var is3DGenerated = false

    // MARK: - Init

    @MainActor override init(toolID: String) {
        super.init(toolID: toolID)
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadModel()
    }

    func loadModel() {
        _ = prediction
    }

    override func setupToolUI() {
        if !isImageSelected {
            setupEmptyState(config: EmptyStateConfig(
                toolID: toolID,
                iconName: "cube",
                titleKey: "empty_depth_title",
                descriptionKey: "empty_depth_description",
                buttonTitleKey: "select_photo"
            ))
            return
        }

        setupDeepImageUI()
    }

    func setupDeepImageUI() {
        guard let original = originalImage else { return }
        showProcessing(message: *"processing")
        generateGrayScaleImage(original)
    }

    func generateGrayScaleImage(_ image: UIImage) {
        prediction.depthPrediction(image: image) { [weak self] depthImage, depthData, err in
            guard let self = self else { return }
            guard let depthData = depthData, let depthImg = depthImage else {
                self.hideProcessing()
                return
            }
            self.depthData = depthData
            self.depthImage = depthImg
            self.is3DGenerated = true
            self.hideProcessing()

            let vc = DepthImageSenceViewController(image: image, depthData: depthData)
            self.depthSceneVC = vc
            self.addChild(vc)
            self.view.addSubview(vc.view)
            vc.view.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
            vc.didMove(toParent: self)
        }
    }

    override func setupNavigationItems() {
        setupUnifiedNavigationItems()
    }

    // MARK: - Empty State

    override func presentImagePicker() {
        pickImageFromLibrary { [weak self] image in
            guard let self else { return }
            let scaledImage = image.scaleToLimit(size: CGSize(width: kLimitImageSize, height: kLimitImageSize))
            self.setImage(scaledImage)
        }
    }

    override func didSetImage() {
        setupDeepImageUI()
    }

    override func resetEditState() {
        super.resetEditState()
        depthData = nil
        depthImage = nil
        depthSceneVC?.willMove(toParent: nil)
        depthSceneVC?.view.removeFromSuperview()
        depthSceneVC?.removeFromParent()
        depthSceneVC = nil
        is3DGenerated = false
    }

    // MARK: - Save

    @objc func onSaveDepthMap() {
        guard let depthImg = depthImage else { return }
        UIImageWriteToSavedPhotosAlbum(depthImg, self, #selector(imageSaveCallback(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func imageSaveCallback(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer?) {
        if let error = error {
            view.makeToast("Save failed: \(error.localizedDescription)")
        } else {
            view.makeToast(*"toast_save_success", duration: 2.0, position: .bottom)
        }
    }

    override func showProcessing(message: String) {
        // Already handled by child view controller
    }

    override func hideProcessing() {
        // Already handled by child view controller
    }
}

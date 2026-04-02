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

    override var toolID: String { "depth_image" }

    // Core ML 模型
    lazy var prediction: MiDaSImageDepthPrediction = MiDaSImageDepthPrediction()

    var lama: LaMaFP16_512?
    private var depthData: [Float]?
    private var depthImage: UIImage?
    private var depthSceneVC: DepthImageSenceViewController?

    @MainActor override init(image: UIImage) {
        super.init(image: image)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // 加载模型
        loadModel()

        // 对选择的图片进行处理
        generateGrayScaleImage(originalImage)
    }

    func loadModel() {
        _ = prediction
    }

    func generateGrayScaleImage(_ image: UIImage) {
        prediction.depthPrediction(image: image) { [weak self] depthImage, depthData, err in
            guard let self = self else { return }
            guard let depthData = depthData, let depthImg = depthImage else { return }
            self.depthData = depthData
            self.depthImage = depthImg
            let vc = DepthImageSenceViewController(image: image, depthData: depthData)
            self.depthSceneVC = vc
            self.addChild(vc)
            self.view.addSubview(vc.view)
            vc.view.snp.makeConstraints { make in
                make.edges.equalToSuperview()
                vc.didMove(toParent: self)
            }
        }
    }

    override func setupNavigationItems() {
        let backButton = UIBarButtonItem(title: *"back", style: .plain, target: self, action: #selector(onBack))
        let saveButton = UIBarButtonItem(title: *"save_to_photo_lib", style: .plain, target: self, action: #selector(onSave))
        let saveDepthButton = UIBarButtonItem(title: *"save_depth_map", style: .plain, target: self, action: #selector(onSaveDepthMap))
        compareButton = makeCompareButton()
        undoButton.isEnabled = false

        navigationItem.leftBarButtonItems = [backButton]
        navigationItem.rightBarButtonItems = [compareButton!, saveButton, saveDepthButton, undoButton]
    }

    @objc private func onBack() {
        navigationController?.popViewController(animated: true)
    }

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

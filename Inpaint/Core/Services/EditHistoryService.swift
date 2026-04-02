//
//  EditHistoryService.swift
//  Inpaint
//
//  Created on 2026/03/31.
//

import UIKit

struct EditRecord: Codable, Identifiable {
    let id: UUID
    let toolID: String
    let date: Date
    let thumbnailPath: String
    let resultPath: String
}

final class EditHistoryService {
    static let shared = EditHistoryService()

    private let userDefaultsKey = "edit_history_records"
    private let maxRecords = 50
    private let thumbnailSize = CGSize(width: 200, height: 200)

    private var records: [EditRecord] = []

    private init() {
        loadRecords()
    }

    // MARK: - Public Methods

    func addRecord(toolID: String, resultImage: UIImage) {
        let thumbnail = resultImage.scaleTo(size: thumbnailSize)
        let thumbnailPath = saveImage(thumbnail, prefix: "thumb")
        let resultPath = saveImage(resultImage, prefix: "result")

        let record = EditRecord(
            id: UUID(),
            toolID: toolID,
            date: Date(),
            thumbnailPath: thumbnailPath,
            resultPath: resultPath
        )

        records.insert(record, at: 0)

        // Trim to max records
        if records.count > maxRecords {
            let removedRecords = records.suffix(from: maxRecords)
            for record in removedRecords {
                deleteImage(at: record.thumbnailPath)
                deleteImage(at: record.resultPath)
            }
            records = Array(records.prefix(maxRecords))
        }

        saveRecords()
    }

    func allRecords() -> [EditRecord] {
        return records
    }

    func deleteRecord(id: UUID) {
        if let index = records.firstIndex(where: { $0.id == id }) {
            let record = records[index]
            deleteImage(at: record.thumbnailPath)
            deleteImage(at: record.resultPath)
            records.remove(at: index)
            saveRecords()
        }
    }

    func clearAll() {
        for record in records {
            deleteImage(at: record.thumbnailPath)
            deleteImage(at: record.resultPath)
        }
        records.removeAll()
        saveRecords()
    }

    func loadThumbnail(for record: EditRecord) -> UIImage? {
        return UIImage(contentsOfFile: record.thumbnailPath)
    }

    func loadResultImage(for record: EditRecord) -> UIImage? {
        return UIImage(contentsOfFile: record.resultPath)
    }

    // MARK: - Private Methods

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([EditRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded
    }

    private func saveRecords() {
        guard let encoded = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
    }

    private func saveImage(_ image: UIImage, prefix: String) -> String {
        let filename = "\(prefix)_\(UUID().uuidString).jpg"
        let url = URL.documentsDirectory.appendingPathComponent(filename)

        guard let data = image.jpegData(compressionQuality: 0.8) else {
            return ""
        }

        do {
            try data.write(to: url)
            return url.path
        } catch {
            return ""
        }
    }

    private func deleteImage(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}

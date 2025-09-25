//
//  FileItem.swift
//  GainMapHDRConvertor
//
//  Created by Hongyu Shi on 2025/9/25.
//

import Foundation
import CoreImage
import SwiftUI
import Combine

// MARK: - 转换状态
enum ConversionStatus {
    case pending       // 等待转换
    case processing    // 转换中
    case completed     // 转换完成
    case failed        // 转换失败
    
    var iconName: String {
        switch self {
        case .pending: return "clock"
        case .processing: return "arrow.clockwise"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .pending: return .secondary
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}

// MARK: - 图像加载状态
enum ImageLoadingStatus {
    case loading       // 正在加载
    case loaded        // 加载完成
    case failed        // 加载失败
}

// MARK: - 文件项目
class FileItem: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    @Published var hdrImage: CIImage?
    @Published var imageLoadingStatus: ImageLoadingStatus = .loading
    @Published var status: ConversionStatus = .pending
    @Published var progress: Double = 0.0
    @Published var errorMessage: String?
    @Published var outputURL: URL?
    
    private var imageData: Data?
    
    // 计算属性
    var fileName: String {
        url.lastPathComponent
    }
    
    var fileSize: String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return "未知大小"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var isHDRImage: Bool {
        guard imageLoadingStatus == .loaded, let image = hdrImage else { return false }
        return image.colorSpace?.name != CGColorSpace.sRGB
    }
    
    var detectedColorSpace: ColorSpace {
        guard imageLoadingStatus == .loaded, let image = hdrImage else { return .p3 }
        return ColorSpace.detectFromImage(image)
    }
    
    var imageInfo: String {
        switch imageLoadingStatus {
        case .loading:
            return "正在加载..."
        case .failed:
            return "加载失败"
        case .loaded:
            guard let image = hdrImage else { return "加载失败" }
            let size = image.extent.size
            let colorSpaceName = detectedColorSpace.displayName
            return "\(Int(size.width))×\(Int(size.height)) • \(colorSpaceName)"
        }
    }
    
    init(url: URL) {
        self.url = url
        loadImage()
    }
    
    private func loadImage() {
        Task {
            do {
                // 开始访问安全作用域资源
                let wasAlreadyAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if wasAlreadyAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                let data = try Data(contentsOf: url)
                self.imageData = data
                
                await MainActor.run {
                    // 尝试作为 HDR 图像加载
                    if let hdrImage = CIImage(data: data, options: [.expandToHDR: true]) {
                        self.hdrImage = hdrImage
                        self.imageLoadingStatus = .loaded
                    } else if let regularImage = CIImage(data: data) {
                        self.hdrImage = regularImage
                        self.imageLoadingStatus = .loaded
                    } else {
                        self.errorMessage = "不支持的图像格式"
                        self.imageLoadingStatus = .failed
                        self.status = .failed
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "加载失败: \(error.localizedDescription)"
                    self.imageLoadingStatus = .failed
                    self.status = .failed
                }
            }
        }
    }
    
    // 获取临时文件用于转换
    func getTemporaryURL() throws -> URL {
        guard let data = imageData else {
            throw ConversionError.noInputImageFound
        }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)
        
        try data.write(to: tempURL)
        return tempURL
    }
    
    // 重置状态
    func reset() {
        status = .pending
        progress = 0.0
        errorMessage = nil
        outputURL = nil
    }
}

// MARK: - 文件项目集合
class FileItemCollection: ObservableObject {
    @Published var items: [FileItem] = []
    @Published var selectedItem: FileItem?
    
    var pendingItems: [FileItem] {
        items.filter { $0.status == .pending }
    }
    
    var completedItems: [FileItem] {
        items.filter { $0.status == .completed }
    }
    
    var failedItems: [FileItem] {
        items.filter { $0.status == .failed }
    }
    
    var hasItems: Bool {
        !items.isEmpty
    }
    
    var hasSelectedItem: Bool {
        selectedItem != nil
    }
    
    func addFiles(from urls: [URL]) {
        let newItems = urls.map { FileItem(url: $0) }
        items.append(contentsOf: newItems)
        
        // 如果之前没有选中项，选中第一个新添加的项
        if selectedItem == nil, let firstItem = newItems.first {
            // 延迟选择，给图像加载一些时间
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.selectedItem = firstItem
            }
        }
    }
    
    func removeItem(_ item: FileItem) {
        items.removeAll { $0.id == item.id }
        
        if selectedItem?.id == item.id {
            DispatchQueue.main.async {
                self.selectedItem = self.items.first
            }
        }
    }
    
    func removeAll() {
        items.removeAll()
        selectedItem = nil
    }
    
    func selectItem(_ item: FileItem) {
        DispatchQueue.main.async {
            self.selectedItem = item
        }
    }
    
    func resetAllStatus() {
        items.forEach { $0.reset() }
    }
}
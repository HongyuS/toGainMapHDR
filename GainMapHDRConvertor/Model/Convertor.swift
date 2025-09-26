//
//  Convertor.swift
//  GainMapHDRConvertor
//
//  Created by Hongyu Shi on 2025/9/25.
//

import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import SwiftUI
import Combine

// MARK: - Export Format Enums
enum ExportFormat: CaseIterable {
    case adaptive       // 默认格式 - adaptive gain map
    case rgbGainMap     // -b: RGB gain map with base image
    case appleType1     // -g: Apple gain map by CIFilter
    case appleType2     // -a: Apple gain map from ISO gain map
    case sdr            // -s: SDR only
    case pqHDR          // -p: PQ HDR
    case hlgHDR         // -h: HLG HDR
}

enum ColorSpace {
    case auto          // 自动检测
    case srgb          // sRGB / Rec.709
    case p3            // Display P3
    case rec2020       // Rec.2020
    
    var displayName: String {
        switch self {
        case .auto: return "自动检测"
        case .srgb: return "sRGB / Rec.709"
        case .p3: return "Display P3"
        case .rec2020: return "Rec.2020"
        }
    }
    
    var sdrColorSpace: CGColorSpace {
        switch self {
        case .auto, .srgb: return CGColorSpace(name: CGColorSpace.itur_709)!
        case .p3: return CGColorSpace(name: CGColorSpace.displayP3)!
        case .rec2020: return CGColorSpace(name: CGColorSpace.itur_2020_sRGBGamma)!
        }
    }
    
    var hdrColorSpace: CGColorSpace {
        switch self {
        case .auto, .srgb: return CGColorSpace(name: CGColorSpace.itur_709_PQ)!
        case .p3: return CGColorSpace(name: CGColorSpace.displayP3_PQ)!
        case .rec2020: return CGColorSpace(name: CGColorSpace.itur_2100_PQ)!
        }
    }
    
    var hlgColorSpace: CGColorSpace {
        switch self {
        case .auto, .srgb: return CGColorSpace(name: CGColorSpace.itur_709_HLG)!
        case .p3: return CGColorSpace(name: CGColorSpace.displayP3_HLG)!
        case .rec2020: return CGColorSpace(name: CGColorSpace.itur_2100_HLG)!
        }
    }
    
    // 从命令行参数字符串转换
    static func fromString(_ string: String) -> ColorSpace? {
        let lowercased = string.lowercased()
        switch lowercased {
        case "srgb", "709", "rec709", "rec.709", "bt709", "bt.709", "itu709":
            return .srgb
        case "p3", "dcip3", "dci-p3", "dci.p3", "displayp3":
            return .p3
        case "rec2020", "2020", "rec.2020", "bt2020", "itu2020", "2100", "rec2100", "rec.2100":
            return .rec2020
        default:
            return nil
        }
    }
    
    // 从 CIImage 自动检测色彩空间
    static func detectFromImage(_ image: CIImage) -> ColorSpace {
        let imageColorSpace = String(describing: image.colorSpace)
        
        if imageColorSpace.contains("709") || imageColorSpace.contains("sRGB") {
            return .srgb
        } else if imageColorSpace.contains("2100") || imageColorSpace.contains("2020") {
            return .rec2020
        }
        
        return .p3 // 默认为 P3
    }
}

enum ColorDepth {
    case eightBit      // 8位
    case tenBit        // 10位
}

enum FileFormat {
    case heic          // HEIC格式
    case jpeg          // JPEG格式
}

// MARK: - Conversion Options
struct ConversionOptions: Equatable {
    var imageQuality: Double = 0.99            // -q: 图像质量 (0.0-1.0)
    var toneMappingRatio: Float = 0.0          // -r: 色调映射比例 (0.0-1.0)
    var exportFormat: ExportFormat = .adaptive // 导出格式
    var colorSpace: ColorSpace = .auto         // -c: 色彩空间
    var colorDepth: ColorDepth = .eightBit     // -d: 色彩深度
    var fileFormat: FileFormat = .jpeg         // -j: 文件格式
    var scalingRatio: Float = 1.0              // -H: 增益图缩放 (1.0-2.0)
    var additionalText: String = ""            // -t: 附加文本
    var baseImageURL: URL?                     // -b: 基础图像URL
    
    var isHalfSize: Bool {
        return scalingRatio > 1.0
    }
    
    var isValid: (Bool, String?) {
        if imageQuality < 0.0 || imageQuality > 1.0 {
            return (false, "图像质量必须在 0.0 到 1.0 之间")
        }
        if toneMappingRatio < 0.0 || toneMappingRatio > 1.0 {
            return (false, "色调映射比例必须在 0.0 到 1.0 之间")
        }
        if scalingRatio < 1.0 || scalingRatio > 2.0 {
            return (false, "缩放比例必须在 1.0 到 2.0 之间")
        }
        
        // 检查格式兼容性
        if fileFormat == .jpeg && (exportFormat == .hlgHDR || exportFormat == .pqHDR) {
            return (false, "JPEG 格式不支持导出 HLG 或 PQ HDR")
        }
        
        return (true, nil)
    }
    
    // 应用约束条件并自动调整
    mutating func applyConstraints() {
        // JPEG 强制 8 位
        if fileFormat == .jpeg {
            colorDepth = .eightBit
        }
        
        // PQ HDR 强制 10 位
        if exportFormat == .pqHDR {
            colorDepth = .tenBit
        }
        
        // JPEG 不能输出 HDR，自动切换到适配格式
        if fileFormat == .jpeg && (exportFormat == .hlgHDR || exportFormat == .pqHDR) {
            exportFormat = .adaptive // 回退到默认格式
        }
    }
}

// MARK: - Conversion Result
enum ConversionResult {
    case success(URL)
    case failure(ConversionError)
}

enum ConversionError: LocalizedError {
    case invalidInputImage
    case noInputImageFound
    case baseImageNotFound
    case invalidParameters(String)
    case processingFailed(String)
    case exportFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidInputImage:
            return "输入图像无效"
        case .noInputImageFound:
            return "未找到输入图像"
        case .baseImageNotFound:
            return "未找到基础图像"
        case .invalidParameters(let message):
            return "参数无效: \(message)"
        case .processingFailed(let message):
            return "处理失败: \(message)"
        case .exportFailed(let message):
            return "导出失败: \(message)"
        }
    }
}

// MARK: - Main Convertor Class
class Convertor: ObservableObject {
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    
    private let ctx = CIContext()
    
    
    // MARK: - Core Conversion Method
    func convertHDRImage(
        inputURL: URL,
        outputURL: URL,
        options: ConversionOptions
    ) async -> ConversionResult {
        
        do {
            // 验证参数
            let validation = options.isValid
            if !validation.0 {
                return .failure(.invalidParameters(validation.1!))
            }
            
            // 加载 HDR 图像
            guard let hdrImage = CIImage(contentsOf: inputURL, options: [.expandToHDR: true]) else {
                return .failure(.noInputImageFound)
            }
            
            // 根据输入图像确定色彩空间
            let colorSpaces = determineColorSpaces(from: hdrImage, preferred: options.colorSpace)
            
            // 计算头部空间和色调映射
            let picHeadroom = try calculateMaxLuminance(from: hdrImage)
            
            if picHeadroom < 1.05 {
                print("警告: 图像头部空间 < 1.05，这是一个SDR图像，将输出SDR图像")
                return try await exportSDRImage(
                    image: hdrImage,
                    outputURL: outputURL,
                    colorSpaces: colorSpaces,
                    options: options
                )
            }
            
            let headroomRatio = 1.0 + picHeadroom - pow(picHeadroom, options.toneMappingRatio)
            
            // 生成 SDR 图像
            let sdrImage = try generateSDRImage(
                from: hdrImage,
                headroomRatio: headroomRatio,
                options: options
            )
            
            // 根据格式导出
            return try await exportImage(
                hdrImage: hdrImage,
                sdrImage: sdrImage,
                picHeadroom: picHeadroom,
                outputURL: outputURL,
                colorSpaces: colorSpaces,
                options: options
            )
            
        } catch {
            return .failure(.processingFailed(error.localizedDescription))
        }
    }
    
    // MARK: - Helper Methods
    
    private func determineColorSpaces(from image: CIImage, preferred: ColorSpace) -> (sdr: CGColorSpace, hdr: CGColorSpace, hlg: CGColorSpace) {
        // 如果用户选择了自动检测，或者选择了 .auto，从图像检测
        let actualColorSpace: ColorSpace
        if preferred == .auto {
            actualColorSpace = ColorSpace.detectFromImage(image)
        } else {
            actualColorSpace = preferred
        }
        
        return (
            sdr: actualColorSpace.sdrColorSpace,
            hdr: actualColorSpace.hdrColorSpace,
            hlg: actualColorSpace.hlgColorSpace
        )
    }
    
    private func calculateMaxLuminance(from image: CIImage) throws -> Float {
        let extent = image.extent
        
        let filter = CIFilter.areaMaximum()
        filter.inputImage = image
        filter.extent = extent
        
        guard let outputImage = filter.outputImage else {
            throw ConversionError.processingFailed("无法计算最大亮度")
        }
        
        var bitmap = [Float](repeating: 0, count: 4)
        ctx.render(outputImage,
                   toBitmap: &bitmap,
                   rowBytes: MemoryLayout<Float>.size * 4,
                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBAf,
                   colorSpace: nil)
        
        let r = bitmap[0]
        let g = bitmap[1]
        let b = bitmap[2]
        
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    
    private func generateSDRImage(
        from hdrImage: CIImage,
        headroomRatio: Float,
        options: ConversionOptions
    ) throws -> CIImage {
        
        switch options.exportFormat {
        case .appleType1:
            // Apple Type 1 使用 CIToneMapHeadroom
            return hdrImage.applyingFilter("CIToneMapHeadroom",
                                         parameters: ["inputSourceHeadroom": headroomRatio,
                                                    "inputTargetHeadroom": 1.0])
            
        case .rgbGainMap:
            // 如果指定了基础图像，使用基础图像；否则生成色调映射图像
            if let baseURL = options.baseImageURL,
               let baseImage = CIImage(contentsOf: baseURL) {
                return baseImage
            } else {
                print("警告: 无法加载基础图像，将通过色调映射生成基础图像")
                return hdrImage.applyingFilter("CIToneMapHeadroom",
                                             parameters: ["inputSourceHeadroom": headroomRatio,
                                                        "inputTargetHeadroom": 1.0])
            }
            
        default:
            // 其他格式使用默认色调映射
            return hdrImage.applyingFilter("CIToneMapHeadroom",
                                         parameters: ["inputSourceHeadroom": headroomRatio,
                                                    "inputTargetHeadroom": 1.0])
        }
    }
    
    private func exportSDRImage(
        image: CIImage,
        outputURL: URL,
        colorSpaces: (sdr: CGColorSpace, hdr: CGColorSpace, hlg: CGColorSpace),
        options: ConversionOptions
    ) async throws -> ConversionResult {
        
        let exportOptions: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): options.imageQuality
        ]
        
        do {
            if options.fileFormat == .jpeg {
                try ctx.writeJPEGRepresentation(of: image,
                                              to: outputURL,
                                              colorSpace: colorSpaces.sdr,
                                              options: exportOptions)
            } else {
                if options.colorDepth == .tenBit {
                    try ctx.writeHEIF10Representation(of: image,
                                                    to: outputURL,
                                                    colorSpace: colorSpaces.sdr,
                                                    options: exportOptions)
                } else {
                    try ctx.writeHEIFRepresentation(of: image,
                                                  to: outputURL,
                                                  format: .RGBA8,
                                                  colorSpace: colorSpaces.sdr,
                                                  options: exportOptions)
                }
            }
            return .success(outputURL)
        } catch {
            return .failure(.exportFailed(error.localizedDescription))
        }
    }
    
    private func exportImage(
        hdrImage: CIImage,
        sdrImage: CIImage,
        picHeadroom: Float,
        outputURL: URL,
        colorSpaces: (sdr: CGColorSpace, hdr: CGColorSpace, hlg: CGColorSpace),
        options: ConversionOptions
    ) async throws -> ConversionResult {
        
        switch options.exportFormat {
        case .hlgHDR:
            return try await exportHLGHDR(
                image: hdrImage,
                outputURL: outputURL,
                colorSpaces: colorSpaces,
                options: options
            )
            
        case .pqHDR:
            return try await exportPQHDR(
                image: hdrImage,
                outputURL: outputURL,
                colorSpaces: colorSpaces,
                options: options
            )
            
        case .sdr:
            return try await exportSDRImage(
                image: sdrImage,
                outputURL: outputURL,
                colorSpaces: colorSpaces,
                options: options
            )
            
        case .rgbGainMap:
            return try await exportRGBGainMap(
                hdrImage: hdrImage,
                sdrImage: sdrImage,
                outputURL: outputURL,
                colorSpaces: colorSpaces,
                options: options
            )
            
        case .appleType1:
            return try await exportAppleType1(
                hdrImage: hdrImage,
                sdrImage: sdrImage,
                picHeadroom: picHeadroom,
                outputURL: outputURL,
                colorSpaces: colorSpaces,
                options: options
            )
            
        case .appleType2:
            return try await exportAppleType2(
                hdrImage: hdrImage,
                sdrImage: sdrImage,
                outputURL: outputURL,
                colorSpaces: colorSpaces,
                options: options
            )
            
        case .adaptive:
            return try await exportAdaptive(
                hdrImage: hdrImage,
                sdrImage: sdrImage,
                outputURL: outputURL,
                colorSpaces: colorSpaces,
                options: options
            )
        }
    }
    
    private func exportHLGHDR(
        image: CIImage,
        outputURL: URL,
        colorSpaces: (sdr: CGColorSpace, hdr: CGColorSpace, hlg: CGColorSpace),
        options: ConversionOptions
    ) async throws -> ConversionResult {
        
        let exportOptions: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): options.imageQuality
        ]
        
        do {
            if options.colorDepth == .eightBit {
                try ctx.writeHEIFRepresentation(of: image,
                                              to: outputURL,
                                              format: .RGBA8,
                                              colorSpace: colorSpaces.hlg,
                                              options: exportOptions)
            } else {
                try ctx.writeHEIF10Representation(of: image,
                                                to: outputURL,
                                                colorSpace: colorSpaces.hlg,
                                                options: exportOptions)
            }
            return .success(outputURL)
        } catch {
            return .failure(.exportFailed(error.localizedDescription))
        }
    }
    
    private func exportPQHDR(
        image: CIImage,
        outputURL: URL,
        colorSpaces: (sdr: CGColorSpace, hdr: CGColorSpace, hlg: CGColorSpace),
        options: ConversionOptions
    ) async throws -> ConversionResult {
        
        let exportOptions: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): options.imageQuality
        ]
        
        do {
            try ctx.writeHEIF10Representation(of: image,
                                            to: outputURL,
                                            colorSpace: colorSpaces.hdr,
                                            options: exportOptions)
            return .success(outputURL)
        } catch {
            return .failure(.exportFailed(error.localizedDescription))
        }
    }
    
    private func exportRGBGainMap(
        hdrImage: CIImage,
        sdrImage: CIImage,
        outputURL: URL,
        colorSpaces: (sdr: CGColorSpace, hdr: CGColorSpace, hlg: CGColorSpace),
        options: ConversionOptions
    ) async throws -> ConversionResult {
        
        let exportOptions: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): options.imageQuality,
            .hdrImage: hdrImage,
            .hdrGainMapAsRGB: true
        ]
        
        do {
            if options.fileFormat == .jpeg {
                try ctx.writeJPEGRepresentation(of: sdrImage,
                                              to: outputURL,
                                              colorSpace: colorSpaces.sdr,
                                              options: exportOptions)
            } else {
                if options.colorDepth == .tenBit {
                    try ctx.writeHEIF10Representation(of: sdrImage,
                                                    to: outputURL,
                                                    colorSpace: colorSpaces.sdr,
                                                    options: exportOptions)
                } else {
                    try ctx.writeHEIFRepresentation(of: sdrImage,
                                                  to: outputURL,
                                                  format: .RGBA8,
                                                  colorSpace: colorSpaces.sdr,
                                                  options: exportOptions)
                }
            }
            return .success(outputURL)
        } catch {
            return .failure(.exportFailed(error.localizedDescription))
        }
    }
    
    private func exportAdaptive(
        hdrImage: CIImage,
        sdrImage: CIImage,
        outputURL: URL,
        colorSpaces: (sdr: CGColorSpace, hdr: CGColorSpace, hlg: CGColorSpace),
        options: ConversionOptions
    ) async throws -> ConversionResult {
        
        let exportOptions: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): options.imageQuality,
            .hdrImage: hdrImage,
            .hdrGainMapAsRGB: false
        ]
        
        do {
            if options.fileFormat == .jpeg {
                try ctx.writeJPEGRepresentation(of: sdrImage,
                                              to: outputURL,
                                              colorSpace: colorSpaces.sdr,
                                              options: exportOptions)
            } else {
                if options.colorDepth == .tenBit {
                    try ctx.writeHEIF10Representation(of: sdrImage,
                                                    to: outputURL,
                                                    colorSpace: colorSpaces.sdr,
                                                    options: exportOptions)
                } else {
                    try ctx.writeHEIFRepresentation(of: sdrImage,
                                                  to: outputURL,
                                                  format: .RGBA8,
                                                  colorSpace: colorSpaces.sdr,
                                                  options: exportOptions)
                }
            }
            return .success(outputURL)
        } catch {
            return .failure(.exportFailed(error.localizedDescription))
        }
    }
    
    private func exportAppleType1(
        hdrImage: CIImage,
        sdrImage: CIImage,
        picHeadroom: Float,
        outputURL: URL,
        colorSpaces: (sdr: CGColorSpace, hdr: CGColorSpace, hlg: CGColorSpace),
        options: ConversionOptions
    ) async throws -> ConversionResult {
        
        do {
            // 使用自定义滤镜生成增益图
            var gainMap = try getGainMap(hdrInput: hdrImage, sdrInput: sdrImage, hdrMax: picHeadroom)
            
            if options.isHalfSize {
                gainMap = resizeCIImageByHalf(originalImage: gainMap, scalingRatio: options.scalingRatio)
            }
            
            // 准备 SDR 图像数据（匹配命令行版本）
            let sdrImageData: Data
            if options.colorDepth == .tenBit {
                sdrImageData = ctx.tiffRepresentation(of: sdrImage,
                                                    format: .RGB10,
                                                    colorSpace: colorSpaces.sdr)!
            } else {
                sdrImageData = ctx.tiffRepresentation(of: sdrImage,
                                                    format: .RGBA8,
                                                    colorSpace: colorSpaces.sdr)!
            }
            
            let processedSDRImage = CIImage(data: sdrImageData,
                                          options: [.toneMapHDRtoSDR: true])!
            
            // 设置 Apple 属性（完全匹配命令行版本的逻辑）
            let stops = log2(picHeadroom)
            var imageProperties = hdrImage.properties
            var makerApple = imageProperties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any] ?? [:]
            
            switch stops {
            case let x where x >= 2.303:
                makerApple["33"] = 1.0
                makerApple["48"] = (3.0 - stops)/70.0
            case 1.8..<3:
                makerApple["33"] = 1.0
                makerApple["48"] = (2.303 - stops)/0.303
            case 1.6..<1.8:
                makerApple["33"] = 0.0
                makerApple["48"] = (1.80 - stops)/20.0
            default:
                makerApple["33"] = 0.0
                makerApple["48"] = (1.601 - stops)/0.101
            }
            
            imageProperties[kCGImagePropertyMakerAppleDictionary as String] = makerApple
            let modifiedImage = processedSDRImage.settingProperties(imageProperties)
            
            let exportOptions: [CIImageRepresentationOption: Any] = [
                CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): options.imageQuality,
                .hdrGainMapImage: gainMap
            ]
            
            if options.fileFormat == .jpeg {
                try ctx.writeJPEGRepresentation(of: modifiedImage,
                                              to: outputURL,
                                              colorSpace: colorSpaces.sdr,
                                              options: exportOptions)
            } else {
                if options.colorDepth == .tenBit {
                    try ctx.writeHEIF10Representation(of: modifiedImage,
                                                    to: outputURL,
                                                    colorSpace: colorSpaces.sdr,
                                                    options: exportOptions)
                } else {
                    try ctx.writeHEIFRepresentation(of: modifiedImage,
                                                  to: outputURL,
                                                  format: .RGBA8,
                                                  colorSpace: colorSpaces.sdr,
                                                  options: exportOptions)
                }
            }
            
            return .success(outputURL)
        } catch {
            return .failure(.exportFailed(error.localizedDescription))
        }
    }
    
    private func exportAppleType2(
        hdrImage: CIImage,
        sdrImage: CIImage,
        outputURL: URL,
        colorSpaces: (sdr: CGColorSpace, hdr: CGColorSpace, hlg: CGColorSpace),
        options: ConversionOptions
    ) async throws -> ConversionResult {
        
        do {
            // 生成临时增益图（完全匹配命令行版本的实现）
            let tmpExportOptions: [CIImageRepresentationOption: Any] = [
                .hdrImage: hdrImage,
                .hdrGainMapAsRGB: false
            ]
            
            let tmpHeicData = ctx.heifRepresentation(of: sdrImage,
                                                   format: .RGBA8,
                                                   colorSpace: colorSpaces.sdr,
                                                   options: tmpExportOptions)!
            
            var tmpGainMapData = CIImage(data: tmpHeicData,
                                       options: [CIImageOption(rawValue: "kCIImageAuxiliaryHDRGainMap"): true])!
            
            if options.isHalfSize {
                tmpGainMapData = resizeCIImageByHalf(originalImage: tmpGainMapData,
                                                   scalingRatio: options.scalingRatio)
            }
            
            // 设置 Apple 属性（匹配命令行版本的固定值）
            var imageProperties = hdrImage.properties
            var makerApple = imageProperties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any] ?? [:]
            
            makerApple["33"] = 1.01
            makerApple["48"] = 0.009986
            imageProperties[kCGImagePropertyMakerAppleDictionary as String] = makerApple
            
            let modifiedImage = sdrImage.settingProperties(imageProperties)
            
            let appleExportOptions: [CIImageRepresentationOption: Any] = [
                CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): options.imageQuality,
                .hdrGainMapImage: tmpGainMapData
            ]
            
            if options.fileFormat == .jpeg {
                try ctx.writeJPEGRepresentation(of: modifiedImage,
                                              to: outputURL,
                                              colorSpace: colorSpaces.sdr,
                                              options: appleExportOptions)
            } else {
                if options.colorDepth == .tenBit {
                    try ctx.writeHEIF10Representation(of: modifiedImage,
                                                    to: outputURL,
                                                    colorSpace: colorSpaces.sdr,
                                                    options: appleExportOptions)
                } else {
                    try ctx.writeHEIFRepresentation(of: modifiedImage,
                                                  to: outputURL,
                                                  format: .RGBA8,
                                                  colorSpace: colorSpaces.sdr,
                                                  options: appleExportOptions)
                }
            }
            
            return .success(outputURL)
        } catch {
            return .failure(.exportFailed(error.localizedDescription))
        }
    }
    
    // MARK: - Utility Functions
    
    private func getGainMap(hdrInput: CIImage, sdrInput: CIImage, hdrMax: Float) throws -> CIImage {
        let filter = GainMapFilter()
        filter.HDRImage = hdrInput
        filter.SDRImage = sdrInput
        filter.hdrmax = hdrMax
        
        guard let outputImage = filter.outputImage else {
            throw ConversionError.processingFailed("无法生成增益图")
        }
        
        return outputImage
    }
    
    private func resizeCIImageByHalf(originalImage: CIImage, scalingRatio: Float) -> CIImage {
        let lanczosScaleFilter = CIFilter.lanczosScaleTransform()
        lanczosScaleFilter.inputImage = originalImage
        lanczosScaleFilter.scale = 1.0 / scalingRatio
        lanczosScaleFilter.aspectRatio = 1
        return lanczosScaleFilter.outputImage!
    }
    
    // MARK: - File Name Generation
    
    func generateOutputFileName(from inputURL: URL, options: ConversionOptions) -> String {
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let additionalText = options.additionalText.isEmpty ? "" : options.additionalText
        let fileExtension = options.fileFormat == .jpeg ? "jpg" : "heic"
        
        // 如果有附加文本，添加到文件名中
        if !additionalText.isEmpty {
            return "\(baseName)\(additionalText).\(fileExtension)"
        } else {
            return "\(baseName).\(fileExtension)"
        }
    }
}

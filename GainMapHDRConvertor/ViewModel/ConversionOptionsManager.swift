//
//  ConversionOptionsManager.swift
//  GainMapHDRConvertor
//
//  Created by Hongyu Shi on 2025/9/25.
//

import Foundation
import SwiftUI
import Combine

class ConversionOptionsManager: ObservableObject {
    @Published var options = ConversionOptions()
    
    // 计算属性
    var validationMessage: String? {
        let validation = options.isValid
        return validation.0 ? nil : validation.1
    }
    
    var baseImageFileName: String {
        return options.baseImageURL?.lastPathComponent ?? "未选择基础图像"
    }
    
    // 文件格式约束检查
    var availableExportFormats: [ExportFormat] {
        if options.fileFormat == .jpeg {
            // JPEG不支持HLG和PQ HDR
            return [.adaptive, .rgbGainMap, .appleType1, .appleType2, .sdr]
        }
        return ExportFormat.allCases
    }
    
    // 色彩深度控件状态
    var isColorDepthDisabled: Bool {
        return options.fileFormat == .jpeg || options.exportFormat == .pqHDR
    }
    
    var colorDepthDisableReason: String {
        if options.fileFormat == .jpeg {
            return "JPEG 格式强制使用 8 位"
        } else if options.exportFormat == .pqHDR {
            return "PQ HDR 强制使用 10 位"
        }
        return ""
    }
    
    // 色调映射比例控件状态
    var isToneMappingDisabled: Bool {
        switch options.exportFormat {
        case .rgbGainMap:
            return options.baseImageURL != nil // 指定基础图像时禁用
        case .hlgHDR, .pqHDR:
            return true // HDR导出时禁用
        default:
            return false
        }
    }
    
    var toneMappingDisableReason: String {
        if options.exportFormat == .rgbGainMap && options.baseImageURL != nil {
            return "指定了基础图像，色调映射不适用"
        } else if options.exportFormat == .hlgHDR || options.exportFormat == .pqHDR {
            return "HDR 导出时色调映射不适用"
        }
        return ""
    }
    
    // 增益图缩放控件状态
    var isScalingDisabled: Bool {
        return options.exportFormat != .appleType1 && options.exportFormat != .appleType2
    }
    
    var scalingDisableReason: String {
        return "只有 Apple 增益图格式支持缩放"
    }
    
    // 应用约束条件
    func applyConstraints() {
        options.applyConstraints()
    }
    
    // 重置到默认值
    func reset() {
        options = ConversionOptions()
    }
}
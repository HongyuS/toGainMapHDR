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
    var warnings: [String] {
        return options.warnings
    }
    
    var validationMessage: String? {
        let validation = options.isValid
        return validation.0 ? nil : validation.1
    }
    
    var baseImageFileName: String {
        return options.baseImageURL?.lastPathComponent ?? "未选择基础图像"
    }
    
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
    
    // 应用约束条件
    func applyConstraints() {
        options.applyConstraints()
    }
    
    // 重置到默认值
    func reset() {
        options = ConversionOptions()
    }
}
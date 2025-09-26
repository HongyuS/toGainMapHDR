//
//  ParameterConfigView.swift
//  GainMapHDRConvertor
//
//  Created by Hongyu Shi on 2025/9/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ParameterConfigView: View {
    @ObservedObject var conversionOptions: ConversionOptionsManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 参数配置区域
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // 常规参数
                    RegularParametersSection(conversionOptions: conversionOptions)
                    
                    // 高级参数
                    AdvancedParametersSection(conversionOptions: conversionOptions)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            
            // 底栏
            HStack {
                Spacer()
                
                if #available(macOS 26.0, *) {
                    Button("重置", systemImage: "arrow.counterclockwise") {
                        conversionOptions.reset()
                    }
                    .buttonStyle(.glass)
                } else {
                    // Fallback on earlier versions
                    Button("重置", systemImage: "arrow.counterclockwise") {
                        conversionOptions.reset()
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onChange(of: conversionOptions.options) { _, _ in
            conversionOptions.applyConstraints()
        }
    }
}

// MARK: - 常规参数区域
struct RegularParametersSection: View {
    @ObservedObject var conversionOptions: ConversionOptionsManager
    
    var body: some View {
        GroupBox("常规参数") {
            VStack(alignment: .leading, spacing: 24) {
                // 导出格式
                VStack(alignment: .leading, spacing: 12) {
                    Text("导出格式")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker("格式", selection: $conversionOptions.options.exportFormat) {
                        ForEach(conversionOptions.availableExportFormats, id: \.self) { format in
                            Text(exportFormatDisplayName(format)).tag(format)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    Text(exportFormatDescription(conversionOptions.options.exportFormat))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 基础图像选择（仅在RGB增益图模式下显示）
                if conversionOptions.options.exportFormat == .rgbGainMap {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("基础图像")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        BaseImageSelector(conversionOptions: conversionOptions)
                        
                        Text("为RGB增益图指定特定的基础图像（可选）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 文件格式设置
                VStack(alignment: .leading, spacing: 15) {
                    Text("文件设置")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    // 文件格式
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("文件格式", selection: $conversionOptions.options.fileFormat) {
                            Text("HEIC").tag(FileFormat.heic)
                            Text("JPEG").tag(FileFormat.jpeg)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    // 色彩深度
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("色彩深度", selection: $conversionOptions.options.colorDepth) {
                            Text("8位").tag(ColorDepth.eightBit)
                            Text("10位").tag(ColorDepth.tenBit)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .disabled(conversionOptions.isColorDepthDisabled)
                        
                        if conversionOptions.isColorDepthDisabled {
                            Text(conversionOptions.colorDepthDisableReason)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // 图像质量
                    VStack(alignment: .leading, spacing: 8) {
                        Text("图像质量: \(String(format: "%.0f%%", conversionOptions.options.imageQuality * 100))")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Slider(value: $conversionOptions.options.imageQuality, in: 0.1...1.0, step: 0.01) {
                            Text("质量")
                        } minimumValueLabel: {
                            Text("10%").font(.caption)
                        } maximumValueLabel: {
                            Text("100%").font(.caption)
                        }
                    }
                }
                
                // 色彩空间
                VStack(alignment: .leading, spacing: 8) {
                    Picker("色彩空间", selection: $conversionOptions.options.colorSpace) {
                        Text("自动检测").tag(ColorSpace.auto)
                        Text("sRGB").tag(ColorSpace.srgb)
                        Text("Display P3").tag(ColorSpace.p3)
                        Text("Rec.2020").tag(ColorSpace.rec2020)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            .padding(5)
        }
    }
    
    private func exportFormatDisplayName(_ format: ExportFormat) -> String {
        switch format {
        case .adaptive:
            return "自适应增益图"
        case .rgbGainMap:
            return "RGB 增益图"
        case .appleType1:
            return "Apple 增益图 (CIFilter)"
        case .appleType2:
            return "Apple 增益图 (ISO)"
        case .sdr:
            return "SDR 图像"
        case .pqHDR:
            return "PQ HDR 图像"
        case .hlgHDR:
            return "HLG HDR 图像"
        }
    }
    
    private func exportFormatDescription(_ format: ExportFormat) -> String {
        switch format {
        case .adaptive:
            return "自适应增益图 (默认，ISO 标准)"
        case .rgbGainMap:
            return "RGB 增益图 (需要指定基础图像)"
        case .appleType1:
            return "Apple 增益图 (使用 CIFilter 生成)"
        case .appleType2:
            return "Apple 增益图 (从 ISO 增益图转换)"
        case .sdr:
            return "SDR 图像 (无 HDR 增益图)"
        case .pqHDR:
            return "PQ HDR 图像 (强制10位)"
        case .hlgHDR:
            return "HLG HDR 图像"
        }
    }
}

// MARK: - 高级参数区域
struct AdvancedParametersSection: View {
    @ObservedObject var conversionOptions: ConversionOptionsManager
    
    var body: some View {
        GroupBox("高级参数") {
            VStack(alignment: .leading, spacing: 15) {
                // 色调映射比例
                VStack(alignment: .leading, spacing: 8) {
                    Text("色调映射比例: \(String(format: "%.2f", conversionOptions.options.toneMappingRatio))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(conversionOptions.isToneMappingDisabled ? .secondary : .primary)
                    
                    Slider(value: Binding(
                        get: { Double(conversionOptions.options.toneMappingRatio) },
                        set: { conversionOptions.options.toneMappingRatio = Float($0) }
                    ), in: 0.0...1.0, step: 0.01) {
                        Text("色调映射")
                    } minimumValueLabel: {
                        Text("0").font(.caption)
                    } maximumValueLabel: {
                        Text("1").font(.caption)
                    }
                    .disabled(conversionOptions.isToneMappingDisabled)
                    
                    if conversionOptions.isToneMappingDisabled {
                        Text(conversionOptions.toneMappingDisableReason)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("0: 保留完整高光细节, 1: 硬截取SDR范围外部分")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 增益图缩放（仅Apple格式）
                if conversionOptions.options.exportFormat == .appleType1 || conversionOptions.options.exportFormat == .appleType2 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("增益图缩放: \(String(format: "%.1fx", conversionOptions.options.scalingRatio))")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(conversionOptions.isScalingDisabled ? .secondary : .primary)
                        
                        Slider(value: Binding(
                            get: { Double(conversionOptions.options.scalingRatio) },
                            set: { conversionOptions.options.scalingRatio = Float($0) }
                        ), in: 1.0...2.0, step: 0.1) {
                            Text("缩放")
                        } minimumValueLabel: {
                            Text("1.0x").font(.caption)
                        } maximumValueLabel: {
                            Text("2.0x").font(.caption)
                        }
                        .disabled(conversionOptions.isScalingDisabled)
                        
                        if conversionOptions.isScalingDisabled {
                            Text(conversionOptions.scalingDisableReason)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("1.0: 完整尺寸, 2.0: 半尺寸增益图")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // 附加文件名
                VStack(alignment: .leading, spacing: 8) {
                    Text("附加文件名:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("可选的文件名后缀", text: $conversionOptions.options.additionalText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
            .padding(5)
        }
    }
}

// MARK: - 基础图像选择器
struct BaseImageSelector: View {
    @ObservedObject var conversionOptions: ConversionOptionsManager
    @State private var showingFileImporter = false
    
    var body: some View {
        HStack {
            Text(conversionOptions.baseImageFileName)
                .foregroundColor(.secondary)
                .truncationMode(.middle)
            
            Spacer()
            
            Button("选择基础图像") {
                showingFileImporter = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: UTType.allHDRImageFormats,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                conversionOptions.options.baseImageURL = urls.first
            case .failure(let error):
                print("基础图像选择失败: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    ParameterConfigView(
        conversionOptions: ConversionOptionsManager()
    )
    .frame(width: 400, height: 600)
}

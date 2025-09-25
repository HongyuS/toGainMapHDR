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
    let selectedFile: FileItem?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("转换参数")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button("重置") {
                    conversionOptions.reset()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(.controlBackgroundColor))
            
            Divider()
            
            // 参数配置区域
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 当前文件信息
                    if let file = selectedFile {
                        CurrentFileInfoSection(file: file)
                    } else {
                        NoFileSelectedSection()
                    }
                    
                    Divider()
                    
                    // 导出格式
                    ExportFormatSection(conversionOptions: conversionOptions)
                    
                    // 基础图像选择（仅在RGB增益图模式下显示）
                    if conversionOptions.options.exportFormat == .rgbGainMap {
                        BaseImageSection(conversionOptions: conversionOptions)
                    }
                    
                    // 文件设置
                    FileSettingsSection(conversionOptions: conversionOptions)
                    
                    // 色彩空间
                    ColorSpaceSection(conversionOptions: conversionOptions, selectedFile: selectedFile)
                    
                    // 高级选项
                    AdvancedOptionsSection(conversionOptions: conversionOptions)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            
            // 底部警告信息
            if !conversionOptions.warnings.isEmpty {
                Divider()
                WarningsSection(warnings: conversionOptions.warnings)
            }
        }
        .onChange(of: conversionOptions.options) { _, _ in
            conversionOptions.applyConstraints()
        }
    }
}

// MARK: - 当前文件信息区域
struct CurrentFileInfoSection: View {
    @ObservedObject var file: FileItem
    
    var body: some View {
        GroupBox("当前文件") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(file.fileName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // 状态指示器
                    switch file.imageLoadingStatus {
                    case .loading:
                        ProgressView()
                            .scaleEffect(0.8)
                    case .loaded:
                        if file.isHDRImage {
                            Text("HDR")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                    case .failed:
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                }
                
                HStack {
                    Text(file.imageInfo)
                        .font(.subheadline)
                        .foregroundColor(file.imageLoadingStatus == .loading ? .secondary : 
                                        file.imageLoadingStatus == .failed ? .red : .secondary)
                    
                    if file.imageLoadingStatus == .loading {
                        Spacer()
                        Text("请稍等...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 只有在加载完成且不是HDR时才显示警告
                if file.imageLoadingStatus == .loaded && !file.isHDRImage {
                    Text("⚠️ 这可能不是HDR图像")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                // 显示错误信息
                if file.imageLoadingStatus == .failed, let errorMessage = file.errorMessage {
                    Text("❌ \(errorMessage)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }
}

// MARK: - 无文件选中区域
struct NoFileSelectedSection: View {
    var body: some View {
        GroupBox("当前文件") {
            VStack(spacing: 12) {
                Image(systemName: "doc.questionmark")
                    .font(.system(size: 32, weight: .ultraLight))
                    .foregroundColor(.secondary)
                
                Text("请在左侧列表中选择一个文件")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
        }
    }
}

// MARK: - 导出格式区域
struct ExportFormatSection: View {
    @ObservedObject var conversionOptions: ConversionOptionsManager
    
    var body: some View {
        GroupBox("导出格式") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("格式", selection: $conversionOptions.options.exportFormat) {
                    Text("自适应增益图 (默认)").tag(ExportFormat.adaptive)
                    Text("RGB增益图 (需要基础图像)").tag(ExportFormat.rgbGainMap)
                    Text("Apple增益图 (CIFilter生成)").tag(ExportFormat.appleType1)
                    Text("Apple增益图 (ISO转换)").tag(ExportFormat.appleType2)
                    Text("SDR图像").tag(ExportFormat.sdr)
                    Text("PQ HDR图像").tag(ExportFormat.pqHDR)
                    Text("HLG HDR图像").tag(ExportFormat.hlgHDR)
                }
                .pickerStyle(MenuPickerStyle())
                
                Text(exportFormatDescription(conversionOptions.options.exportFormat))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func exportFormatDescription(_ format: ExportFormat) -> String {
        switch format {
        case .adaptive:
            return "自适应增益图 (默认，ISO标准)"
        case .rgbGainMap:
            return "RGB增益图 (需要指定基础图像)"
        case .appleType1:
            return "Apple增益图 (使用CIFilter生成)"
        case .appleType2:
            return "Apple增益图 (从ISO增益图转换)"
        case .sdr:
            return "SDR图像 (无HDR增益图)"
        case .pqHDR:
            return "PQ HDR图像 (强制10位)"
        case .hlgHDR:
            return "HLG HDR图像"
        }
    }
}

// MARK: - 基础图像区域
struct BaseImageSection: View {
    @ObservedObject var conversionOptions: ConversionOptionsManager
    @State private var showingFileImporter = false
    
    var body: some View {
        GroupBox("基础图像") {
            VStack(alignment: .leading, spacing: 8) {
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
                
                Text("为RGB增益图指定特定的基础图像（可选）")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.heic, .jpeg, .png, .tiff],
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

// MARK: - 文件设置区域
struct FileSettingsSection: View {
    @ObservedObject var conversionOptions: ConversionOptionsManager
    
    var body: some View {
        GroupBox("文件设置") {
            VStack(alignment: .leading, spacing: 15) {
                // 文件格式
                VStack(alignment: .leading, spacing: 8) {
                    Text("文件格式:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker("", selection: $conversionOptions.options.fileFormat) {
                        Text("HEIC").tag(FileFormat.heic)
                        Text("JPEG").tag(FileFormat.jpeg)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                // 色彩深度
                VStack(alignment: .leading, spacing: 8) {
                    Text("色彩深度:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker("", selection: $conversionOptions.options.colorDepth) {
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
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Slider(value: $conversionOptions.options.imageQuality, in: 0.1...1.0, step: 0.05) {
                        Text("质量")
                    } minimumValueLabel: {
                        Text("10%").font(.caption)
                    } maximumValueLabel: {
                        Text("100%").font(.caption)
                    }
                }
            }
        }
    }
}

// MARK: - 色彩空间区域
struct ColorSpaceSection: View {
    @ObservedObject var conversionOptions: ConversionOptionsManager
    let selectedFile: FileItem?
    
    var body: some View {
        GroupBox("色彩空间") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("色彩空间", selection: $conversionOptions.options.colorSpace) {
                    Text("自动检测").tag(ColorSpace.auto)
                    Text("sRGB / Rec.709").tag(ColorSpace.srgb)
                    Text("Display P3").tag(ColorSpace.p3)
                    Text("Rec.2020").tag(ColorSpace.rec2020)
                }
                .pickerStyle(SegmentedPickerStyle())
                
                if let file = selectedFile, file.imageLoadingStatus == .loaded {
                    Text("检测到的色彩空间: \(file.detectedColorSpace.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let file = selectedFile, file.imageLoadingStatus == .loading {
                    Text("正在检测色彩空间...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("将根据输入图像自动检测")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - 高级选项区域
struct AdvancedOptionsSection: View {
    @ObservedObject var conversionOptions: ConversionOptionsManager
    
    var body: some View {
        GroupBox("高级选项") {
            VStack(alignment: .leading, spacing: 15) {
                // 色调映射比例
                VStack(alignment: .leading, spacing: 8) {
                    Text("色调映射比例: \(String(format: "%.2f", conversionOptions.options.toneMappingRatio))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
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
                    
                    Text("0: 保留完整高光细节, 1: 硬截取SDR范围外部分")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 增益图缩放（仅Apple格式）
                if conversionOptions.options.exportFormat == .appleType1 || conversionOptions.options.exportFormat == .appleType2 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("增益图缩放: \(String(format: "%.1fx", conversionOptions.options.scalingRatio))")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
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
                        
                        Text("1.0: 完整尺寸, 2.0: 半尺寸增益图")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 附加文件名
                VStack(alignment: .leading, spacing: 8) {
                    Text("附加文件名:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("可选的文件名后缀", text: $conversionOptions.options.additionalText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Text("将添加到输出文件名中")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - 警告区域
struct WarningsSection: View {
    let warnings: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                Text("注意事项")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
                Spacer()
            }
            
            ForEach(warnings, id: \.self) { warning in
                Text("• \(warning)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.1))
    }
}

#Preview {
    ParameterConfigView(
        conversionOptions: ConversionOptionsManager(),
        selectedFile: nil
    )
    .frame(width: 400, height: 600)
}
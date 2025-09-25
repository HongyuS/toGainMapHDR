//
//  ConvertorViewModel.swift
//  GainMapHDRConvertor
//
//  Created by Hongyu Shi on 2025/9/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class ConvertorViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = "准备就绪"
    
    private let convertor = Convertor()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        convertor.$isProcessing
            .receive(on: DispatchQueue.main)
            .assign(to: \.isProcessing, on: self)
            .store(in: &cancellables)
        
        convertor.$progress
            .receive(on: DispatchQueue.main)
            .assign(to: \.progress, on: self)
            .store(in: &cancellables)
    }
    
    func convertSingleFile(_ fileItem: FileItem, outputDirectory: URL, options: ConversionOptions) async {
        guard !isProcessing else { return }
        
        isProcessing = true
        fileItem.progress = 0.3
        
        do {
            let validation = options.isValid
            guard validation.0 else {
                throw ConversionError.invalidParameters(validation.1!)
            }
            
            let outputFilename = convertor.generateOutputFileName(from: fileItem.url, options: options)
            let outputURL = outputDirectory.appendingPathComponent(outputFilename)
            
            let tempURL = try createTempCopy(of: fileItem.url)
            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }
            
            let result = await convertor.convertHDRImage(
                inputURL: tempURL,
                outputURL: outputURL,
                options: options
            )
            
            switch result {
            case .success(let url):
                fileItem.status = .completed
                fileItem.outputURL = url
                fileItem.progress = 1.0
                statusMessage = "转换完成: \(fileItem.fileName)"
            case .failure(let error):
                fileItem.status = .failed
                fileItem.progress = 0.0
                statusMessage = "转换失败: \(error.localizedDescription)"
            }
        } catch {
            fileItem.status = .failed
            fileItem.progress = 0.0
            statusMessage = "转换出错: \(error.localizedDescription)"
        }
        
        isProcessing = false
        progress = 0.0
    }
    
    func batchConvertFiles(_ fileItems: [FileItem], outputDirectory: URL, options: ConversionOptions) async {
        guard !fileItems.isEmpty else { return }
        
        isProcessing = true
        var failureCount = 0
        
        for (index, fileItem) in fileItems.enumerated() {
            progress = Double(index) / Double(fileItems.count)
            
            do {
                let validation = options.isValid
                guard validation.0 else {
                    throw ConversionError.invalidParameters(validation.1!)
                }
                
                let outputFilename = convertor.generateOutputFileName(from: fileItem.url, options: options)
                let outputURL = outputDirectory.appendingPathComponent(outputFilename)
                
                fileItem.progress = 0.3
                
                let tempURL = try createTempCopy(of: fileItem.url)
                defer {
                    try? FileManager.default.removeItem(at: tempURL)
                }
                
                let result = await convertor.convertHDRImage(
                    inputURL: tempURL,
                    outputURL: outputURL,
                    options: options
                )
                
                switch result {
                case .success(let url):
                    fileItem.status = .completed
                    fileItem.outputURL = url
                    fileItem.progress = 1.0
                case .failure(let error):
                    fileItem.status = .failed
                    fileItem.progress = 0.0
                    failureCount += 1
                    print("转换失败: \(error.localizedDescription)")
                }
            } catch {
                fileItem.status = .failed
                fileItem.progress = 0.0
                failureCount += 1
                print("转换出错: \(error.localizedDescription)")
            }
        }
        
        let successCount = fileItems.filter { $0.status == .completed }.count
        statusMessage = "批量转换完成! 成功: \(successCount), 失败: \(failureCount)"
        
        if successCount > 0 {
            NSWorkspace.shared.open(outputDirectory)
        }
        
        isProcessing = false
        progress = 0.0
    }
    
    private func createTempCopy(of sourceURL: URL) throws -> URL {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        let tempURL = tempDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(sourceURL.pathExtension)
        try FileManager.default.copyItem(at: sourceURL, to: tempURL)
        return tempURL
    }
}
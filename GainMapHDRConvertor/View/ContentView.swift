//
//  ContentView.swift
//  GainMapHDRConvertor
//
//  Created by Hongyu Shi on 2025/9/25.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @StateObject private var fileCollection = FileItemCollection()
    @StateObject private var conversionOptions = ConversionOptionsManager()
    @StateObject private var viewModel = ConvertorViewModel()
    
    @State private var showingFilePicker = false
    @State private var showingBatchFilePicker = false
    @State private var isConverting = false
    
    var body: some View {
        NavigationSplitView {
            // 左侧：文件列表
            FileListView(fileCollection: fileCollection)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } detail: {
            // 右侧：参数配置
            ParameterConfigView(
                conversionOptions: conversionOptions,
                selectedFile: fileCollection.selectedItem
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("转换当前文件") {
                    convertSelectedFile()
                }
                .disabled(fileCollection.selectedItem == nil || isConverting)
                
                Button("批量转换") {
                    convertAllFiles()
                }
                .disabled(!fileCollection.hasItems || isConverting)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.heic, .jpeg, .png, .tiff],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDroppedFiles(providers)
            return true
        }
    }
    
    // MARK: - File Operations
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            fileCollection.addFiles(from: urls)
        case .failure(let error):
            print("文件选择失败: \(error.localizedDescription)")
        }
    }
    
    private func handleDroppedFiles(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                defer { group.leave() }
                
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }
        
        group.notify(queue: .main) {
            if !urls.isEmpty {
                fileCollection.addFiles(from: urls)
            }
        }
    }
    
    // MARK: - Conversion Operations
    
    private func convertSelectedFile() {
        guard let selectedFile = fileCollection.selectedItem else { return }
        
        // 选择输出文件夹
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择输出文件夹"
        
        if panel.runModal() == .OK, let outputURL = panel.url {
            isConverting = true
            Task {
                await viewModel.convertSingleFile(
                    selectedFile,
                    outputDirectory: outputURL,
                    options: conversionOptions.options
                )
                await MainActor.run {
                    isConverting = false
                }
            }
        }
    }
    
    private func convertAllFiles() {
        guard fileCollection.hasItems else { return }
        
        // 选择输出文件夹
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择输出文件夹"
        
        if panel.runModal() == .OK, let outputURL = panel.url {
            isConverting = true
            Task {
                await viewModel.batchConvertFiles(
                    fileCollection.items,
                    outputDirectory: outputURL,
                    options: conversionOptions.options
                )
                await MainActor.run {
                    isConverting = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1200, height: 800)
}

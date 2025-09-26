//
//  FileListView.swift
//  GainMapHDRConvertor
//
//  Created by Hongyu Shi on 2025/9/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct FileListView: View {
    @ObservedObject var fileCollection: FileItemCollection
    @State private var showingFileImporter = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 文件列表
            if fileCollection.hasItems {
                List(fileCollection.items, id: \.id, selection: Binding(
                    get: { fileCollection.selectedItem?.id },
                    set: { selectedId in
                        if let selectedId = selectedId,
                           let item = fileCollection.items.first(where: { $0.id == selectedId }) {
                            DispatchQueue.main.async {
                                fileCollection.selectItem(item)
                            }
                        }
                    }
                )) { item in
                    FileRowView(item: item)
                        .contextMenu {
                            FileContextMenu(item: item, fileCollection: fileCollection)
                        }
                }
                .listStyle(.sidebar)
            } else {
                // 空状态
                EmptyStateView(onAddFiles: {
                    showingFileImporter = true
                })
            }
            
            // 底部工具栏
            HStack {
                if #available(macOS 26.0, *) {
                    Button("添加文件", systemImage: "plus") {
                        showingFileImporter = true
                    }
                    .buttonStyle(.glass)
                } else {
                    // Fallback on earlier versions
                    Button("添加文件", systemImage: "plus") {
                        showingFileImporter = true
                    }
                    .buttonStyle(.borderless)
                }
                
                Spacer()
                
                if fileCollection.hasItems {
                    if #available(macOS 26.0, *) {
                        Button("清空列表", systemImage: "trash") {
                            fileCollection.removeAll()
                        }
                        .buttonStyle(.glass)
                    } else {
                        // Fallback on earlier versions
                        Button("清空列表", systemImage: "trash") {
                            fileCollection.removeAll()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(minWidth: 300, idealWidth: 350)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: UTType.allHDRImageFormats,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                fileCollection.addFiles(from: urls)
            case .failure(let error):
                print("文件选择失败: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - 文件行视图
struct FileRowView: View {
    @ObservedObject var item: FileItem
    
    var body: some View {
        HStack(spacing: 12) {
            // 状态图标
            Image(systemName: item.status.iconName)
                .foregroundColor(item.status.color)
                .frame(width: 16, height: 16)
                .opacity(item.status == .processing ? 0.7 : 1.0)
                .scaleEffect(item.status == .processing ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: item.status == .processing)
            
            VStack(alignment: .leading, spacing: 4) {
                // 文件名
                Text(item.fileName)
                    .font(.system(.body, design: .default, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                // 文件信息
                HStack(spacing: 6) {
                    Text(item.fileSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(item.imageInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // HDR 标识和加载状态
                HStack(spacing: 4) {
                    if item.imageLoadingStatus == .loading {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("加载中")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if item.imageLoadingStatus == .loaded && item.isHDRImage {
                        Text("HDR")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    } else if item.imageLoadingStatus == .failed {
                        Text("加载失败")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.2))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }
                }
                
                // 错误信息
                if let errorMessage = item.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
                
                // 进度条
                if item.status == .processing && item.progress > 0 {
                    ProgressView(value: item.progress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .scaleEffect(0.8)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(.containerRelative)
    }
}

// MARK: - 文件上下文菜单
struct FileContextMenu: View {
    let item: FileItem
    let fileCollection: FileItemCollection
    
    var body: some View {
        Button("在 Finder 中显示") {
            NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: item.url.deletingLastPathComponent().path)
        }
        
        if item.status == .completed, let outputURL = item.outputURL {
            Button("显示输出文件") {
                NSWorkspace.shared.selectFile(outputURL.path, inFileViewerRootedAtPath: outputURL.deletingLastPathComponent().path)
            }
        }
        
        Divider()
        
        if item.status == .failed || item.status == .completed {
            Button("重置状态") {
                item.reset()
            }
        }
        
        Button("移除", role: .destructive) {
            fileCollection.removeItem(item)
        }
    }
}

// MARK: - 空状态视图
struct EmptyStateView: View {
    let onAddFiles: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("没有文件")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("点击下方按钮添加 HDR 图像文件")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("选择文件") {
                onAddFiles()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

#Preview {
    FileListView(fileCollection: FileItemCollection())
        .frame(width: 350, height: 500)
}

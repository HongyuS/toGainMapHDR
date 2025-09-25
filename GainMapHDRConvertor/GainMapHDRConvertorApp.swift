//
//  GainMapHDRConvertorApp.swift
//  GainMapHDRConvertor
//
//  Created by Hongyu Shi on 2025/9/25.
//

import SwiftUI

@main
struct GainMapHDRConvertorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加文件...") {
                    // 这里可以触发文件选择
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

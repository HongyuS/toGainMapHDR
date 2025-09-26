//
//  UTType+Extensions.swift
//  GainMapHDRConvertor
//
//  Created by Hongyu Shi on 2025/9/26.
//

import UniformTypeIdentifiers

extension UTType {
    /// AVIF格式
    static var avif: UTType {
        UTType(importedAs: "public.avif", conformingTo: .image)
    }
    
    /// Radiance HDR格式
    static var hdr: UTType {
        UTType(filenameExtension: "hdr", conformingTo: .image) ??
        UTType(importedAs: "public.radiance", conformingTo: .image)
    }
    
    /// 所有支持的HDR图像格式
    static var allHDRImageFormats: [UTType] {
        return [
            // 基本格式
            .heic, .jpeg, .png, .tiff, .jpegxl, .heif, .exr,
            // 扩展格式
            .avif, .hdr
        ]
    }
}

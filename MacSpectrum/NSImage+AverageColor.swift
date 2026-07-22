//
//  NSImage+AverageColor.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/6/8.
//

import AppKit

extension NSImage {
    /// 🚀 极客专属：直接从 NSImage 的硬件位图缓冲中秒算平均色
    var averageColor: NSColor? {
        // 1. 安全解包内部的 CGImage 句柄
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        // 2. 将其转换成 macOS 专用的位图表示对象
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        
        // 3. 拿到图片的真实物理像素宽高
        let pixelWidth = bitmapRep.pixelsWide
        let pixelHeight = bitmapRep.pixelsHigh
        
        guard pixelWidth > 0 && pixelHeight > 0 else { return nil }
        
        var totalR: Int = 0
        var totalG: Int = 0
        var totalB: Int = 0
        
        // 🎯 性能优化巧思：如果每张专辑图都全量扫描（比如几百万像素），M1 Pro 也会被白白浪费算力。
        // 咱们采取“十字交叉/步进采样法”，每隔 step 个像素抽样一次，结果几乎完全一致，速度提升上百倍！
        let step = max(1, pixelWidth / 50)
        var sampleCount = 0
        
        for y in stride(from: 0, to: pixelHeight, by: step) {
            for x in stride(from: 0, to: pixelWidth, by: step) {
                // 探测当前坐标的像素指针
                if let color = bitmapRep.colorAt(x: x, y: y) {
                    // 扣出 RGB 分量（0.0 ~ 1.0）
                    totalR += Int(color.redComponent * 255)
                    totalG += Int(color.greenComponent * 255)
                    totalB += Int(color.blueComponent * 255)
                    sampleCount += 1
                }
            }
        }
        
        guard sampleCount > 0 else { return nil }
        
        // 4. 算得平均值
        let avgR = CGFloat(totalR / sampleCount) / 255.0
        let avgG = CGFloat(totalG / sampleCount) / 255.0
        let avgB = CGFloat(totalB / sampleCount) / 255.0
        
        return NSColor(red: avgR, green: avgG, blue: avgB, alpha: 1.0)
    }
}

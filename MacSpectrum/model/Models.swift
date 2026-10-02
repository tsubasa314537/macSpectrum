//
//  Models.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/4/18.
//

import Foundation
import SwiftUI

struct Playlist: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    var songs: [Song]
}

struct Song: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
    let lyric: String
}

// MARK: - 颜色主题定义

struct SpectrumPalette {
    let name: String
    let low: Color   // 低频（中心侧：一般用饱满、稳重的主色）
    let high: Color  // 高频（外侧：用主色进行色相偏移或提亮，形成流光溢彩的动感）
    
    // ✨ 根据传入的专辑平均色，动态繁衍出一套完美的高低频渐变主题
    init(from averageColor: Color, name: String = "AlbumDynamic") {
        self.name = name
        self.low = averageColor // 中心侧采用纯正的专辑主色，作为能量大本营
        
#if os(macOS)
        let nsColor = NSColor(averageColor).usingColorSpace(.deviceRGB) ?? .white
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
#else
        let uiColor = UIColor(averageColor)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
#endif
        
        // 高频外侧：色相微调 +0.08，亮度拔高
        let newHue = (h + 0.08).truncatingRemainder(dividingBy: 1.0)
        self.high = Color(hue: Double(newHue), saturation: Double(s), brightness: min(Double(b) * 1.2, 1.0))
    }
    
    init(name: String, low: Color, high: Color) {
        self.name = name
        self.low = low
        self.high = high
    }
}

extension SpectrumPalette {
    static let all: [SpectrumPalette] = [
        // ── 🔴 红色 / 玫瑰色系 (0.00 ~ 0.06) ──
        SpectrumPalette(name: "Rose",       low: Color(hue: 0.98, saturation: 0.85, brightness: 1.0),
                        high: Color(hue: 0.03, saturation: 0.75, brightness: 1.0)),
        SpectrumPalette(name: "Magma",      low: Color(hue: 0.04, saturation: 1.00, brightness: 1.0),
                        high: Color(hue: 0.10, saturation: 0.90, brightness: 1.0)),
        
        // ── 橙色 / 金黄色系 (0.06 ~ 0.18) ──
        SpectrumPalette(name: "Sunset",     low: Color(hue: 0.08, saturation: 1.00, brightness: 1.0),
                        high: Color(hue: 0.15, saturation: 0.90, brightness: 1.0)),
        SpectrumPalette(name: "Amber",      low: Color(hue: 0.11, saturation: 0.95, brightness: 0.98),
                        high: Color(hue: 0.16, saturation: 0.80, brightness: 1.0)),
        SpectrumPalette(name: "Gold",       low: Color(hue: 0.13, saturation: 1.00, brightness: 0.92),
                        high: Color(hue: 0.18, saturation: 0.85, brightness: 1.0)),
        
        // ── 绿色 / 黄绿系 (0.18 ~ 0.42) ──
        SpectrumPalette(name: "Lime",       low: Color(hue: 0.22, saturation: 0.85, brightness: 0.95),
                        high: Color(hue: 0.30, saturation: 0.70, brightness: 1.0)),
        SpectrumPalette(name: "Emerald",    low: Color(hue: 0.35, saturation: 0.90, brightness: 0.90),
                        high: Color(hue: 0.42, saturation: 0.75, brightness: 1.0)),
        
        // ── 青色 / 蓝绿系 (0.42 ~ 0.58) ──
        SpectrumPalette(name: "Mint",       low: Color(hue: 0.45, saturation: 0.75, brightness: 0.92),
                        high: Color(hue: 0.33, saturation: 0.65, brightness: 1.0)),
        SpectrumPalette(name: "Aurora",     low: Color(hue: 0.42, saturation: 0.90, brightness: 0.85),
                        high: Color(hue: 0.55, saturation: 0.80, brightness: 1.0)),
        SpectrumPalette(name: "AquaCyan",   low: Color(hue: 0.50, saturation: 0.90, brightness: 0.95),
                        high: Color(hue: 0.46, saturation: 0.75, brightness: 1.0)),
        
        // ── 蓝色 / 冰蓝系 (0.58 ~ 0.70) ──
        SpectrumPalette(name: "Glacier",    low: Color(hue: 0.55, saturation: 0.70, brightness: 1.0),
                        high: Color(hue: 0.62, saturation: 0.50, brightness: 1.0)),
        SpectrumPalette(name: "Teal",       low: Color(hue: 0.58, saturation: 0.85, brightness: 0.95),
                        high: Color(hue: 0.65, saturation: 0.70, brightness: 1.0)),
        
        // ── 💜 紫罗兰 / 靛蓝系 (0.70 ~ 0.82) ──
        SpectrumPalette(name: "Ultramarine",low: Color(hue: 0.68, saturation: 0.85, brightness: 0.95),
                        high: Color(hue: 0.76, saturation: 0.75, brightness: 1.0)),
        SpectrumPalette(name: "Orchid",     low: Color(hue: 0.75, saturation: 0.80, brightness: 0.98),
                        high: Color(hue: 0.80, saturation: 0.65, brightness: 1.0)),
        
        // ── 💖 霓虹粉 / 洋红系 (0.82 ~ 1.00) ──
        SpectrumPalette(name: "Candy",      low: Color(hue: 0.78, saturation: 0.75, brightness: 1.0),
                        high: Color(hue: 0.84, saturation: 0.65, brightness: 1.0)),
        SpectrumPalette(name: "Neon",       low: Color(hue: 0.85, saturation: 1.00, brightness: 1.0),
                        high: Color(hue: 0.95, saturation: 0.90, brightness: 1.0)),
        SpectrumPalette(name: "Plum",       low: Color(hue: 0.90, saturation: 0.85, brightness: 0.95),
                        high: Color(hue: 0.98, saturation: 0.70, brightness: 1.0))
    ]
}

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval // 换算成总秒数，方便跟播放器的当前进度做比对
    let text: String       // 歌词文本
}

// MARK: - 车道逻辑分发判官
enum LineType { case odd, even }

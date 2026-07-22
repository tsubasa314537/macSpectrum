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
    
//    ✨ 核心新增：根据传入的专辑平均色，动态繁衍出一套完美的高低频渐变主题
    init(from averageColor: Color, name: String = "AlbumDynamic") {
        self.name = name
        self.low = averageColor // 中心侧采用纯正的专辑主色，作为能量大本营
        
        // 🚀 巧思：为了让高频有层次感，我们在底层把主色转成 HSL，将色相（Hue）轻轻推移一点点（比如 +0.1）
        // 这样高频边缘就会产生极具艺术感的同色系色彩流转，绝不单调！
#if os(macOS)
        let nsColor = NSColor(averageColor).usingColorSpace(.deviceRGB) ?? .white
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
#else
        let uiColor = UIColor(averageColor)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
#endif
        
        // 高频外侧：色相微调 +0.08（比如黄变橙，蓝变紫），亮度拔高到极限
        let newHue = (h + 0.08).truncatingRemainder(dividingBy: 1.0)
        self.high = Color(hue: Double(newHue), saturation: Double(s), brightness: min(Double(b) * 1.2, 1.0))
    }
    
    // 原有的预设保留（作为兜底）
    init(name: String, low: Color, high: Color) {
        self.name = name
        self.low = low
        self.high = high
    }
}

extension SpectrumPalette {
    static let all: [SpectrumPalette] = [
        // ===========================================================
        // 🌊 蓝色家族大扩军（由深至浅、从赛博到透明）
        // ===========================================================
        // 1. 原版深海（压暗加深底座，高频流转）
//        SpectrumPalette(name: "Ocean",    low: Color(hue: 0.60, saturation: 0.95, brightness: 0.85),
//                        high: Color(hue: 0.68, saturation: 0.85, brightness: 0.95)),
        
        // 2. 新增：电光青蓝（浅蓝、高亮度、极具穿透力，专门对付暗黑和灰白背景！）
        SpectrumPalette(name: "AquaCyan", low: Color(hue: 0.52, saturation: 0.90, brightness: 0.95),
                        high: Color(hue: 0.48, saturation: 0.75, brightness: 1.0)),
        SpectrumPalette(name: "AquaCyan", low: Color(hue: 0.52, saturation: 0.90, brightness: 0.95),
                        high: Color(hue: 0.48, saturation: 0.75, brightness: 0.75)),
        // 3. 新增：冰晶透蓝（极高明度的冷调浅蓝，在白底或黑底下都像水晶一样亮眼）
        SpectrumPalette(name: "Glacier",  low: Color(hue: 0.55, saturation: 0.70, brightness: 1.0),
                        high: Color(hue: 0.62, saturation: 0.50, brightness: 1.0)),
        SpectrumPalette(name: "DarkGlacier",  low: Color(hue: 0.55, saturation: 0.70, brightness: 1.0),
                        high: Color(hue: 0.62, saturation: 0.50, brightness: 0.6)),
        // ===========================================================
        // 🌋 熔岩红色家族拆分（彻底解决太深太暗的问题）
        // ===========================================================
        // 1. 原版熔岩（基部明度强行抬高到 0.95！）
//        SpectrumPalette(name: "Lava",     low: Color(hue: 0.00, saturation: 1.0, brightness: 0.95),
//                        high: Color(hue: 0.08, saturation: 0.85, brightness: 1.0)),
        
        // 2. 新增：炽热岩浆（往橙黄色偏置，明度拉满，绝对不会暗淡！）
        SpectrumPalette(name: "Magma",    low: Color(hue: 0.04, saturation: 1.0, brightness: 1.0),
                        high: Color(hue: 0.12, saturation: 0.90, brightness: 1.0)),
        SpectrumPalette(name: "DarkMagma",    low: Color(hue: 0.04, saturation: 1.0, brightness: 1.0),
                        high: Color(hue: 0.12, saturation: 0.90, brightness: 0.75)),
        // ===========================================================
        // 🔮 梦幻糖果重铸（彻底告别蓝色，拥抱绝美浅紫！）
        // ===========================================================
        // 彻底清洗 HSL 参数，将低频锁在优雅的浅紫/玫紫（0.78），高频流向粉紫（0.84），流光溢彩！
        SpectrumPalette(name: "Candy",    low: Color(hue: 0.78, saturation: 0.75, brightness: 1.0),
                        high: Color(hue: 0.84, saturation: 0.65, brightness: 1.0)),
        SpectrumPalette(name: "DarkCandy",    low: Color(hue: 0.78, saturation: 0.75, brightness: 1.0),
                        high: Color(hue: 0.84, saturation: 0.65, brightness: 0.75)),
        // ===========================================================
        // 🎨 其余经典艺术保留骨架
        // ===========================================================
        SpectrumPalette(name: "Sunset",   low: Color(hue: 0.08, saturation: 1.0, brightness: 1.0),
                        high: Color(hue: 0.16, saturation: 0.9, brightness: 1.0)),
//        SpectrumPalette(name: "DarkSunset",   low: Color(hue: 0.08, saturation: 1.0, brightness: 1.0),
//                        high: Color(hue: 0.16, saturation: 0.9, brightness: 0.75)),
        SpectrumPalette(name: "Aurora",   low: Color(hue: 0.42, saturation: 0.9, brightness: 0.85),
                        high: Color(hue: 0.55, saturation: 0.8, brightness: 1.0)),
        SpectrumPalette(name: "DarkAurora",   low: Color(hue: 0.42, saturation: 0.9, brightness: 0.85),
                        high: Color(hue: 0.55, saturation: 0.8, brightness: 0.5)),
        SpectrumPalette(name: "Neon",     low: Color(hue: 0.85, saturation: 1.0, brightness: 1.0),
                        high: Color(hue: 0.95, saturation: 0.9, brightness: 1.0)),
        SpectrumPalette(name: "DarkNeon",     low: Color(hue: 0.85, saturation: 1.0, brightness: 1.0),
                        high: Color(hue: 0.95, saturation: 0.9, brightness: 0.75)),
        SpectrumPalette(name: "Mint",     low: Color(hue: 0.45, saturation: 0.7, brightness: 0.9),
                        high: Color(hue: 0.33, saturation: 0.6, brightness: 1.0)),
        SpectrumPalette(name: "DarkMint",     low: Color(hue: 0.45, saturation: 0.7, brightness: 0.9),
                        high: Color(hue: 0.33, saturation: 0.6, brightness: 0.65)),
        SpectrumPalette(name: "Gold",     low: Color(hue: 0.13, saturation: 1.0, brightness: 0.9),
                        high: Color(hue: 0.18, saturation: 0.85, brightness: 1.0)),
        SpectrumPalette(name: "DarkGold",     low: Color(hue: 0.13, saturation: 1.0, brightness: 0.9),
                        high: Color(hue: 29 / 360 , saturation: 0.81, brightness: 0.93))
    ]
}

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval // 换算成总秒数，方便跟播放器的当前进度做比对
    let text: String       // 歌词文本
}

// MARK: - 🗺️ 车道逻辑分发判官
enum LineType { case odd, even }

//
// PaletteManager.swift
// MacSpectrum
//
// Created by 郭鹏 on 2026/6/2.
//

import SwiftUI
import Combine

// MARK: - 主题管理器
class PaletteManager: ObservableObject {
    
    @Published var blendFactor: Double = 1.0 // 默认 1.0 代表已经过渡完毕
    @Published var currentPalette: SpectrumPalette = SpectrumPalette(
        name: "Default",
        low: .cyan,
        high: .cyan
    )
    
    @Published var bgPalette = Color(.cyan)
    
    private var fromPalette: SpectrumPalette?
    private var toPalette: SpectrumPalette?
    
    // ── 👴 【老爷子的经典 hold 调度备忘录】 ──────────────────
    private var displayLinkTimer: Timer?
    private var blendStart: Date?
    private let blendDuration: TimeInterval = 1.8 // 🎯 换歌时，色彩渐变 1.8 秒，丝滑又不拖沓
    
    // ── ✈️ 【Autopilot 自动驾驶专用雷达】 ──────────────────
    private var autopilotTimer: Timer?
    @Published var isAutopilotActive: Bool = false
    
    init() {
        // 🚀 老爷子！经典【init走 hold 调度】满血复活！
        // 启动时默认加载第一套手工主题，并初始化好混色基准
        let defaultPreset = SpectrumPalette.all.first(where: { $0.name == "Sunset" }) ?? SpectrumPalette.all[0]
        self.currentPalette = defaultPreset
        self.fromPalette = defaultPreset
        self.toPalette = defaultPreset
        self.bgPalette = defaultPreset.high
    }
    
    deinit {
        displayLinkTimer?.invalidate()
        autopilotTimer?.invalidate()
    }
    
    // ── ✈️ 【核心邪术：启动/停止萨博自动驾驶变换】 ──────────────────
    func startAutopilotColors() {
        self.isAutopilotActive = true
        self.autopilotTimer?.invalidate() // 防御性清空旧钟
        
        // 1. 进模式的一瞬间，立刻先盲摇一套双色，别让老爷子等
        self.triggerRandomAutopilotBlend()
        
        // 2. 🕰️ 每 10 秒雷打不动地随机渐变更换手工主题
        self.autopilotTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.triggerRandomAutopilotBlend()
        }
    }
    
    func stopAutopilotColors() {
        self.isAutopilotActive = false
        self.autopilotTimer?.invalidate()
        self.autopilotTimer = nil
        // 停止自动驾驶后，保持当前颜色不变，等待下一首歌曲的专辑色来接管
    }
    
    private func triggerRandomAutopilotBlend() {
        guard let randomPreset = SpectrumPalette.all.randomElement() else { return }
        
        self.fromPalette = self.currentPalette
        self.toPalette = randomPreset
        
        DispatchQueue.main.async {
            self.bgPalette = randomPreset.high
        }
        
        self.blendFactor = 0.0
        self.blendStart = Date()
        
        // 🚀 唤醒 60fps 混色车间
        self.displayLinkTimer?.invalidate()
        self.displayLinkTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.performBlend()
        }
    }
    
    // ── 🚀 完全体动态染色中心：支持 [即时硬切 / 丝滑渐变] 切换 ──
    // 🎯 增加了 animated 参数（默认为 true）
    func updateAlbumColor(_ newColor: Color, _ themeType: String, animated: Bool = true) {
        // 🚨 安全拦截：如果当前正在自动驾驶（Autopilot），不允许换歌的专辑色来打乱节奏！
        if isAutopilotActive { return }
        
        // 1. 提取真实专辑色的 HSL 组件来判断色彩家族
#if os(macOS)
        let nsColor = NSColor(newColor).usingColorSpace(.deviceRGB) ?? .white
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
#else
        let uiColor = UIColor(newColor)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
#endif
        
        // 兜底默认用 落日余晖 主题
        var targetPreset = SpectrumPalette.all.first(where: { $0.name == "Sunset" }) ?? SpectrumPalette.all[0]
        
        // 🎯 密网交织：全量匹配您的所有 8 套艺术主题！
        if themeType == "black" {
            if h >= 0.0 && h < 0.04 {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "Candy" }) ?? targetPreset
            } else if h >= 0.04 && h < 0.11 {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "Sunset" }) ?? targetPreset
            } else if h >= 0.11 && h < 0.20 {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "Gold" }) ?? targetPreset
            } else if h >= 0.20 && h < 0.40 {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "Mint" }) ?? targetPreset
            } else if h >= 0.40 && h < 0.58 {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "Aurora" }) ?? targetPreset
            } else if h >= 0.58 && h < 0.67 {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "Glacier" }) ?? targetPreset
            } else if h >= 0.67 && h < 0.76 {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "AquaCyan" }) ?? targetPreset
            } else if h >= 0.76 && h < 0.88 {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "Neon" }) ?? targetPreset
            } else {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "Candy" }) ?? targetPreset
            }
        } else {
            if h >= 0.0 && h < 0.04 {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "DarkCandy" }) ?? targetPreset
            } else if h >= 0.04 && h < 0.11 {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "DarkGold" }) ?? targetPreset
            } else if h >= 0.11 && h < 0.20 {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "DarkMint" }) ?? targetPreset
            } else if h >= 0.20 && h < 0.40 {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "DarkMint" }) ?? targetPreset
            } else if h >= 0.40 && h < 0.58 {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "DarkAurora" }) ?? targetPreset
            } else if h >= 0.58 && h < 0.67 {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "DarkGlacier" }) ?? targetPreset
            } else if h >= 0.67 && h < 0.76 {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "DarkAquaCyan" }) ?? targetPreset
            } else if h >= 0.76 && h < 0.88 {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "DarkNeon" }) ?? targetPreset
            } else {
                targetPreset = SpectrumPalette.all.first(where: { $0.name == "DarkCandy" }) ?? targetPreset
            }
        }
        
        // 2. 注入血肉：低频（中心侧）死死咬合住真实的专辑色
        let baseLow = newColor
        let dynamicPalette = SpectrumPalette(name: "Hybrid-\(targetPreset.name)", low: baseLow, high: targetPreset.high)
        
        // 3. 🚀【核心改进】：处理手动切换与自动切换的分流逻辑
        if !animated || fromPalette == nil {
            // 🎯 手动切主题（animated == false）：立刻取消所有定时器，0 秒瞬间硬切落地！
            self.displayLinkTimer?.invalidate()
            self.displayLinkTimer = nil
            
            self.currentPalette = dynamicPalette
            self.fromPalette = dynamicPalette
            self.toPalette = dynamicPalette
            self.blendFactor = 1.0
            
            DispatchQueue.main.async {
                self.bgPalette = dynamicPalette.high
            }
            return
        }
        
        // 🚚 换歌（animated == true）：开启 1.8 秒丝滑 60fps 渐变
        self.fromPalette = self.currentPalette
        self.toPalette = dynamicPalette
        
        if let highP = self.toPalette?.high {
            DispatchQueue.main.async {
                self.bgPalette = highP
            }
        }
        
        self.blendFactor = 0.0
        self.blendStart = Date()
        
        self.displayLinkTimer?.invalidate()
        self.displayLinkTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.performBlend()
        }
    }
    
    private func performBlend() {
        guard let start = blendStart, let from = fromPalette, let to = toPalette else { return }
        let elapsed = Date().timeIntervalSince(start)
        let progress = min(elapsed / blendDuration, 1.0)
        
        let blendedLow = interpolate(from: from.low, to: to.low, t: progress)
        let blendedHigh = interpolate(from: from.high, to: to.high, t: progress)
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.blendFactor = progress
            self.currentPalette = SpectrumPalette(name: "Blending", low: blendedLow, high: blendedHigh)
            
            if progress >= 1.0 {
                self.displayLinkTimer?.invalidate()
                self.fromPalette = to
            }
        }
    }
    
    /// ── UI层渲染光柱时的颜色调用 ──
    func color(position: Double, intensity: Double) -> Color {
        let color = interpolate(
            from: currentPalette.high,
            to: currentPalette.high,
            t: position
        )
        return color.opacity(0.4 + intensity * 0.6)
    }
    
    // 经典双平台 RGB 分量万能插值公式
    private func interpolate(from: Color, to: Color, t: Double) -> Color {
#if os(macOS)
        let f = NSColor(from).usingColorSpace(.deviceRGB) ?? NSColor.white
        let g = NSColor(to).usingColorSpace(.deviceRGB)   ?? NSColor.white
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var gr: CGFloat = 0, gg: CGFloat = 0, gb: CGFloat = 0, ga: CGFloat = 0
        f.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        g.getRed(&gr, green: &gg, blue: &gb, alpha: &ga)
#else
        let f = UIColor(from)
        let g = UIColor(to)
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var gr: CGFloat = 0, gg: CGFloat = 0, gb: CGFloat = 0, ga: CGFloat = 0
        f.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        g.getRed(&gr, green: &gg, blue: &gb, alpha: &ga)
#endif
        
        let ct = CGFloat(t)
        return Color(
            red:     Double(fr + (gr - fr) * ct),
            green:   Double(fg + (gg - fg) * ct),
            blue:    Double(fb + (gb - fb) * ct),
            opacity: Double(fa + (ga - fa) * ct)
        )
    }
}

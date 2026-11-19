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
    
    // 🎯 当前主题表面。所有颜色都按"与底的感知亮度对比度"现算，所以切主题必须重算一遍。
    @Published var surface: ThemeSurface = .dark
    
    // 🎨 引擎派生出的四色：core 柱体描边 / wash 极淡填充 / accent 文字级强调 / glow 光晕。
    @Published private(set) var ink: ThemeInk = ThemeColorEngine.ink(
        from: Color(hue: 0.08, saturation: 1.0, brightness: 1.0),
        surface: .dark
    )
    
    // 🎯 全局强调色：指向 ink.accent。
    // 以前它是一个写死等于 currentPalette.high 的 @Published 存储属性，两套主题共用一套为纯黑底
    // 设计的高亮霓虹色，于是灰白主题下明黄/冰川蓝直接看不见。改成按主题派生后，
    // 歌词当前行、列表选中、标题等所有调用点自动获得主题适配。
    var bgPalette: Color { ink.accent }
    
    private var fromPalette: SpectrumPalette?
    private var toPalette: SpectrumPalette?
    
    private var displayLinkTimer: Timer?
    private var blendStart: Date?
    private let blendDuration: TimeInterval = 1.8 // 换歌时，色彩渐变 1.8 秒
    
    private var autopilotTimer: Timer?
    @Published var isAutopilotActive: Bool = false
    
    init() {
        let defaultPreset = SpectrumPalette.all.first(where: { $0.name == "Sunset" }) ?? SpectrumPalette.all[0]
        self.currentPalette = defaultPreset
        self.fromPalette = defaultPreset
        self.toPalette = defaultPreset
        self.ink = ThemeColorEngine.ink(from: defaultPreset.low, surface: self.surface)
    }
    
    deinit {
        displayLinkTimer?.invalidate()
        autopilotTimer?.invalidate()
    }
    
    func startAutopilotColors() {
        self.isAutopilotActive = true
        self.autopilotTimer?.invalidate()
        
        self.triggerRandomAutopilotBlend()
        
        self.autopilotTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.triggerRandomAutopilotBlend()
        }
    }
    
    func stopAutopilotColors() {
        self.isAutopilotActive = false
        self.autopilotTimer?.invalidate()
        self.autopilotTimer = nil
    }
    
    private func triggerRandomAutopilotBlend() {
        guard let randomPreset = SpectrumPalette.all.randomElement() else { return }
        
        self.fromPalette = self.currentPalette
        self.toPalette = randomPreset
        
        self.ink = ThemeColorEngine.ink(from: randomPreset.low, surface: self.surface)
        
        self.blendFactor = 0.0
        self.blendStart = Date()
        
        self.displayLinkTimer?.invalidate()
        self.displayLinkTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.performBlend()
        }
    }
    
    func updateAlbumColor(_ newColor: Color, _ themeType: String, animated: Bool = true) {
        if isAutopilotActive { return }
        
#if os(macOS)
        let nsColor = NSColor(newColor).usingColorSpace(.deviceRGB) ?? .white
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
#else
        let uiColor = UIColor(newColor)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
#endif
        
        var targetPreset = SpectrumPalette.all.first(where: { $0.name == "Sunset" }) ?? SpectrumPalette.all[0]
        
        // 🎯 16 段精细化 HSL 色相匹配网络
        if h >= 0.00 && h < 0.03 {
            targetPreset = SpectrumPalette.all.first(where: { $0.name == "Rose" }) ?? targetPreset
        } else if h >= 0.03 && h < 0.07 {
            targetPreset = SpectrumPalette.all.first(where: { $0.name == "Magma" }) ?? targetPreset
        } else if h >= 0.07 && h < 0.11 {
            targetPreset = SpectrumPalette.all.first(where: { $0.name == "Sunset" }) ?? targetPreset
        } else if h >= 0.11 && h < 0.15 {
            targetPreset = SpectrumPalette.all.first(where: { $0.name == "Amber" }) ?? targetPreset
        } else if h >= 0.15 && h < 0.20 {
            targetPreset = SpectrumPalette.all.first(where: { $0.name == "Gold" }) ?? targetPreset
        } else if h >= 0.20 && h < 0.28 {
            targetPreset = SpectrumPalette.all.first(where: { $0.name == "Lime" }) ?? targetPreset
        } else if h >= 0.28 && h < 0.38 {
            targetPreset = SpectrumPalette.all.first(where: { $0.name == "Emerald" }) ?? targetPreset
        } else if h >= 0.38 && h < 0.46 {
            targetPreset = SpectrumPalette.all.first(where: { $0.name == "Mint" }) ?? targetPreset
        } else if h >= 0.46 && h < 0.52 {
            targetPreset = SpectrumPalette.all.first(where: { $0.name == "AquaCyan" }) ?? targetPreset
        } else if h >= 0.52 && h < 0.58 {
            targetPreset = SpectrumPalette.all.first(where: { $0.name == "Aurora" }) ?? targetPreset
        } else if h >= 0.58 && h < 0.64 {
            targetPreset = SpectrumPalette.all.first(where: { $0.name == "Glacier" }) ?? targetPreset
        } else if h >= 0.64 && h < 0.70 {
            targetPreset = SpectrumPalette.all.first(where: { $0.name == "Teal" }) ?? targetPreset
        } else if h >= 0.70 && h < 0.76 {
            targetPreset = SpectrumPalette.all.first(where: { $0.name == "Ultramarine" }) ?? targetPreset
        } else if h >= 0.76 && h < 0.82 {
            targetPreset = SpectrumPalette.all.first(where: { $0.name == "Orchid" }) ?? targetPreset
        } else if h >= 0.82 && h < 0.88 {
            targetPreset = SpectrumPalette.all.first(where: { $0.name == "Candy" }) ?? targetPreset
        } else if h >= 0.88 && h < 0.94 {
            targetPreset = SpectrumPalette.all.first(where: { $0.name == "Neon" }) ?? targetPreset
        } else {
            targetPreset = SpectrumPalette.all.first(where: { $0.name == "Plum" }) ?? targetPreset
        }
        
        // 🎨 先拿专辑平均色，再往匹配到的预设色相上锚一小段：保留专辑身份，又借预设把脏色往正色带。
        // 这个锚定后的颜色作为 palette.low 存下来，后续 blend 逐帧插值的也是它，ink 那么每帧跟着重算。
        let anchored = ThemeColorEngine.anchor(album: newColor, toward: targetPreset.high, weight: 0.35)
        let dynamicPalette = SpectrumPalette(name: "Hybrid-\(targetPreset.name)", low: anchored, high: targetPreset.high)
        let targetInk = ThemeColorEngine.ink(from: anchored, surface: ThemeSurface.of(themeType: themeType))
        
        if !animated || fromPalette == nil {
            self.displayLinkTimer?.invalidate()
            self.displayLinkTimer = nil
            
            self.currentPalette = dynamicPalette
            self.fromPalette = dynamicPalette
            self.toPalette = dynamicPalette
            self.blendFactor = 1.0
            
            DispatchQueue.main.async {
                self.surface = ThemeSurface.of(themeType: themeType)
                self.ink = targetInk
            }
            return
        }
        
        self.fromPalette = self.currentPalette
        self.toPalette = dynamicPalette
        
        DispatchQueue.main.async {
            self.surface = ThemeSurface.of(themeType: themeType)
            self.ink = targetInk
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
        
        // 🎨 颜色过渡期间逐帧重算 ink：插值走的是锚定后的源色(low)，所以换歌时强调色、
        // 柱体色、光晕是一起平滑渐变的，而不是像以前那样 blend 完成瞬间跳色。
        let blendedInk = ThemeColorEngine.ink(from: blendedLow, surface: self.surface)
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.blendFactor = progress
            self.currentPalette = SpectrumPalette(name: "Blending", low: blendedLow, high: blendedHigh)
            self.ink = blendedInk
            
            if progress >= 1.0 {
                self.displayLinkTimer?.invalidate()
                self.fromPalette = to
            }
        }
    }
    
    func color(position: Double, intensity: Double) -> Color {
        let color = interpolate(
            from: currentPalette.high,
            to: currentPalette.high,
            t: position
        )
        return color.opacity(0.4 + intensity * 0.6)
    }
    
    // 🎨 光柱专用色源：以前 themeType / isAutopilot 两个参数是摆设，永远返回 bgPalette，
    // 两套主题共用一组为黑底设计的颜色。现在直接吃按主题派生好的 ink。
    func barColor(position: Double, intensity: Double, themeType: String, isAutopilot: Bool) -> Color {
        // ⚠️ 浅底不能沿用那套“低能量就压透明度”的招：core 的对比度是按满不透明度反解出来的，
        // 再乘 0.45 会让安静部分的柱子直接被洗进背景里。深底 fade into black 很自然，浅底只留一点呼吸。
        surface.isLight
            ? ink.core.opacity(0.80 + intensity * 0.20)
            : ink.core.opacity(0.45 + intensity * 0.55)
    }

    /// 变白曲线指数：>1 让中段留住颜色，只有能量真的顶到上限才泛白。
    private let whiteCurve: Double = 1.35

    /// 柱体"肚子"的主体色：按能量在 core → wash 之间插值。
    ///
    /// ⚠️ 这里的驱动量是**能量**，不是竖向位置。之前按位置把柱体分四层变浅是错的：
    /// 那样一根安静的矮柱也会顶端发白，而一根满能量的柱除了顶部照样是深色。
    /// QQ 白主题的真实逻辑是“能量越大 → 越高 → 肚子越大 → 整根越白”，
    /// 所以它必须和 bulge（肚子宽度）用同一个驱动量，两者才能绑在一起变。
    /// whiteness 直接取 0...1 原始值，不再额外叠加 opacity（core 的对比度是按满不透明度解出来的）。
    /// 线性映射下 0.5 能量就已经褪到一半，整片频谱会看着像"往背景里淡出"；
    /// 1.35 下 0.5 能量只走 0.39，而 1.0 能量仍然完整走到 wash。
    func barBellyColor(whiteness: CGFloat) -> Color {
        guard surface.isLight else { return ink.core }
        let t = CGFloat(pow(min(max(whiteness, 0), 1), whiteCurve))
        let c = ink.coreRGB, w = ink.washRGB
        return Color(red: Double(c.r + (w.r - c.r) * t),
                     green: Double(c.g + (w.g - c.g) * t),
                     blue: Double(c.b + (w.b - c.b) * t))
    }

    /// 底部反光带用色：始终是那层极淡 tint，不随能量变。
    var barWashColor: Color { ink.wash }

    /// shadow / blur 用色。
    /// 注：灰白主题下它只给柱内那层能量驱动的 blur 用；外层投影已改成中性黑
    /// （用 glow 色做投影会和 blur 叠成一片黄雾，颜色应该只留在柱体里）。
    var barGlowColor: Color { ink.glow }

    /// 灰白主题的页面底渐变：顶部压一层主题色的**互补色**淡 tint，往下衰减，到光柱区回到纯页面色。
    ///
    /// 三个设计约束，缺一不可：
    /// ① tint 与页面**等亮度**（ThemeColorEngine.tintSat 解出来的），所以 core / accent 现有的
    ///    2.0:1 / 3.6:1 目标全部继续成立，不需要重算任何一个颜色；
    /// ② 底部必须回到无色——最下面 16pt 是 wash 反光带，那是主题色的半透明平铺，
    ///    和互补底在全强度下相遇会互相抵消成灰米色；
    /// ③ 用连续梯度而不是硬边——割裂感的真来源是硬边，不是“有色”。
    ///
    /// 0.42 处插一个“tint 与页面各半”的中间档，是为了让上半段慢降、下半段收平；
    /// 只有两端的双档会读成“上面刷了一块色”，三档才读成“空气里有颜色”。
    var backgroundGradient: LinearGradient {
        let pageRGB = surface.backgroundRGB
        let midRGB = ThemeColorEngine.mix(ink.bgTintRGB, pageRGB, 0.5)
        let page = surface.background
        if !surface.isLight {
            return LinearGradient(colors: [page, page], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(
            stops: [
                .init(color: ink.bgTint, location: 0.00),
                .init(color: Color(red: Double(midRGB.r), green: Double(midRGB.g), blue: Double(midRGB.b)),
                      location: 0.42),
                .init(color: page, location: 0.78),
                .init(color: page, location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // 🔁 主题切换时重算 ink。以前没有任何入口触发重算（updateAlbumColor 只在 onAppear / 换歌时调），
    // 所以 Cmd+T 切到灰白后拿到的仍然是为黑底算的那套色。现由 MainPlayerView.onChange(of: themeType) 调。
    func applyTheme(_ themeType: String) {
        let next = ThemeSurface.of(themeType: themeType)
        guard next != surface else { return }
        surface = next
        ink = ThemeColorEngine.ink(from: currentPalette.low, surface: next)
    }
    
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

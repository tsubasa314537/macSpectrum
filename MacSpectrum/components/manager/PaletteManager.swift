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
    
    /// 专辑图 → 当前封面 + 主题色。主界面和正在播放页共用这一份，
    /// 免得两边各写一套、其中一边漏挂 onChange（主界面原先就是这么丢的）。
    /// 返回挑中的那张图，由调用方写回 player.nowAlbum。
    @discardableResult
    func applyAlbumImages(_ images: [NSImage], themeType: String) -> NSImage? {
        // 多张专辑图时随机取一张：唱片页是「轮换封面」的语义，跟着随机才能和转盘上看到的一致。
        let image = images.isEmpty ? NSImage(named: "Albumdefault") : images.randomElement()
        if let image, let average = image.averageColor {
            // animated: false —— 换歌要的是「到新歌就直接变色」，1.8s 渐变只留给 autopilot 混色。
            updateAlbumColor(Color(average), themeType, animated: false)
        }
        return image
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

    // ── 外侧渐隐柱专用色 ────────────────────────────────
    // 只被超出 AudioManager.coreBandCount 的那几根调用，原有 32 根走的
    // barColor / barBellyColor 一行没动。做法是**只改颜色**：RGB 往页面底混 mix，
    // alpha 同比例乘 (1-mix)，不加任何 blur、不改尺寸、不改 shadow/blur 半径。
    // 为什么不止混 RGB：正在播放页黑主题的底是「纯黑 + 20% 强调色 wash」（见
    // MainPlayerView 的 .background 分支），并不等于 surface.background；只混到页面底色
    // 仍会留一块色差。alpha 一起收到 0 才能保证最外侧那根真的看不见。
    // 两条都走 ink 的分量缓存，一帧几次乘加，不做 Color → NSColor 反解（每秒 60 帧）。

    /// core 色往页面底混 mix：0 = 与 barColor 完全同值，1 = 彻底消失。
    func barFadeColor(intensity: Double, mix: CGFloat) -> Color {
        let t = min(max(mix, 0), 1)
        let rgb = ThemeColorEngine.mix(ink.coreRGB, surface.backgroundRGB, t)
        // 不透明度曲线与 barColor 保持一致，再乘 (1-t)。黑主题里 shadow 吃的也是这个色，
        // 所以它跟着一起淡出，不需要额外处理。
        let alpha = (surface.isLight ? 0.80 + intensity * 0.20 : 0.45 + intensity * 0.55) * Double(1 - t)
        return Color(red: Double(rgb.r), green: Double(rgb.g), blue: Double(rgb.b), opacity: alpha)
    }

    /// 肚子色：与 barBellyColor 同一条 core→wash 能量曲线，末端再往页面底混 mix。
    func barFadeBellyColor(whiteness: CGFloat, mix: CGFloat) -> Color {
        let t = min(max(mix, 0), 1)
        // 黑主题的柱体就是 SmoothPentagon 单色，根本没有“肚子”这一层；给个 faded core 兜底。
        guard surface.isLight else { return barFadeColor(intensity: 0, mix: t) }
        let w = CGFloat(pow(min(max(whiteness, 0), 1), whiteCurve))
        let belly = ThemeColorEngine.mix(ink.coreRGB, ink.washRGB, w)
        let rgb = ThemeColorEngine.mix(belly, surface.backgroundRGB, t)
        return Color(red: Double(rgb.r), green: Double(rgb.g), blue: Double(rgb.b), opacity: Double(1 - t))
    }

    // MARK: - 列表文字色
    // 主界面 header、歌单列、歌曲列三处都要用，所以住在 palette 里而不是某个视图里。
    // 不能拿 Color.primary / .secondary：那两个跟着**系统**外观走，app 自己切主题它不管，
    // 黑主题下系统还是浅色时文字就直接隐进背景了。

    /// 正文级主色。浅主题用接近黑的深灰而不是纯黑：15pt 大面积正文白底上纯黑太硬。
    var textPrimary: Color { surface.isLight ? Color(white: 0.12) : .white }
    /// 输入框 placeholder 用色。系统那层 placeholderTextColor 跟着**系统外观**走，app 自己切主题
    /// 它不跟：系统外观 Dark + 本 app 浅主题时，浅底上画的是白字，实测与底色同为 0.957、零对比，
    /// 根本读不出字（用户反馈）。所以这里显式给色，不走系统默认。
    /// 0.18 比正文 0.12 略浅，空框不会看成“已经有字”；想再黑就把它贴到 textPrimary。
    var textPlaceholder: Color { surface.isLight ? Color(white: 0.18) : Color.white.opacity(0.55) }
    /// 次要色（艺术家、专辑、时长、未选中图标）。
    var textSecondary: Color { surface.isLight ? Color(white: 0.42) : Color.white.opacity(0.55) }
    /// shadow / blur 用色。
    /// 注：灰白主题下它只给柱内那层能量驱动的 blur 用；外层投影已改成中性黑
    /// （用 glow 色做投影会和 blur 叠成一片黄雾，颜色应该只留在柱体里）。
    var barGlowColor: Color { ink.glow }

    /// 灰白主题的页面底渐变：顶部压一层主题色的**互补色**淡 tint，往下衰减，到光柱区回到纯页面色。
    ///
    /// 三个设计约束，缺一不可：
    /// ① tint 最多只比页面暗 `ThemeColorEngine.tintMaxDark`（1.18:1）。原先要求严格等亮度，
    ///    结果黄/金主题的互补蓝在等亮度下几乎没有彩度空间，tint 直接解成白色（用户反馈“反差色
    ///    看不出来”）；改成允许暗一点点后，accent 的 3.6:1 最差还剩 3.0:1，仍在可读线以上；
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

    /// 待机呼吸的字样色：从 accent（= bgPalette）往「淡端」插值。
    /// phase 取 0…1（0 = accent 本身，1 = 峰位最淡），amplitude 是最大淡化量。
    /// 拿缓存分量做三次乘加，不走 Color → NSColor 反解——这个函数每秒会被调 60 次。
    ///
    /// ⚠️ 淡端往哪儿混必须分主题，不能一律往纯白：
    /// 浅主题下 accent 本身已是 3.6:1 的暗彩色，再往**纯白**混到调用方给的 0.60，
    /// 峰位相对亮度被抬到与页面底只差一点 —— 扫完整个色相空间，最淡点最差只剩 **1.48:1**
    /// （深色系主题如黄、金更接近 1.5，等于没有），这就是用户反馈的“白色主题下最浅色看不见”。
    /// 改成往**页面底色**混、幅度按 `lightBreathFade` 收口后，最淡点最差 2.04:1：
    /// 观感上仍然是“颜色往底里化开再收回来”，但字始终在。
    /// 深主题维持原样（往纯白、幅度 0.60，峰位最差仍有 10.31:1）——黑底上变白就是变亮，
    /// 对比度不掉，用户也确认黑色主题这版没问题。
    func wordmarkColor(phase: Double, amplitude: Double) -> Color {
        let c = ink.accentRGB
        let w = min(max(phase, 0) * min(max(amplitude, 0), 1), 1)
        let t = surface.isLight ? min(w, lightBreathFade) : w
        let m = ThemeColorEngine.mix(c, surface.isLight ? surface.backgroundRGB : (r: 1, g: 1, b: 1), t)
        return Color(red: Double(m.r), green: Double(m.g), blue: Double(m.b))
    }

    /// 浅主题的最大淡化量（往页面底色混的比例）。0.40 是“最淡点仍站得住 2:1”那一档，
    /// 想呼吸得更开就往上加：0.45 → 1.91:1，0.52 → 1.75:1（再高浅底上就要开始闪没了）。
    private let lightBreathFade: CGFloat = 0.40

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

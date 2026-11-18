//
//  ThemeColorEngine.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/11/18.
//

import SwiftUI

// MARK: - 主题表面

/// 两种主题各自的"底"。所有配色都按**与底的感知亮度对比度**反解，而不是各主题手调一套色值。
///
/// 之所以要这么做：16 套预设清一色 `brightness: 1.0`，但同为满亮度，黄的相对亮度约 0.72、
/// 蓝只有约 0.11。于是"黑底觉得大红大蓝偏深"和"灰白底觉得明黄冰川蓝看不见"其实是同一个 bug
/// 的两面——缺的是亮度闭环，不是删颜色。
enum ThemeSurface: Equatable {
    case dark
    case light

    /// 灰白主题底色已从 #BFBFBF 提到近白：极淡的 wash 只有在高亮底上才"长"得出来（对标 QQ 音乐）。
    private static let lightBackgroundRGB: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.957, 0.957, 0.965)
    private static let darkBackgroundRGB: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.02, 0.02, 0.03)

    private var backgroundRGB: (r: CGFloat, g: CGFloat, b: CGFloat) {
        self == .dark ? Self.darkBackgroundRGB : Self.lightBackgroundRGB
    }

    var background: Color {
        let c = backgroundRGB
        return Color(red: Double(c.r), green: Double(c.g), blue: Double(c.b))
    }

    var backgroundLuminance: CGFloat {
        let c = backgroundRGB
        return ThemeColorEngine.luminance(r: c.r, g: c.g, b: c.b)
    }

    var isLight: Bool { self == .light }

    static func of(themeType: String) -> ThemeSurface {
        themeType == "black" ? .dark : .light
    }
}

// MARK: - 派生四色

/// 一个"专辑色 + 主题底"组合派生出的完整配色。
struct ThemeInk {
    /// 柱体描边/根部：图形级对比度（浅底约 2:1）
    let core: Color
    /// 高能量时柱体趋近的那层极淡 tint：也是底部反光带的用色
    let wash: Color
    /// 文字级强调色（歌词当前行、列表选中、标题）：需要更稳的对比度（浅底约 3.6:1）
    let accent: Color
    /// shadow / blur 用色
    let glow: Color

    // core / wash 的 RGB 分量缓存：柱体要按能量在两者之间逐帧插值，
    // 如果每根柱都去走 Color → NSColor 反解，一帧就是几十次对象分配。
    // 在派生时顺手留下分量，混色就只剩三次乘加。
    let coreRGB: (r: CGFloat, g: CGFloat, b: CGFloat)
    let washRGB: (r: CGFloat, g: CGFloat, b: CGFloat)
}

// MARK: - 引擎

enum ThemeColorEngine {

    // ── 感知亮度与对比度（WCAG 相对亮度） ────────────────────────

    static func luminance(r: CGFloat, g: CGFloat, b: CGFloat) -> CGFloat {
        func linearize(_ c: CGFloat) -> CGFloat {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    static func contrast(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    // ── HSB 工具 ────────────────────────────────────────────────

    static func color(hue: CGFloat, sat: CGFloat, bri: CGFloat) -> Color {
        Color(hue: Double(hue), saturation: Double(sat), brightness: Double(bri))
    }

    /// HSB → RGB 标准展开。自己算而不是走 NSColor，避免逐帧分配颜色对象。
    static func rgb(hue: CGFloat, sat: CGFloat, bri: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let h = ((hue - floor(hue)) * 6).truncatingRemainder(dividingBy: 6)
        let s = min(max(sat, 0), 1)
        let v = min(max(bri, 0), 1)
        let c = v * s
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let rgb: (CGFloat, CGFloat, CGFloat)
        switch h {
        case 0..<1: rgb = (c, x, 0)
        case 1..<2: rgb = (x, c, 0)
        case 2..<3: rgb = (0, c, x)
        case 3..<4: rgb = (0, x, c)
        case 4..<5: rgb = (x, 0, c)
        default:    rgb = (c, 0, x)
        }
        return (rgb.0 + m, rgb.1 + m, rgb.2 + m)
    }

    private static func luminance(hue: CGFloat, sat: CGFloat, bri: CGFloat) -> CGFloat {
        let c = rgb(hue: hue, sat: sat, bri: bri)
        return luminance(r: c.r, g: c.g, b: c.b)
    }

    static func hsb(of color: Color) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
#if os(macOS)
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor.systemGray
#else
        let ns = UIColor(color)
#endif
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s, b)
    }

    // ── 感知亮度闭环 ─────────────────────────────────────────

    /// 浅底：固定 H/S，二分出**满足对比度的最大 V**（能多鲜艳就多鲜艳，只要还跳得出来）。
    /// vFloor 是亮度地板——低于它，明黄会褪成橄榄绿、青柠会褪成草绿，"土"味就是这么来的。
    /// 若在 vFloor 上都达不到 target，就停在 vFloor，剩下的辨识度交给 wash 体块与光晕补。
    static func lightBrightness(hue: CGFloat, sat: CGFloat, surface: ThemeSurface,
                                target: CGFloat, vFloor: CGFloat) -> CGFloat {
        let bg = surface.backgroundLuminance
        if contrast(luminance(hue: hue, sat: sat, bri: 1.0), bg) >= target { return 1.0 }
        if contrast(luminance(hue: hue, sat: sat, bri: vFloor), bg) < target { return vFloor }
        var lo = vFloor, hi = CGFloat(1.0)
        for _ in 0..<12 {
            let mid = (lo + hi) / 2
            if contrast(luminance(hue: hue, sat: sat, bri: mid), bg) >= target { lo = mid } else { hi = mid }
        }
        return lo
    }

    /// 深底：**V 永远钉在 1.0**，绝不压暗——暗背景上更亮同时也就更显色，去解"最小亮度"
    /// 只会得到"勉强看得见"的闷色（曾经把明黄压成 #90730C）。
    /// 真正救不了的是深蓝深紫这种**本身低亮度**的色相：纯靠提亮到顶也只有约 2.6:1，
    /// 所以第二个旋钮改成**降饱和度**把亮度抬起来（靛蓝 #3826FF → #B9B2FF），这正好治你说的"大红大蓝偏深"。
    static func darkSaturation(hue: CGFloat, sat: CGFloat, surface: ThemeSurface,
                               target: CGFloat, sFloor: CGFloat = 0.30) -> CGFloat {
        let bg = surface.backgroundLuminance
        if contrast(luminance(hue: hue, sat: sat, bri: 1.0), bg) >= target { return sat }
        if contrast(luminance(hue: hue, sat: sFloor, bri: 1.0), bg) < target { return sFloor }
        var lo = sFloor, hi = sat
        for _ in 0..<12 {
            let mid = (lo + hi) / 2
            // 饱和度越高 → 亮度越低 → 与黑底越不跳，所以留下约束内**最饱和**的那一档，
            // 只削到刚够跳为止，不要把鲜艳的蓝刷成粉紫。
            if contrast(luminance(hue: hue, sat: mid, bri: 1.0), bg) >= target { lo = mid } else { hi = mid }
        }
        return lo
    }

    // ── 主入口 ──────────────────────────────────────────────

    /// 把专辑平均色（已锚定过预设）按主题底派生成 core / wash / accent / glow。
    static func ink(from source: Color, surface: ThemeSurface) -> ThemeInk {
        let src = hsb(of: source)

        // 黑底/灰底封面的平均色几乎没有色相，硬抬饱和度只会得到脏色，直接锚到暖橙。
        let hue: CGFloat = src.s < 0.08 ? 0.08 : src.h

        // 饱和度地板：冰川蓝(s 0.50)、淡黄这类低饱和色在浅底上会直接融进背景，这里托住底线。
        let sat = min(max(src.s * 1.12, 0.58), 0.92)
        let accentSat = min(sat + 0.08, 0.95)

        let core: Color
        let accent: Color
        let wash: Color
        let glow: Color
        let coreRGB: (r: CGFloat, g: CGFloat, b: CGFloat)
        let washRGB: (r: CGFloat, g: CGFloat, b: CGFloat)

        if surface.isLight {
            // 图形级 2.0:1 就够（光柱是高频运动的装饰元素，不是正文），文字级再要到 3.6:1。
            let coreV = lightBrightness(hue: hue, sat: sat, surface: surface,
                                        target: 2.0, vFloor: 0.55)
            let accentV = lightBrightness(hue: hue, sat: accentSat, surface: surface,
                                          target: 3.6, vFloor: 0.45)
            core = color(hue: hue, sat: sat, bri: coreV)
            accent = color(hue: hue, sat: accentSat, bri: accentV)
            coreRGB = rgb(hue: hue, sat: sat, bri: coreV)
            // wash：极淡的一层 tint，在 #F4F4F6 上刚好读出"白里透着一点黄"——对标 QQ 的柱体肚子。
            wash = color(hue: hue, sat: 0.28, bri: 1.0)
            washRGB = rgb(hue: hue, sat: 0.28, bri: 1.0)
            glow = color(hue: hue, sat: min(sat, 0.72), bri: 1.0)
        } else {
            let coreSat = darkSaturation(hue: hue, sat: sat, surface: surface, target: 3.0)
            let accentSat2 = darkSaturation(hue: hue, sat: accentSat, surface: surface, target: 4.5)
            core = color(hue: hue, sat: coreSat, bri: 1.0)
            accent = color(hue: hue, sat: accentSat2, bri: 1.0)
            coreRGB = rgb(hue: hue, sat: coreSat, bri: 1.0)
            wash = color(hue: hue, sat: 0.55, bri: 0.45)
            washRGB = rgb(hue: hue, sat: 0.55, bri: 0.45)
            glow = core
        }

        return ThemeInk(core: core, wash: wash, accent: accent, glow: glow,
                        coreRGB: coreRGB, washRGB: washRGB)
    }

    /// 把专辑平均色往匹配到的预设色相上牵引一小段：保留专辑身份，又借预设这个"美化锚点"
    /// 把封面里的脏色往正色上带。weight = 0 完全跟随专辑，1 等于直接取预设。
    static func anchor(album: Color, toward anchorColor: Color, weight: CGFloat) -> Color {
        let a = hsb(of: album)
        let b = hsb(of: anchorColor)

        // 色相走最短弧，否则 0.98 → 0.02 会绕整圈跑到别的颜色上。
        var delta = b.h - a.h
        if delta > 0.5 { delta -= 1 } else if delta < -0.5 { delta += 1 }

        var hue = (a.h + delta * weight).truncatingRemainder(dividingBy: 1.0)
        if hue < 0 { hue += 1 }

        let sat = min(max(a.s + (b.s - a.s) * weight, 0.35), 1.0)
        let bri = min(max(a.b + (b.b - a.b) * weight, 0.35), 1.0)

        return color(hue: hue, sat: sat, bri: bri)
    }
}

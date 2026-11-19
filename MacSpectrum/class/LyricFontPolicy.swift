//
//  LyricFontPolicy.swift
//  MacSpectrum
//
//  按歌词的实际文字系统自动选字体：日语走明朝、俄语走 Georgia、其余保持现状苹方。
//  全部用 macOS 自带字体，不依赖任何外部字体文件。
//

import SwiftUI
import AppKit
import CoreText

/// 歌词的主导文字系统。判定只看字符，不猜语言。
enum LyricScript {
    /// 中日韩 + 拉丁：现状（苹方 rounded）
    case cjkLatin
    /// 含假名 → 日文明朝
    case japanese
    /// 含西里尔 → Georgia
    case cyrillic
}

enum LyricFontPolicy {

    /// 从一整首歌的歌词文本判主导文字系统。
    ///
    /// 判据是**占比**而不是"有没有"，而且要假名（或西里尔）比汉字还多才切。实测分布：
    /// - 真日语歌（含故意堆汉字的那种）假名占 CJK 字符的 0.68–0.75，远在一半之上
    /// - 中文歌里夹一句日文（"就像那句 好きだよ"）只有 0.10–0.14
    /// - 中日双语歌词本（翻译与原文交替）落在 0.3–0.5，汉字通常过半
    ///
    /// 选这个位置而不是宽松的 0.3，是因为两侧失效代价不对称：误切会把整首汉字拖进
    /// 明朝体，而明朝体缺简体字形（见下面 japanese 分支），上屏是一行里混两种笔体；
    /// 不误切则仅维持现状（苹方本身就带假名字形，不会 fallback）。所以取保守侧：
    /// **只对"主导文字系统是日语"的歌换字体**，混排一律不动。
    ///
    /// 汉字数量本身不参与"中日判断"——两边都用汉字，拿它区分不了中日；它只当分母。
    ///
    /// `>= 2` 这个下限是护栏，防的是一两个偶然字符（装饰、误录、GBK 误解码后乱码
    /// 里蹦出来的假名）单独触发切换；实践中占比这一关先拦住，轮不到它说话。
    static func detect(_ text: String) -> LyricScript {
        var kana = 0, han = 0, cyrillic = 0

        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x3040...0x309F).contains(v) ||       // 平假名
               (0x30A0...0x30FF).contains(v) { kana += 1 }  // 片假名（含长音符 30FC）
            else if (0x4E00...0x9FFF).contains(v) { han += 1 }          // 汉字
            else if (0x0400...0x04FF).contains(v) { cyrillic += 1 }     // 西里尔（含 Ё ё）
        }

        // 假名和西里尔合起来压过汉字，才认为这首歌的主体不是中文。
        // 纯日语/纯俄语歌里 han = 0，这一关天然通过。
        let majority = kana + cyrillic > han

        // 两种都成片出现时不该发生，真遇到（混排歌词）按假名优先：
        // 日语歌里夹俄文单词比俄语歌里夹假名常见得多。
        if kana >= 2, majority { return .japanese }
        if cyrillic >= 2, majority { return .cyrillic }
        return .cjkLatin
    }

    /// 取字号 `size` 的歌词字体。`emphasized` 对应歌词墙里的"当前唱到的那一行"。
    static func font(_ script: LyricScript, size: CGFloat, emphasized: Bool) -> Font {
        switch script {
        case .cjkLatin:
            return .system(size: size, weight: emphasized ? .bold : .medium, design: .rounded)

        case .japanese:
            // 切明朝体是审美选择，不是补 bug：实测苹方自己就带假名字形
            // （CTFontGetGlyphsForCharacters あ=true），渲染时也不会 cascade 到别的字族，
            // 所以混排场景退回苹方是无损的——这一点正是上面敢用"假名必须过半"这个
            // 保守判据的前提。
            //
            // 已知边界：明朝体（不管 MS PMincho 还是 Hiragino）都缺简体专用码位
            // （专 U+4E13 / 识 U+8BC6 / 颜 U+989C），遇到会掉到 STSongti-SC，一行里混两种衬线来源。
            // 两者覆盖逐字相同，所以选哪个不改变这个行为；真日文文本用的是日文新字体码位
            // （専 U+5C02 / 識 U+8B58 / 顔 U+9854），碰不到。
            //
            // 未唱行/当前行的拉开方式取决于字面：见 MinchoFace。
            switch mincho {
            case .external(let ps):
                // MS PMincho 只有一个面，emphasized 在这一档是**空操作**（实测 .bold() 墨水量零变化），
                // 当前行的突出完全由调用方的字号承担（歌词墙 28 vs 20）。
                return .custom(ps, size: size)
            case .hiragino:
                // Hiragino 有 W3/W6 两档，字重能拉得开（实测 24pt 墨水量 69787 → 73072）。
                return .custom(emphasized ? "HiraMinProN-W6" : "HiraMinProN-W3", size: size)
            }

        case .cyrillic:
            // Georgia 是 macOS 自带（/System/Library/Fonts/Supplemental/），西里尔全覆盖，
            // 而且是 Matthew Carter 专为俄语设计过的字形，不是从拉丁字形硬拼的。
            return .custom(emphasized ? "Georgia-Bold" : "Georgia", size: size)
        }
    }

    // MARK: - 明朝体字面选型

    /// 明朝体用哪个字面。整进程只解析一次（Swift 的 static 惰性初始化自带线程安全）。
    private static let mincho: MinchoFace = resolveMincho()

    private enum MinchoFace {
        /// 用户自己的 MS PMincho：单面字体，粗细拉不开，强调只能靠字号。
        case external(psName: String)
        /// 系统自带 Hiragino Mincho ProN：有 W3/W6 两档可用。
        case hiragino
    }

    /// 用户自己放的字体目录。本工程 `ENABLE_APP_SANDBOX = NO`，可以直接读。
    /// 路径与 App 里的 songs/lyrics 不同源（那在 Documents/spectrumplayer 下），这里取的是同一个基目录。
    ///
    /// nonisolated 是必需的：项目开了 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor，
    /// 而 `static let mincho` 的全局初始化器跑在 nonisolated 上下文，调 MainActor 方法会警告。
    /// 这几个函数只碰 FileManager 与 CoreText，不涉及任何 UI 状态，标 nonisolated 属实。
    private nonisolated static var externalFontsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/spectrumplayer/fonts")
    }

    /// 提前跑一次 mincho 解析。注册一个 9MB 的 ttf 有几十毫秒，
    /// 不该发生在第一首日文歌上屏的那一刻，所以 App 启动时调一下。
    static func prewarm() { _ = mincho }

    /// 解析顺序：系统字体里已有 → 从字体目录注册后取 → 都没有则回落 Hiragino。
    private nonisolated static func resolveMincho() -> MinchoFace {
        // ① 用户真把它装进系统字体了（拖进 ~/Library/Fonts 就会走到这里，不需注册）
        for name in ["MS-PMincho", "MS PMincho"] where NSFont(name: name, size: 12) != nil {
            return .external(psName: name)
        }

        // ② 从字体目录注册到本进程。用 `.process` 而不是 `.persistent`：
        //    不动用户的系统字体簿，App 退出即消失，文件不在就自然走回落分支。
        guard let files = try? FileManager.default.contentsOfDirectory(
                at: externalFontsDir, includingPropertiesForKeys: nil) else {
            return .hiragino
        }
        for url in files where ["ttf", "otf", "ttc"].contains(url.pathExtension.lowercased()) {
            // 先问文件自己有哪些面，只认明朝体：以后用户丢进来的别的字体不应该被当成日文字体用。
            guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  descs.contains(where: isMinchoFamily) else { continue }
            var error: Unmanaged<CFError>?
            guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else { continue }
            // 拿文件自报的 PostScript 名去取，不猜命名规则。
            for d in descs {
                guard let ps = CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String,
                      NSFont(name: ps, size: 12) != nil else { continue }
                return .external(psName: ps)
            }
        }
        return .hiragino
    }

    private nonisolated static func isMinchoFamily(_ d: CTFontDescriptor) -> Bool {
        let fam = (CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String ?? "").lowercased()
        return fam.contains("mincho")
    }
}

//
//  LyricView.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/6/10.
//

import SwiftUI

struct LyricView: View {
    @ObservedObject var lyricManager: LyricManager
    @ObservedObject var player: PlayerManager // 监听当前歌曲和播放进度
    @Binding var themeType: String
    var palette: PaletteManager
    
    /// 本首歌用哪套字体。歌词为空（没匹配到 LRC）时拿歌名去判，
    /// 这样日语歌的假名标题也不会退回苹方（标题短，占比判据在小样本上不稳，
    /// 但只有一个歌名时它已经是全部证据，判出来什么用什么）。
    private var script: LyricScript {
        lyricManager.lyrics.isEmpty
            ? LyricFontPolicy.detect(player.currentSong?.title ?? "")
            : lyricManager.script
    }
    
    var body: some View {
        VStack {
            if lyricManager.lyrics.isEmpty {
                // 🏖️ 防空洞兑底：没有歌词时显示歌名。左对齐跟歌词的竖轴对齐（同一左边距），
                // 否则有词/无词切歌时文字会左右跳。
                VStack(spacing: 12) {
                    Spacer()
                    Text(player.currentSong?.title ?? "未知曲目")
                        .font(LyricFontPolicy.font(script, size: 30, emphasized: true))
                        .foregroundColor(themeType == "black" ? .white : .black)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            } else {
                // 🌊 瀑布流歌词墙：整墙**靠左**（每行钉在同一条竖轴上，当前行锁定到视口垂直中央）。
                // 以前每行按自身宽度居中，换行时长短不一 → 整墙左右抖，跟 QQ 音乐那种左排版不一样。
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            // 🧠 顶部垫高：确保第一句歌词也能滚到窗口的正中间
                            Color.clear.frame(height: 200)
                            
                            ForEach(lyricManager.lyrics) { line in
                                let isCurrent = lyricManager.currentLineId == line.id
                                
                                Text(line.text)
                                // 🎨 当前唱到的词放大加粗，没唱到的字变小变淡。
                                // 🔤 字体交给 LyricFontPolicy：日语歌走明朝体（未唱行 W3 / 当前行 W6），
                                // 俄语歌走 Georgia，其余仍是原来的苹方 rounded。
                                    .font(LyricFontPolicy.font(script,
                                                                size: isCurrent ? 35 : 27,
                                                                emphasized: isCurrent))
                                // ✨ 高光联动：唱到的那一行亮起专辑强调色（已按主题反解对比度，灰白底上不会再发虚）；
                                // 黑主题未唱行：白 + 0.4；灰白主题底色提到近白后，用深灰而不是纯黑，减轻压迫感。
                                    .foregroundColor(isCurrent ? palette.bgPalette :
                                        (themeType == "black" ? .white.opacity(0.4) : Color(white: 0.38)))
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal, 20)
                                    .id(line.id) // 给每一行打上身份证，方便滚动定位
                            }
                            
                            // 底部垫高：确保最后一句也能滚到正中间
                            Color.clear.frame(height: 200)
                        }
                    }
                    // 🌫️ 上下渐隐：遮罩加在 ScrollView（视口）上，而不是里面的 VStack 上。
                    // 加在内容上的话渐隐带会跟歌词一起滚走，等于没加；加在视口上它才是钉死的“窗口框”。
                    .mask(alignment: .center) {
                        EdgeFadeMask(top: 104, bottom: 78)
                    }
                    // 🚀 跳行核心：只要唱到下一句，当前行锁定到视口中央。
                    .onChange(of: lyricManager.currentLineId) { _, _ in
                        centerCurrentLine(proxy, animated: true)
                    }
                    // 🔁 主题切换必须在这里补一刀：Cmd+T 会让 NowPlayingView.upperArea 换分支，
                    // 整棵歌词子树（含 ScrollView）被销毁重建，滚动位置从 0 重新开始，
                    // 而 currentLineId 一个字没变 → 上面那个 onChange 不会触发 → 歌词停在第一句，
                    // 非要等下一次换行才归位（用户报的就是这个）。
                    // 离屏探针实测：切分支前后 NSScrollView 是**不同实例**，originY 回 0，
                    // 而把当前行摆回正中需要 858pt；重建时同步 scrollTo 可以直接落位。
                    // 顺带也治好了「进页面时 currentLineId 已经就位、没有变化可监听」的同源问题。
                    .onAppear {
                        centerCurrentLine(proxy, animated: false)
                    }
                    // ⏱️ 手动偏移即时跟随：每次 timeOffset 变化，先按新偏移重算当前行，再滚动对齐。
                    // 与上面 onChange(of: currentTime) 同款同步调用，是已验证可靠的重算路径。
                    .onChange(of: lyricManager.timeOffset) { _, _ in
                        lyricManager.updateCurrentLine(currentTime: player.currentTime)
                        centerCurrentLine(proxy, animated: true)
                    }
                }
            }
        }
        // 切歌同步监听
        .onChange(of: player.currentSong?.id) { _, _ in
            // 只要 ID 变了，说明切歌了，我们直接通过 player 拿到最新的 title 塞进去！
            if let song = player.currentSong {
                lyricManager.loadLyric(for: song.title)
            }
        }
        // ⏱️ 高频毫秒进度监听（在大排灯的主计时器里轮询触发即可，或者直接绑定进度状态）
        .onChange(of: player.currentTime) { _, newTime in
            lyricManager.updateCurrentLine(currentTime: newTime)
        }
    }
    
    /// 把当前行摆到视口正中。`animated: false` 用在「视图刚被重建」这种场合——
    /// 那时从顶部滚过去看起来像是歌词自己掉下来了，而用户要的是它本来就该在那儿。
    private func centerCurrentLine(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let targetId = lyricManager.currentLineId else { return }
        if animated {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                proxy.scrollTo(targetId, anchor: .center)
            }
        } else {
            withAnimation(nil) {
                proxy.scrollTo(targetId, anchor: .center)
            }
        }
    }
}

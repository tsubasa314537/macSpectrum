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
    
    var body: some View {
        VStack {
            if lyricManager.lyrics.isEmpty {
                // 🏖️ 防空洞兑底：没有歌词时，居中干净利落地显示歌名
                VStack(spacing: 12) {
                    Spacer()
                    Text(player.currentSong?.title ?? "未知曲目")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(themeType == "black" ? .white : .black)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                // 🌊 瀑布流歌词墙：居中布局，当前行锁定到视口中央。
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 28) {
                            // 🧠 顶部垫高：确保第一句歌词也能滚到窗口的正中间
                            Color.clear.frame(height: 200)
                            
                            ForEach(lyricManager.lyrics) { line in
                                let isCurrent = lyricManager.currentLineId == line.id
                                
                                Text(line.text)
                                // 🎨 当前唱到的词放大加粗，没唱到的字变小变淡
                                    .font(.system(size: isCurrent ? 28 : 20, weight: isCurrent ? .bold : .medium, design: .rounded))
                                // ✨ 高光联动：唱到的那一行亮起专辑强调色（已按主题反解对比度，灰白底上不会再发虚）；
                                // 黑主题未唱行：白 + 0.4；灰白主题底色提到近白后，用深灰而不是纯黑，减轻压迫感。
                                    .foregroundColor(isCurrent ? palette.bgPalette :
                                        (themeType == "black" ? .white.opacity(0.4) : Color(white: 0.38)))
                                    .multilineTextAlignment(.center)
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
                    .onChange(of: lyricManager.currentLineId) { _, nextId in
                        if let targetId = nextId {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                proxy.scrollTo(targetId, anchor: .center)
                            }
                        }
                    }
                    // ⏱️ 手动偏移即时跟随：每次 timeOffset 变化，先按新偏移重算当前行，再滚动对齐。
                    // 与上面 onChange(of: currentTime) 同款同步调用，是已验证可靠的重算路径。
                    .onChange(of: lyricManager.timeOffset) { _, _ in
                        lyricManager.updateCurrentLine(currentTime: player.currentTime)
                        if let targetId = lyricManager.currentLineId {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                proxy.scrollTo(targetId, anchor: .center)
                            }
                        }
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
}

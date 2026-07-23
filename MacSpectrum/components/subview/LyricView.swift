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
                // 🏖️ 防空洞兜底：没有歌词时，干净利落地显示歌名和歌手
                VStack(spacing: 12) {
                    Spacer()
                    Text(player.currentSong?.title ?? "未知曲目")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(themeType == "black" ? .white : .black)
//                    Text(player.currentSong?.artist ?? "未知歌手")
//                        .font(.system(size: 15))
//                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                // 🌊 瀑布流歌词墙
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 24) {
                            // 🧠 顶部垫高：确保第一句歌词也能滚到窗口的正中间
                            Color.clear.frame(height: 180)
                            
                            ForEach(lyricManager.lyrics) { line in
                                let isCurrent = lyricManager.currentLineId == line.id
                                
                                Text(line.text)
                                // 🎨 大厂巧思：当前唱到的词放大加粗，没唱到的字变小变淡
                                    .font(.system(size: isCurrent ? 20 : 15, weight: isCurrent ? .bold : .medium, design: .rounded))
                                // ✨ 极其惊艳的高光联动：
                                // 唱到的那一行，直接亮起当前歌曲提取出来的专辑灵魂色！没唱到的根据主题黑白变淡！
                                    .foregroundColor(isCurrent ? palette.bgPalette : (themeType == "black" ? .white.opacity(0.4) : .black.opacity(0.4)))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                                    .scaleEffect(isCurrent ? 1.05 : 1.0) // 轻微膨胀呼吸感
//                                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isCurrent) // 极佳的弹性动画
                                    .id(line.id) // 给每一行打上身份证，方便爆破滚动
                            }
                            
                            // 底部垫高：确保最后一句也能滚到正中间
                            Color.clear.frame(height: 180)
                        }
                    }
                    // 🚀 【跳行核心核心】：只要唱到下一句，立刻丝滑追随滚动！
                    .onChange(of: lyricManager.currentLineId) { _, nextId in
                        if let targetId = nextId {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                // anchor: .center 的意思是让当前歌词雷打不动地保持在右侧视图的正中央！
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

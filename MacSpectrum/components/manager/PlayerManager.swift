//
//  PlayerManager.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/4/18.
//

import Foundation
import AVFoundation
import Combine
import MediaPlayer
import AppKit
import CoreAudio

class PlayerManager: ObservableObject {
    
    let songsURL: URL
    let lyricsURL: URL
    
    // 顺便把 albums 也动态化了
    var albumsURL: URL {
        songsURL.deletingLastPathComponent().appendingPathComponent("albums", isDirectory: true)
    }
    
    // ── 🎛️ 任务栏状态菜单控制中枢 ──────────────────────────────────
    @Published var karaoke: Bool = false
    @Published var isAutopilotMode: Bool = false
    @Published var standardTheme: Bool = false
    @Published var themeType: String = "black"
    
    //MARK: 播放引擎相关
    private var shuffledOrder: [Int] = []
    private var shufflePointer: Int = 0
    
    var beatDetector = OfflineAudioOnsetDetector()
    
    @Published var beats: [TimeInterval] = []
    
    @Published var nowAlbum = NSImage(named: "Albumdefault")
    @Published var spectrum = AudioManager()
    private var isManualStop = false
    
    let delayUnit = AVAudioUnitDelay()
    let engine = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    
    @Published var currentSong: Song?
    @Published var isPlaying: Bool = false
    
    //当前播放列表及当前位移
    @Published var currentPlaylist: [Song] = []
    @Published var currentIndex: Int = 0
    
    private var playToken = 0
    
//    private let albumsPath = "/Users/guopeng/Documents/spectrumplayer/albums"
    
//    var albumsPath: String
    
    @Published var albumImages: [NSImage] = []
    
    // 存储总时长，load 文件时赋值
    private(set) var totalDuration: Double = 0
    
    // 专门提供给前台歌词（onChange）和外部状态高频响应的 `@Published` 灵魂变量
    @Published var currentTime: Double = 0
    
    // 💾 用于在暂停时，死死锁住当前的播放进度，防止 lastRenderTime 变 nil 导致归零
    private var lastPausedTime: Double = 0
    
    // 实时计算当前节点进度的底层辅助属性
    private var nodeCurrentTime: Double {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
        else { return 0 }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }
    
    //进度条实时更新用定时器（提高频率到 0.1 秒，歌词滚动更丝滑）
    private var progressTimer: Timer?
    
    // play/resume 时启动
    func startProgressTimer() {
        stopProgressTimer() // 容错：先停旧的
        
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.isPlaying {
                let nextTime = self.currentTime + 0.1
                
                // 边界防护：不能让进度条冲出歌的总长度
                self.currentTime = min(nextTime, self.totalDuration)
                
                // 高频向系统及 BoringNotch 同步
                self.updateNowPlayingInfo()
            }
        }
    }
    
    // pause/stop 时停止
    func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    init(songsURL: URL, lyricsURL: URL) {
        
        self.songsURL = songsURL
        self.lyricsURL = lyricsURL
        
        setupAudioGraph()
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice, // 核心选择器：默认输出设备改变
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // 向系统注册一个“硬件监听钩子”
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            audioDeviceChangedListener, // 具体的极客监听回调
            Unmanaged.passUnretained(self).toOpaque() // 把当前的 PlayerManager 实例指针传过去
        )
        
        // 初始化时先自动对齐一次延迟
        updateDynamicDelay()
        
        setupGlobalRemoteCommandCenter()
    }
    
    // 🚀 【核心修复：多媒体总线无条件强占机制】
    func setupGlobalRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // 1. 强控【播放】
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.resume()
            }
            return .success
        }
        
        // 2. 强控【暂停】
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.pause()
            }
            return .success
        }
        
        // 🚀 3. 【合并指挥部】：把 播放/暂停 复合键（Toggle 物理按键）也强行接管过来！
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                if self.isPlaying {
                    self.pause()
                } else {
                    self.resume()
                }
            }
            return .success
        }
        
        // 4. 强控【上一曲】
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.previousTrack()
            }
            return .success
        }
        
        // 5. 强控【下一曲】
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] event in
            guard let self = self else { return .commandFailed }
            DispatchQueue.main.async {
                self.nextTrack()
            }
            return .success
        }
        
        // 6. 强控【进度条拖拽/跳转】（BoringNotch 和 系统控制中心 进度条解锁 key！）
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            
            let targetTime = positionEvent.positionTime
            print("🎛️ 收到 BoringNotch/系统指令：【进度条跳转至 \(targetTime) 秒】")
            
            DispatchQueue.main.async {
                // 🚀 调用您完美的 Seek 算法，带版本号防错，绝不卡死
                self.seek(to: targetTime)
            }
            
            return .success
        }
        
        print("🎛️ [macSpectrum 终极控制链] 系统总线、物理多媒体键、BoringNotch 全线大对齐！")
    }
    
    // 🚀 【铁腕状态同步】：确保每次引擎状态改变，瞬间打醒 BoringNotch
    func updateNowPlayingState() {
        if #available(macOS 10.12, iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        }
        // 联动触发您原有的元数据刷新
        updateNowPlayingInfo()
    }
    
    // 🚀 【核心跳转算法】：让歌曲瞬间瞬移到指定的秒数
    func seek(to time: Double) {
        guard let playerFile = audioFile else { return }
        let sampleRate = playerFile.processingFormat.sampleRate
        let targetFrame = Int64(time * sampleRate)
        let totalFrames = playerFile.length
        
        guard targetFrame < totalFrames else {
            nextTrack()
            return
        }
        
        let remainingFrames = AVAudioFrameCount(totalFrames - targetFrame)
        guard remainingFrames > 0 else { return }
        
        // 🚀 【核心解药 1】：在 stop 之前，先把版本戳加 1！
        // 这样一会儿系统 stop 误触发旧闭包时，旧闭包会因为版本对不上而瞬间失效！
        playToken += 1
        let currentToken = playToken // 锁死当前这次跳转的专属版本
        
        let wasPlaying = isPlaying
        playerNode.stop() // 👈 此时系统底层会疯狂误触发之前的闭包，但现在伤不到我们了！
        
        // 🚀 【核心解药 2】：重新喂给系统段落，并在闭包里写好“真·播放完毕”的逻辑
        playerNode.scheduleSegment(
            playerFile,
            startingFrame: targetFrame,
            frameCount: remainingFrames,
            at: nil
        ) { [weak self] in
            // 🎯 注意！这里是底层音频线程，绝对不能直接操作 UI 或调用会 stop 的核心方法
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // 🛑 门神拦截：如果 currentToken 已经跟最新的 self.playToken 对不上了
                // 说明这次闭包触发是由于用户点进度条“人为 stop”引起的伪触发，直接无视它！
                guard currentToken == self.playToken else {
                    print("⚠️ 拦截到系统的 Seek 伪触发现场，安全放行...")
                    return
                }
                
                // 🎵 只有版本号完全一致，说明这首歌是从您点的那一秒开始，顺理成章、真正放到了最后尽头！
                print("🎉 歌曲后续片段真正播放完毕，奉命自动切歌！")
                self.nextTrack()
            }
        }
        
        if wasPlaying {
            playerNode.play()
            self.currentTime = time
            self.updateNowPlayingInfo()
        }
    }
    
    private let audioDeviceChangedListener: AudioObjectPropertyListenerProc = { _, _, _, inClientData in
        guard let clientData = inClientData else { return noErr }
        
        // 把传过来的指针，安全地重新还原成咱们的 PlayerManager 实例
        let playerManager = Unmanaged<PlayerManager>.fromOpaque(clientData).takeUnretainedValue()
        
//        print("📢 CoreAudio 探测到 Mac 全局音频设备发生物理切换！")
        
        // 回到主线程，让引擎重新绑定并动态刷新时间
        DispatchQueue.main.async {
            playerManager.handleAudioRouteChanged()
        }
        
        return noErr
    }
    
    private func setupAudioGraph() {
        engine.attach(playerNode)
        engine.attach(delayUnit)
        
        delayUnit.wetDryMix = 100
        delayUnit.feedback = 0
        delayUnit.lowPassCutoff = 20000
        
        // 🚀 【核心解药】：强行让 AVAudioEngine 认主系统当前的默认设备（比如 AirPods）
        let outputUnit = engine.outputNode.audioUnit
        
        // A. 声明一个变量准备接收 Mac 默认输出设备的硬件 ID
        var defaultDeviceID = AudioDeviceID(0)
        var propertySize = uint32(MemoryLayout<AudioDeviceID>.size)
        
        // B. 寻路指针：指向 macOS 系统默认输出设备的硬件地址
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain // 2026年现代系统标准用法
        )
        
        // C. 从 CoreAudio 系统中把当前的真实硬件 ID（比如 AirPods 的硬件特征码）捞出来
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultDeviceID
        )
        
        // D. 如果成功拿到了硬件 ID，直接强行注入给 AVAudioEngine 的输出节点！
        if status == noErr && defaultDeviceID != 0 {
            AudioUnitSetProperty(
                outputUnit!,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &defaultDeviceID,
                uint32(MemoryLayout<AudioDeviceID>.size)
            )
        }
        
        // 🎛️ 之后的串联和分流管道保持完全不变
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)
        spectrum.installTap(on: engine.mainMixerNode)
        
        engine.connect(engine.mainMixerNode, to: delayUnit, format: nil)
        engine.connect(delayUnit, to: engine.outputNode, format: nil)
        
        try? engine.start()
    }
    
    // 🎧 当收到内核硬件变更信号时的处理函数
    @objc func handleAudioRouteChanged() {
        // 🚀 【核心微调 1】：不要去 stop 引擎，也不要重新跑 setupAudioGraph！
        // 我们给系统更宽裕的 1.2 秒时间，让蓝牙或者扬声器的硬件底层通道彻底“交接班”完毕。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self else { return }
            
//            print("🔄 硬件交接班完毕，雷达开始扫描最新物理参数...")
            // 🎯 直接去抓已经交接完毕的当前硬件真实延迟，拒绝抢跑！
            self.updateDynamicDelay()
        }
    }
    
    // 🔍 动态计算并更新硬件延迟的核心算法（反向平衡流）
    private func updateDynamicDelay() {
        // 直接读取真实、正确的 outputNode 表现延迟（扬声器返回 0.001s，AirPods 返回 0.160s）
        let hardwareLatency = engine.outputNode.presentationLatency
        
        // 🎯 【拨乱反正的核心公式】：
        // 我们的目标是让“软件延迟 + 硬件延迟 + 软件沙漏扣留时间 = 一个恒定的同步完美点”
        // 经过您之前的实测，当总延迟顶到 180ms（0.180秒）左右时，人眼和人耳最舒服。
        
        let targetTotalDelay: Double = 0.198 // 👈 黄金同步靶向总时间
        let softwareBaseOffset: Double = 0.023 // 您的软件渲染基础开销
        
        // ⚖️ 关键在此：用总目标，减去软件开销，再减去硬件已经自带的延迟！
        // 设备硬件自己延迟得越多（如 AirPods 160ms），我们的软件沙漏就应该扣留得越少（183 - 23 - 160 = 0ms，开闸放水！）
        // 设备硬件自己速度极快（如 扬声器 1ms），我们的软件沙漏就得多扣留一会儿（183 - 23 - 1 = 159ms，憋住声音！）
        let calculatedDelay = targetTotalDelay - softwareBaseOffset - hardwareLatency
        
        // 限幅保护，防止算出负数
        let finalDelay = max(0.001, min(calculatedDelay, 0.25))
        
        // 🎯 一键动态刷新物理沙漏的时间！
        self.delayUnit.delayTime = finalDelay
        
//        print("📊 [硬件雷达精确微调] -> 当前硬件自带延迟: \(String(format: "%.3f", hardwareLatency))s | 软件沙漏奉命扣留: \(String(format: "%.3f", finalDelay))s")
    }

    // MARK: - 加载歌单
    func loadPlaylist(songs: [Song]) {
        currentPlaylist = songs
        currentIndex = 0
        generateShuffleOrder()
    }
    
    // MARK: - 生成随机序列
    private func generateShuffleOrder() {
        shuffledOrder = Array(0..<currentPlaylist.count).shuffled()
        shufflePointer = 0
    }
    
    // MARK: - 播放控制
    func nextTrack() {
        guard !shuffledOrder.isEmpty else { return }
//        beatDetector.cancelCurrentAnalysis()
        shufflePointer += 1
        if shufflePointer >= shuffledOrder.count {
            generateShuffleOrder()
        }
        currentIndex = shuffledOrder[shufflePointer]
        playCurrent()
    }
    
    func playCurrent() {
        
        guard currentPlaylist.indices.contains(currentIndex) else { return }
        
        let song = currentPlaylist[currentIndex]

        play(song: song)
    }
    
    func previousTrack() {
        shufflePointer -= 1
        if shufflePointer < 0 {
            shufflePointer = 0
        } else {
            currentIndex = shuffledOrder[shufflePointer]
            playCurrent()
        }
    }
    
    func play(song: Song) {
        stop()
        
        beatDetector.analyzeSongFile(fileURL: song.url){ [weak self] kicks in
            self?.beats = kicks
            
            if let currentBeats = self?.beats, let pNode = self?.playerNode {
                self?.spectrum.setDrumMap(currentBeats,  for: pNode)
            }
        }
        
        do {
            audioFile = try AVAudioFile(forReading: song.url)
            guard let file = audioFile else { return }
            totalDuration = Double(file.length) / file.processingFormat.sampleRate
            
            // 🚀 新歌打底：时间绝对归零
            self.currentTime = 0
            
            playToken += 1
            let currentToken = playToken
          
            isManualStop = false
            playerNode.scheduleFile(file, at: nil) { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    // 门神校验：如果中途被切歌了或者被 Seek 了，这里就不触发 nextTrack
                    guard currentToken == self.playToken else { return }
                    self.nextTrack()
                }
            }
            
            playerNode.play()
            currentSong = song
            isPlaying = true
            albumImages = findAlbumImages(for: song)
            
            // 🏁 启动硬核物理时钟
            startProgressTimer()
            self.updateNowPlayingState()
            
        } catch {
            print("Play error: \(error)")
        }
    }
    
    func pause() {
        // 🚀 暂停时：不要去修改或累加 currentTime，让它稳稳钉在当前断点！
        playerNode.pause()
        isPlaying = false
        
        // 🛑 掐断定时器，时间线瞬间在断点被彻底冰封！
        stopProgressTimer()
        
        // 广播给系统：进度锁死，速率归0，BoringNotch 紧急闭锁刹车！
        updateNowPlayingInfo()
        self.updateNowPlayingState()
    }
    
    func resume() {
        playerNode.play()
        isPlaying = true
        
        // 🏁 复活时：重新拉起时钟，由于 currentTime 停在断点，它会自动从断点（如 0:39）以 +0.1 秒继续跑！
        startProgressTimer()
        self.updateNowPlayingState()
    }
    
    func stop() {
        isManualStop = true
        stopProgressTimer()
        
        playerNode.stop()
        engine.reset()
        isPlaying = false
        
        // 彻底清洗归零
        self.currentTime = 0
        updateNowPlayingInfo()
    }
    
    func updateNowPlayingInfo() {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle]                    = currentSong?.title ?? ""
        info[MPMediaItemPropertyPlaybackDuration]         = totalDuration
        
        //专辑图片（控制中心和boringnotch用）
        if let img = albumImages.count != 0 ? albumImages.first : NSImage(named: "Albumdefault") {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in
                return img
            }
        }

        // 不再发会变成0的底层计算属性，而是代理 currentTime
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate]        = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo   = info
    }
    
    // 根据当前歌曲查找匹配的专辑图列表
    func findAlbumImages(for song: Song) -> [NSImage] {
        let filename = song.title
        let parts = filename.components(separatedBy: " - ")
        guard parts.count >= 2 else { return [] }
        
        let artist   = parts[0].trimmingCharacters(in: .whitespaces)
        let songName = parts[1].trimmingCharacters(in: .whitespaces)
        
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: albumsURL.path) else { return [] }
        
        let artistFiles = files.filter {
            $0.lowercased().hasPrefix(artist.lowercased()) &&
            $0.lowercased().hasSuffix(".jpg")
        }
        
        //来自歌词的专辑名
        let album = song.lyric.components(separatedBy: "-").last?.replacingOccurrences(
            of: "_qm",
            with: ""
        ) ?? ""
        
        //artistFiles是当前歌手的所有专辑图片数组
        //artist是当前歌手
        //albumName是当前歌曲所在专辑
        for file in artistFiles {
            let trimmed = file.dropFirst(artist.count + 1)
            let albumName = trimmed.replacingOccurrences(of: "_4.jpg", with: "")
                .replacingOccurrences(of: " ", with: "")
            //如果能唯一确定，则专辑数组只返回一张
            if(albumName.lowercased().contains(album)) {
                if let image = NSImage(contentsOfFile: albumsURL.path + "/" + file) {
                    return [image]
                }
                //如果歌词文件不存在，但是选定的歌曲名中就是专辑名则专辑数组也只返回对应的一张
            } else if songName.replacingOccurrences(of: " ", with: "")
                .lowercased().contains(albumName.lowercased()) {
                if let image = NSImage(contentsOfFile: albumsURL.path + "/" + file) {
                    return [image]
                }
            }
        }
        
        //匹配失败，返回该歌手全部专辑图
        return artistFiles.compactMap {
            NSImage(contentsOfFile: albumsURL.path + "/" + $0)
        }
    }
}

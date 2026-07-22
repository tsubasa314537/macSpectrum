import Foundation
import AVFoundation
import Accelerate
import Combine
import CoreAudio

class AudioManager: ObservableObject {
    
    private let fftSize   = 1024
    private let bandCount = 32
    private var fftSetup: FFTSetup?
    
    private var beatsMap: [TimeInterval] = []
    private var snaresMap: [TimeInterval] = []
    private var currentKickIndex: Int = 0
    private var lastFrameSeconds: Double = 0.0
    
    private var playerNode: AVAudioPlayerNode?
    
    // ── 双声道各自维护独立的环形缓冲区和峰值 ──────────────────────
    
    private var totalSamples: Int = 0
    private var ringBufferL: [Float]
    private var ringBufferR: [Float]
    private var prevBands: [Float]
    private var writeIndex: Int = 0
    
    private var peakL: Float = 1e-6
    private var peakR: Float = 1e-6
    private let peakDecay: Float = 0.998
    
    private var currentSampleRate: Float = 44100
    
    // ── dB 映射参数 ───────────────────────────────────────────────
    private let noiseFloorDB: Float = -60.0
    private let ceilingDB:    Float = -6.0
    
    private var energies: [Float]
    private var result: [Float]
    
    // ── Attack / Release ─────────────────────────────────────────
    private let attack:  Float = 1.2
    private let release: Float = 0.2
    //基准值：1.4/0.3
    
    // ── 输出：左右各 48 个频段 ────────────────────────────────────
    @Published var leftMagnitudes:  [Float]
    @Published var rightMagnitudes: [Float]
    
    // 💾 【新增消噪沙盒】：用来死死记住上一帧光柱停留在屏幕上的真实渲染高度
    private var lastLeftRender:  [Float]
    private var lastRightRender: [Float]
    
    // ── 🚀 【新增：节拍触发器专用状态机】 ──────────────────────
    private var prevTriggerFeature: Float = 0.0
    private var envelopeState: Float = 0.0
    private var onsetEnvelope: Float = 0.0
    private var frameIndex: Int = 0
    private var lastPeakFrame: Int = 0
    
    var isTriggered: Bool = false
    var triggerValue: Float = 0.0 // 👈 这个值可以传给 UI 驱动全局闪烁或鼓点爆炸动效
    var tunnelRaw: Float = 0.0
    
    private var lastRealtimeTriggerTime: Double = 0.0
    private let realtimeCooldown: Double = 0.08       // 80毫秒冷却，防抖去尾巴
    private var previousRealtimeDB: Float = -120.0
    
    init() {
        let log2n = vDSP_Length(log2(Float(fftSize)))
        result   = [Float](repeating: 0, count: bandCount)
        energies = [Float](repeating: 0, count: bandCount)
        
        leftMagnitudes = Array(repeating: 0, count: bandCount)
        rightMagnitudes = Array(repeating: 0, count: bandCount)
        
        lastLeftRender = Array(repeating: 0, count: bandCount)
        lastRightRender = Array(repeating: 0, count: bandCount)
        
        //初始化时一次分配
        ringBufferL = Array(repeating: 0, count: fftSize)
        ringBufferR = Array(repeating: 0, count: fftSize)
        prevBands = Array(repeating: 0, count: fftSize)
        
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }
    
    func setDrumMap(_ beats: [TimeInterval], for node: AVAudioPlayerNode) {
        self.beatsMap = beats
        self.currentKickIndex = 0
        self.playerNode = node
    }
    
    func installTap(on mixer: AVAudioMixerNode) {
        
        let format = mixer.outputFormat(forBus: 0)
        
        mixer.removeTap(onBus: 0)
        
        mixer.installTap(onBus: 0,
                         //在一个fft窗口周期内回调4次
                         bufferSize: AVAudioFrameCount(fftSize / 4),
                         format: format) { [weak self] buffer, _ in
            self?.processAudio(buffer: buffer,
                               channelCount: Int(format.channelCount))
        }
    }
    
    // MARK: - 🚀 节拍/起音检测特工组 (Onset Detection)
    // 1. 特征提取：用硬件加速算 RMS 均方根
    private func computeTriggerFeature(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var rms: Float = 0
        // 🎯 使用 Apple 矢量数学加速，比 for 循环快几倍，专抓突变
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }
    
    // 2. 状态机更新与峰值判定
    private func updateOnsetEnvelope(feature: Float) {
        frameIndex += 1
        
        // 🎯 算出一阶差分（Flux）：只有能量【增加】时才算，人声拉长音减少时为 0
        let flux = max(0, feature - prevTriggerFeature)
        prevTriggerFeature = feature
        
        // 🎯 一阶低通滤波器构建自适应动态包络
        let alpha: Float = 0.85
        envelopeState = alpha * envelopeState + (1 - alpha) * flux
        onsetEnvelope = envelopeState
        
        let isPeak = detectPeak(current: flux) // 👉 注意：通常用当前的 flux 去跟包络线比，比直接用 envelope 更好
        
        if isPeak {
            triggerValue = 1.0
            isTriggered = true
            lastPeakFrame = frameIndex
        } else {
            let framesSincePeak = frameIndex - lastPeakFrame
            if framesSincePeak > 2 {
                triggerValue *= 0.88 // 🎯 节拍触发后的快速卸力阻尼
                if triggerValue < 0.02 {
                    triggerValue = 0
                    isTriggered = false
                }
            }
        }
    }
    
    // 3. 动态阈值防抖拦截
    private func detectPeak(current: Float) -> Bool {
        let threshold: Float = 0.02 // 🎯 起跳阈值，如果放电音《Bad Romance》可以适当调小或调大
        guard current > threshold else { return false }
        
        // 防抖：前后两发极限快鼓之间至少隔 3 帧（在 23ms 回调下约为 70 毫秒，完美对应极限快鼓连打）
        guard frameIndex - lastPeakFrame > 3 else { return false }
        
        // 自适应判定：当前的变化率必须大于整体平均包络的某个比例
        return current > onsetEnvelope * 0.95
    }
    
    // MARK: - 音频处理（回调线程）
    private func processAudio(buffer: AVAudioPCMBuffer, channelCount: Int) {
        guard let data = buffer.floatChannelData else { return }
        
        let frameCount = Int(buffer.frameLength)
        currentSampleRate = Float(buffer.format.sampleRate)
        
        for i in 0..<frameCount {
            ringBufferL[writeIndex] = data[0][i]
            ringBufferR[writeIndex] = channelCount >= 2 ? data[1][i] : data[0][i]
            writeIndex = (writeIndex + 1) % fftSize
        }
        
        totalSamples += frameCount
        if totalSamples < fftSize { return }
        
        var samplesL = [Float](repeating: 0, count: fftSize)
        var samplesR = [Float](repeating: 0, count: fftSize)
        let tailCount = fftSize - writeIndex
        samplesL[0..<tailCount] = ringBufferL[writeIndex..<fftSize]
        samplesR[0..<tailCount] = ringBufferR[writeIndex..<fftSize]
        samplesL[tailCount..<fftSize] = ringBufferL[0..<writeIndex]
        samplesR[tailCount..<fftSize] = ringBufferR[0..<writeIndex]
        
        let magsL = computeFFT(samples: samplesL)
        let magsR = computeFFT(samples: samplesR)
        
        let prevL = leftMagnitudes
        let prevR = rightMagnitudes
        
        // ── 🚀 接入实时时域暴力大鼓雷达（直接利用 256 滑动窗口） ──────────────────
        let triggerSamplesSize = 256
        var isRealtimeKickTriggered = false
        
        if frameCount >= triggerSamplesSize {
            // 1. 抓取这 256 个时域点，混合左右声道
            var triggerSamples = [Float](repeating: 0, count: triggerSamplesSize)
            let startOffset = frameCount - triggerSamplesSize
            for i in 0..<triggerSamplesSize {
                let sampleL = data[0][startOffset + i]
                let sampleR = channelCount >= 2 ? data[1][startOffset + i] : sampleL
                triggerSamples[i] = max(abs(sampleL), abs(sampleR)) // 🎯 暴力取绝对值最大值
            }
            
            // 2. 用硬件加速算时域 RMS 物理分贝
            var rmsValue: Float = 0.0
            vDSP_rmsqv(triggerSamples, 1, &rmsValue, vDSP_Length(triggerSamplesSize))
            let currentDB = 20.0 * log10(max(rmsValue, 1e-6))
            
            // 3. 实时绝对值判定（-5.0dB 绝对真理，配合 80ms 冷却去噪）
            let deltaDB = currentDB - previousRealtimeDB
            
            // 🎯 老爷子，这里就是您刚才测出来的黄金手感参数！
            if currentDB >= -6.0/* && deltaDB > 0.0*/ {
                print("***********IN***************")
                // 获取当前真实的播放时间
                var currentSeconds: Double = 0.0
                if let node = playerNode, node.isPlaying,
                   let nodeTime = node.lastRenderTime,
                   let playerTime = node.playerTime(forNodeTime: nodeTime) {
                    currentSeconds = Double(playerTime.sampleTime) / playerTime.sampleRate
                }
                
                // 冷却时间判定
                if currentSeconds - lastRealtimeTriggerTime >= realtimeCooldown {
                    isRealtimeKickTriggered = true
                    lastRealtimeTriggerTime = currentSeconds
                }
            }
            previousRealtimeDB = currentDB
            
            // 4. 兼容保留原本的 Onset 状态机（防止 UI 的其他联动断掉）
            let feature = computeTriggerFeature(samples: triggerSamples)
            updateOnsetEnvelope(feature: feature)
        }
        
        // 📥 【双剑合一】：只要离线子弹触发了，或者我们实时暴力雷达抓到了，都算触发！
        let offlineTriggered = triggered()
        let finalTriggered = offlineTriggered || isRealtimeKickTriggered
        
        let rawBandsL = computeBands(
            rawMags: magsL,
            previous: prevL,
            peak: &peakL,
            triggered: finalTriggered
        )
        let rawBandsR = computeBands(
            rawMags: magsR,
            previous: prevR,
            peak: &peakR,
            triggered: finalTriggered
        )
        
        // 📥 此时安全地在后台捞出刚刚算好的触发值
        let currentTrigger = self.triggerValue
        //        let triggered = triggered()
        //        let rawBandsL = computeBands(
        //            rawMags: magsL,
        //            previous: prevL,
        //            peak: &peakL,
        //            triggered: triggered
        //        )
        //        let rawBandsR = computeBands(
        //            rawMags: magsR,
        //            previous: prevR,
        //            peak: &peakR,
        //            triggered: triggered
        //        )
        
        
        lastLeftRender  = rawBandsL
        lastRightRender = rawBandsR
        
        // ── 🚀 统一打包派发给主线程 ──────────────────────────────────────────
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // 所有的 @Published 变量在同一条主线程流水线上同时赋值，警告彻底消失！
            self.leftMagnitudes = lastLeftRender
            self.rightMagnitudes = lastRightRender
            self.triggerValue = currentTrigger
            self.isTriggered = (currentTrigger > 0.0)
        }
    }
    
    // MARK: - FFT
    
    private func computeFFT(samples: [Float]) -> [Float] {
        guard let setup = fftSetup else { return [] }
        
        let halfSize = fftSize / 2
        let log2n    = vDSP_Length(log2(Float(fftSize)))
        
        // Hann 窗
        var windowed = [Float](repeating: 0, count: fftSize)
        var window   = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
        
        var real  = [Float](repeating: 0, count: halfSize)
        var imag  = [Float](repeating: 0, count: halfSize)
        var split = DSPSplitComplex(realp: &real, imagp: &imag)
        
        windowed.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) {
                vDSP_ctoz($0, 2, &split, 1, vDSP_Length(halfSize))
            }
        }
        
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        
        var mags: [Float] = [Float](repeating: 0, count: halfSize)
        vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(halfSize))
        
        var scale = 1.0 / Float(fftSize)
        vDSP_vsmul(mags, 1, &scale, &mags, 1, vDSP_Length(halfSize))
        
        return mags
    }
    
    private func triggered() -> Bool {
        // ── 🚀 【降维打击核心判定】 ──────────────────────────────────
        var isAITriggeredNow = false
        
        if !beatsMap.isEmpty, currentKickIndex < beatsMap.count,
           let node = playerNode, node.isPlaying {
            
            // 在 computeBands 判定前注入：
            if let nodeTime = node.lastRenderTime,
               let playerTime = node.playerTime(forNodeTime: nodeTime) {
                let currentSeconds = Double(playerTime.sampleTime) / playerTime.sampleRate
                
                // ── 🚨 【黄金补丁】：侦测 boringnotch 滚动条拖拽 ──────────────────────────────────
                if abs(currentSeconds - lastFrameSeconds) > 0.5 {
                    // 🏃‍♂️ 发现用户拉进度条了！不管拉向哪里，立刻用二分查找法重置弹夹光标！
                    // 找到第一个时间大于当前播放时间的子弹索引
                    if let newIndex = beatsMap.firstIndex(where: { $0 >= currentSeconds }) {
                        currentKickIndex = newIndex
                        //                        print("🔄 [滚动条联动] 发现进度条跳跃，弹夹光标紧急重置为: \(newIndex)")
                    } else {
                        currentKickIndex = beatsMap.count // 如果拽到了歌尾，光标直接推满
                    }
                }
                lastFrameSeconds = currentSeconds // 🎯 刷新备忘录
                
                // ── 🥷 重新焊装的超级子弹精准雷达大闸 ──────────────────────────────────
                // 每次实时进来，我们都用当前时间 currentSeconds 去弹夹库里校对
                if currentKickIndex < beatsMap.count {
                    let targetKickTime = beatsMap[currentKickIndex]
                    
                    // 🎯 黄金捕获窗口：只要当前音频播放的时间，已经进入到鼓点前后 35 毫秒的范围内
                    // 这代表鼓点正在发生，或者即将发生，立刻无延时拦截点火！
                    if abs(currentSeconds - targetKickTime) <= 0.035 {
                        isAITriggeredNow = true
                        //                        print("currentKickIndex=====\(currentKickIndex)")
                        // 核心：点火成功后，立刻利落地把这颗子弹弹出弹夹，指针进 1
                        currentKickIndex += 1
                    }
                    // 🎯 防卡死大闸：如果播放时间已经远远甩开（超过了 35 毫秒）这颗子弹，说明这颗子弹错过了
                    // 必须立刻把它扔掉，让指针往前走，去等待下一颗真鼓点子弹，防止弹夹卡死在原地
                    else if currentSeconds > targetKickTime + 0.035 {
                        currentKickIndex += 1
                    }
                }
            }
        }
        
        
        return isAITriggeredNow
    }
    
    // MARK: - 频段计算
    private func computeBands(rawMags: [Float], previous: [Float], peak: inout Float, triggered: Bool) -> [Float] {
        let minFreq: Float = 45
        let maxFreq: Float = 5500
        
        peak *= peakDecay
        //        var framePeak: Float = 0
        
        for i in 0..<bandCount {
            // 🚀 这里自动调用全新的 Mel 算法，分出来的 b1, b2 绝对丝滑、独立
            let (b1, b2) = bins(band: i, minFreq: minFreq, maxFreq: maxFreq, sr: currentSampleRate)
            let energy = computeEnergy(from: b1, to: b2, in: rawMags)
            energies[i] = energy
            
            peak = max(peak, energies[i])
            //            if framePeak > peak {
            //                peak = peak * 0.98 + framePeak * 0.02
            //            }
            
            let normalized = energy / max(peak, 1e-10)
            let dB         = log2(max(normalized, 1e-10)) * 3.0103
            let mapped     = (dB - noiseFloorDB) / (ceilingDB - noiseFloorDB)
            let raw        = min(max(mapped, 0), 1)
            
            //双声道共享此raw值，取的是这一帧的两个声道谁最大
            tunnelRaw = max(raw, tunnelRaw)
            
            // 🥁 1. 鼓点中频注入：11 ~ 25 柱（从左往右顺滑阶梯下滑）
//            if triggered && (i >= 5/*11 && i <= 25*/) {
//                let relativeIndex = Float(i - 5)
//                let cheatValue = 0.95 - relativeIndex * 0.04  // 🎯 起点 0.95，终点 0.39
//                tunnelRaw = tunnelRaw * 0.65 + cheatValue * 0.35
                //                raw = cheatValue
//            }
            
            // 🎛️ 2. 镲片高频注入：26 ~ 34 柱（以30柱为中心的对称伞状小山包）
//            if triggered && (i >= 26 && i <= 34) {
//                let distanceToCenter = abs(Float(i - 30))
//                let cheatValue = 0.90 - distanceToCenter * 0.08 // 🎯 中心 0.90，边缘 0.58
//                tunnelRaw = tunnelRaw * 0.7 + cheatValue * 0.3
                //                raw = cheatValue
//            }
            
            var smoothed: Float = 0.0
            
            let prev = previous[i]
            
            if i >= 4 {
                if triggered {
                    // 🚀 鼓点来了：如果原本音乐的 raw 已经比 prev 还要高（人声稳定高位），那就尊重人声
                    // 否则，才用我们的混合公式强行把柱子踢上去！
                    let baseline = max(raw, tunnelRaw)
                    smoothed = baseline > prev
                    ? prev * 0.4 + baseline * 0.6  // 稍微加大一点现帧权重，让爬坡更凌厉
                    : prev * 0.7 + baseline * 0.3 // 人声在高位时，绝对不准它触发“暴跌”，保持稳定
                } else {
                    // 🚀 鼓点走了（普通音乐状态）：
                    if raw > prev {
                        // 爬坡走常规的 attack
                        smoothed = prev * (1.0 - attack) + raw * attack
                    } else {
                        // 🎯 核心保护补丁：如果当前是人声持续高位（raw很大），即使 prev 很高，也不允许它触发急速下砸
                        // 我们用一个自适应释放：如果 raw 依然维持在高位（比如 > 0.6），就用极其温柔的常规 release 维持住！
                        if raw > 0.7 {
                            smoothed = prev * release + raw * (1.0 - release)
                        } else {
                            // 只有当音乐真正进入低谷、要卸力时，才允许它快速自由落体
                            smoothed = prev * 0.15 + raw * 0.85
                        }
                    }
                }
            } else {
                // 0 ~ 3 柱极低频走常规丝滑路线
                smoothed = raw > prev
                ? prev * (1.0 - attack) + raw * attack
                : prev * release + raw * (1.0 - release)
            }
            
            tunnelRaw = 0
            result[i] = smoothed
        }
        
        // ── 🎛️ 参谋长推荐：高频阻尼防爆网（26 ~ 34柱） ──────────────────
        for p in 26...31 {
            // 🎯 计算当前柱子距离最远端的深度
            // p=26 时 alpha 约 0.70（给乐器留点脆劲）
            // p=34 时 alpha 约 0.45（给极端高频齿音加上重沙包，允许它跳，但必须极其丝滑）
            let progress = Float(p - 26) / 8.0 // 0.0 ~ 1.0
            let currentWeight = 0.70 - progress * 0.25 // 0.70 下降到 0.45
            let prevWeight = 1.0 - currentWeight
            
            result[p] = result[p] * currentWeight + prevBands[p] * prevWeight
        }
        
        // 横向邻居平滑
        var spatialSmoothed = result
        for i in 1..<(bandCount - 1) {
            spatialSmoothed[i] = result[i-1] * 0.15 + result[i] * 0.7 + result[i+1] * 0.15
        }
        spatialSmoothed[0] = result[0] * 0.7 + result[1] * 0.3
        spatialSmoothed[bandCount - 1] = result[bandCount - 1] * 0.3 + result[bandCount - 2] * 0.7
        
        prevBands = spatialSmoothed
        
        return spatialSmoothed
    }
    
    // MARK: - 🚀 升级版：纯正 Mel 声学刻度频段划分（彻底解决低频全抬、重叠问题）
    private func bins(band: Int, minFreq: Float, maxFreq: Float, sr: Float) -> (Int, Int) {
        // 1. 将物理频率转化为 Mel 听觉频率
        let minMel = hzToMel(minFreq)
        let maxMel = hzToMel(maxFreq)
        
        // 2. 在 Mel 空间里进行绝对均匀、连续的等长切片
        let melStart = minMel + (maxMel - minMel) * (Float(band) / Float(bandCount))
        let melEnd   = minMel + (maxMel - minMel) * (Float(band + 1) / Float(bandCount))
        
        // 3. 将 Mel 切片完美还原回物理 Hz 频率
        let f1 = melToHz(melStart)
        let f2 = melToHz(melEnd)
        
        return (freqToBin(f1, sr: sr), freqToBin(f2, sr: sr))
    }
    
    // 🎼 Hz 转 Mel 经典声学公式
    private func hzToMel(_ hz: Float) -> Float {
        return 1127.0 * log(1.0 + hz / 700.0)
    }
    
    // 🎼 Mel 转 Hz 还原公式
    private func melToHz(_ mel: Float) -> Float {
        return 700.0 * (exp(mel / 1127.0) - 1.0)
    }
    
    private func freqToBin(_ freq: Float, sr: Float) -> Int {
        let ratio = freq / (sr / 2)
        // 向上取整，并确保至少占据一个物理 bin 窗口，防止低频重叠死区
        return min(max(Int(ceil(ratio * Float(fftSize / 2))), 0), fftSize / 2 - 1)
    }
    
    private func computeEnergy(from start: Int, to end: Int, in mags: [Float]) -> Float {
        let s = max(0, start)
        let e = min(end, mags.count - 1)
        if e <= s { return mags[s] }
        
        var sum: Float = 0
        for i in s...e {
            sum += mags[i]
        }
        
        return sum / Float(e - s + 1)
    }
}

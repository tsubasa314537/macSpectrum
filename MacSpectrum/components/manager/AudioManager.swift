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
    private let peakDecay: Float = 0.9995
    
    private var currentSampleRate: Float = 44100
    
    // ── dB 映射参数 ───────────────────────────────────────────────
    private let noiseFloorDB: Float = -60.0
    private let ceilingDB:    Float = -6.0
    
    private var energies: [Float]
    private var result: [Float]
    
    // ── Attack / Release ─────────────────────────────────────────
    private let attack:  Float = 0.8
    private let release: Float = 0.2
    //基准值：1.4/0.3
    
    // ── 输出：左右各 32 个频段 ────────────────────────────────────
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
    
    func installTap(on mixer: AVAudioMixerNode) {
        
        let format = mixer.outputFormat(forBus: 0)
        
        mixer.removeTap(onBus: 0)
        
        mixer.installTap(onBus: 0,
                         //在一个fft窗口周期内回调1次
                         bufferSize: AVAudioFrameCount(fftSize / 2),
                         format: format) { [weak self] buffer, _ in
            self?.processAudio(buffer: buffer,
                               channelCount: Int(format.channelCount))
        }
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
        
        let rawBandsL = computeBands(
            rawMags: magsL,
            previous: prevL,
            peak: &peakL
        )
        let rawBandsR = computeBands(
            rawMags: magsR,
            previous: prevR,
            peak: &peakR
        )
        
        lastLeftRender  = rawBandsL
        lastRightRender = rawBandsR
        
        // ── 统一打包派发给主线程 ──────────────────────────────────────────
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.leftMagnitudes = lastLeftRender
            self.rightMagnitudes = lastRightRender
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
    
    // MARK: - 频段计算
    private func computeBands(rawMags: [Float], previous: [Float], peak: inout Float) -> [Float] {
        let minFreq: Float = 45
        let maxFreq: Float = 5500
        
        peak *= peakDecay
        
        for i in 0..<bandCount {
            // 🚀 调用全新的 Mel 算法，分出来的 b1, b2 绝对丝滑、独立
            let (b1, b2) = bins(band: i, minFreq: minFreq, maxFreq: maxFreq, sr: currentSampleRate)
            let energy = computeEnergy(from: b1, to: b2, in: rawMags)
            energies[i] = energy
            
            peak = max(peak, energies[i])
            
            let normalized = energy / max(peak, 1e-10)
            let dB         = log2(max(normalized, 1e-10)) * 3.0103
            let mapped     = (dB - noiseFloorDB) / (ceilingDB - noiseFloorDB)
            
            let raw = min(max(mapped/* + redistributedBass*/, 0), 1)
            // ──────────────────────────────────────────────────────────────────
            
            // 双声道共享此 raw 值，取的是这一帧的两个声道谁最大
            tunnelRaw = max(raw, tunnelRaw)
            
            var smoothed: Float = 0.0
            let prev = previous[i]
                smoothed = raw > prev
                ? prev * (1.0 - attack) + raw * attack
                : prev * release + raw * (1.0 - release)
            
            tunnelRaw = 0
            result[i] = smoothed * 0.95 + prev * 0.05
            
        }
        
        // ── 🎛️ 参谋长推荐：高频阻尼防爆网（26 ~ 31柱） ──────────────────
        for p in 26...bandCount - 1 {
            // 🎯 计算当前柱子距离最远端的深度
            // p=26 时 alpha 约 0.70（给乐器留点脆劲）
            // p=31 时 alpha 约 0.45（给极端高频齿音加上重沙包，允许它跳，但必须极其丝滑）
            let progress = Float(p - 26) / 8.0 // 0.0 ~ 1.0
            let currentWeight = 0.70 - progress * 0.30 // 0.70 下降到 0.45
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

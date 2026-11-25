//
//  SongMetadataStore.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/11/24.
//

import AVFoundation
import Combine
import Foundation

/// 时长元数据扫描器。
///
/// 时长拿不到文件名 —— 歌词文件名里那个数字段虽然实测就是秒数，但用户点名要
/// 「AVAudioFile 真读时长」，所以只能逐个打开文件读 header。代价实测过（本机 120 首抽样）：
/// 单个 0.53ms，全库 787 首约 0.4s —— 打开 AVAudioFile 只解析容器头、不解码音频。
/// 所以可以放后台一次性扫完；但它终究是磁盘 IO，绝不能放到列表行的 body 里逐帧去读。
///
/// 分批上报（每 64 首 merge 一次 @Published）而不是扫完一把梭：
/// 0.4s 虽然不致于卡屏，但一把梭仍会让「时长」列整块跳出来；分批则是从顶部往里填。
/// 如果以后库长到万首量级（≈5s），这套分批就是必需的。
final class SongMetadataStore: ObservableObject {
    @Published private(set) var durations: [URL: TimeInterval] = [:]
    /// 后台是否还在读。列表用它把「还没读到」和「读失败」区分开。
    @Published private(set) var isScanning = false

    private var requested = Set<URL>()
    /// 在跑的后台批次。只主线程读写，归零才把 isScanning 落下。
    private var activePasses = 0

    private let batchSize = 64

    /// 幂等入口：只扫没扫过的 URL。切歌单、开 Super Shuffle、搜索命中都会反复调进来。
    /// 因为进来的永远是「新那部分」，所以多个批次并发跑也只是各写各的字典，
    /// 不会重复劳动；也就根本不需要取消机制。
    func scan(_ songs: [Song]) {
        let pending = songs.map { $0.url }.filter { !requested.contains($0) }
        guard !pending.isEmpty else { return }
        requested.formUnion(pending)
        schedule(pending)
    }

    private func schedule(_ urls: [URL]) {
        activePasses += 1
        isScanning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            var batch: [URL: TimeInterval] = [:]
            for url in urls {
                // processingFormat 的 sampleRate 为 0 只出现在容器损坏的情况，
                // 不挡就会得到 NaN，列表里显示成 nan:nan。
                if let file = try? AVAudioFile(forReading: url),
                   file.processingFormat.sampleRate > 0 {
                    batch[url] = Double(file.length) / file.processingFormat.sampleRate
                }
                if batch.count >= self.batchSize {
                    self.publish(batch)
                    batch.removeAll(keepingCapacity: true)
                }
            }
            if !batch.isEmpty { self.publish(batch) }
            DispatchQueue.main.async {
                self.activePasses -= 1
                self.isScanning = self.activePasses > 0
            }
        }
    }

    private func publish(_ new: [URL: TimeInterval]) {
        DispatchQueue.main.async {
            self.durations.merge(new) { _, latest in latest }
        }
    }

    func duration(of url: URL) -> TimeInterval? {
        durations[url]
    }
}

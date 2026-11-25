//
//  AlbumArtStore.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026-11-25.
//

import AppKit
import Combine
import Foundation
import ImageIO

/// 歌曲列表小封面的索引 + 缓存。
///
/// 为什么不复用 PlayerManager.findAlbumImages：那个函数每调一次就 contentsOfDirectory 列一遍
/// albums 目录，匹配不上还要把该歌手的全部图片逐个 NSImage(contentsOfFile:) 读进来 —— 给正在
/// 播放页那张旋转唱片用没问题（一首歌一次），列表里二十几行一起调就是二十几次列目录 + 上百次
/// 全图解码。这里拆成两步：目录只解析一次建索引（艺术家 → [(专辑名, URL)]），行渲染时是纯字典
/// 查找；解码丢后台，并且走 ImageIO 的缩略图接口按 128px 出图，不碰原图尺寸。
///
/// 匹配口径（艺术家对上，专辑名先精确后宽松）已抽成 static，控制条与正在播放页的
/// `PlayerManager.findAlbumImages` 也走这一份 —— 两边各写一套时，列表按下划线切、
/// 控制条按原始串前缀比（连 NFC 归一都没做，Céline Dion 那 23 首它今天就找不到），
/// 同一个 bug 会报两次。现在只允许有一份规则。
///
/// ⚠️ 艺术家段不能靠「切第一个下划线」拿出来：专辑图文件名是 QQ 那边直接落的盘，艺术家自己
/// 就常带下划线 —— 实测本机 487 张里有 `S_H_E_Super Star_4.jpg`（团体名 S.H.E）、
/// `林坤信 _ 商育通_仙籁情深_4.jpg`（多艺术家分隔符是 " _ "）。按第一个下划线切会把 key 切成
/// "s" / "林坤信"，于是这 68 首（787 里的 8.6%）在列表里永远查不到、只会显示占位图；
/// 而控制栏走的是 findAlbumImages 的前缀匹配，一点播放图就出来了 —— 就是报上来的那个不一致。
/// 所以现在改成拿艺术家串做前缀匹配，剩下那段才是专辑名。
final class AlbumArtStore: ObservableObject {

    /// key 用解析出来的 jpg URL：同一张专辑里的多首歌共用一份解码结果。
    @Published private(set) var images: [URL: NSImage] = [:]

    private struct Entry {
        /// sanitize 过的专辑名。
        let album: String
        let url: URL
    }

    /// 艺术家（sanitize 过）→ 该艺术家的全部专辑图。前缀匹配现算一次就缓存。
    private var byArtist: [String: [Entry]] = [:]
    /// albums 目录里的全部 jpg，只列一次。
    private var files: [URL] = []
    private var listed = false
    /// 已在后台排队或正在解码的 URL。行 body 每帧都会调 thumbnail(for:)，靠它保证幂等。
    private var loading: Set<URL> = []

    /// 出图边长。行里显示 40pt，@2x 也只要 80，取 128 是给以后放大留余量。
    static let pixelSize: CGFloat = 128
    /// 缓存上限。本机全部专辑图才 483 张，正常碰不到；写出来是为了库涨上去之后不会无限吃内存。
    private let cacheLimit = 800

    private let albumsURL: URL

    /// 确实没有专辑图的歌一律用 assets 里的 Albumdefault（用户要求），所以对外返回非可选：
    /// 没解析到、或者还在后台解码，都先给这张，图回来后 @Published 再把它换掉。
    private let fallbackImage: NSImage

    init(albumsURL: URL) {
        self.albumsURL = albumsURL
        self.fallbackImage = NSImage(named: "Albumdefault") ?? NSImage()
    }

    /// 行渲染入口。
    func thumbnail(for song: Song) -> NSImage {
        if let url = resolveURL(for: song) {
            if let image = images[url] { return image }
            enqueue(url)
        }
        return fallbackImage
    }

    /// 选中歌单时预热整张歌单，省掉滚动时逐行现解码那一下等待。幂等，可以反复调。
    func warm(_ songs: [Song]) {
        for song in songs {
            if let url = resolveURL(for: song) { enqueue(url) }
        }
    }

    // MARK: - 索引

    private func loadFilesIfNeeded() {
        guard !listed else { return }
        listed = true
        let fm = FileManager.default
        files = ((try? fm.contentsOfDirectory(at: albumsURL, includingPropertiesForKeys: nil,
                                             options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.pathExtension.lowercased() == "jpg" }
            // 排序后再入维：同一歌手多图、又只能兜底取 first 时，保证每次启动拿到同一张。
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// 该艺术家的全部专辑图。每个艺术家只扫一遍 487 个文件名，结果进 byArtist 缓存，
    /// 后续行渲染全是字典查。
    private func entries(artistKey: String) -> [Entry] {
        if let hit = byArtist[artistKey] { return hit }
        loadFilesIfNeeded()
        let found = Self.entries(artistKey: artistKey, urls: files)
        byArtist[artistKey] = found
        return found
    }

    private func resolveURL(for song: Song) -> URL? {
        // Song.artist 只来自文件名（用户明确 metadata 以后再做），拆不出来是「未知」，
        // 专辑图里当然不会有「未知」这个艺术家，直接走 nil → Albumdefault。
        Self.pick(album: song.album, from: entries(artistKey: PlaylistLoader.sanitize(song.artist)))
    }

    // MARK: - 共用解析规则

    /// 一次性解析（不养缓存）：控制条与正在播放页的整图走这条。它们是一首歌一次，
    /// 犯不上为它们多养一套状态；但规则必须和列表同一份，见下。
    static func resolveURL(for song: Song, albumsURL: URL) -> URL? {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: albumsURL, includingPropertiesForKeys: nil,
                                                    options: [.skipsHiddenFiles]) else { return nil }
        let jpgs = urls.filter { $0.pathExtension.lowercased() == "jpg" }
        let key = PlaylistLoader.sanitize(song.artist)
        guard !key.isEmpty else { return nil }
        return pick(album: song.album, from: entries(artistKey: key, urls: jpgs))
    }

    /// 艺术家段 → 候选专辑图。前缀匹配而不是切下划线，理由见文件头那段。
    private static func entries(artistKey key: String, urls: [URL]) -> [Entry] {
        var found: [Entry] = []
        if !key.isEmpty {
            for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let stem = PlaylistLoader.sanitize(url.deletingPathExtension().lastPathComponent)
                guard stem.hasPrefix(key) else { continue }
                // 剩下那段就是专辑名：先去掉分隔用的前导 "_"，再去掉抓图的尾部 "_4"。
                var album = String(stem.dropFirst(key.count))
                if album.hasPrefix("_") { album = String(album.dropFirst()) }
                if album.hasSuffix("_4") { album = String(album.dropLast(2)) }
                found.append(Entry(album: album, url: url))
            }
        }
        found.sort { $0.album < $1.album }
        return found
    }

    /// 专辑名先精确后宽松，都对不上就取排序后的第一张（稳定兜底）。
    private static func pick(album: String, from entries: [Entry]) -> URL? {
        guard !entries.isEmpty else { return nil }
        let want = PlaylistLoader.sanitize(album)
        if album != "未知", !want.isEmpty {
            if let exact = entries.first(where: { $0.album == want }) { return exact.url }
            // 宽松：专辑名带括注时（"21 (Explicit)" vs "21"）精确对不上，互相包含就算命中。
            if let loose = entries.first(where: { $0.album.contains(want) || want.contains($0.album) }) {
                return loose.url
            }
        }
        return entries.first?.url
    }

    // MARK: - 解码

    private func enqueue(_ url: URL) {
        guard images[url] == nil, !loading.contains(url) else { return }
        loading.insert(url)

        let side = Self.pixelSize
        DispatchQueue.global(qos: .utility).async {
            let image = Self.decode(url, side: side)
            DispatchQueue.main.async {
                self.loading.remove(url)
                guard let image else { return }
                if self.images.count >= self.cacheLimit {
                    // 不做 LRU：本库根本到不了这个量级，等真到了再补。先腾出三分之一，
                    // 避免出现「缓存满 → 新歌永远没有图」的死区。
                    self.images = self.images.filter { _ in Bool.random() }
                }
                self.images[url] = image
            }
        }
    }

    /// 后台线程只干解码这一件事，不碰任何 @Published 状态。
    private static func decode(_ url: URL, side: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceThumbnailMaxPixelSize: side,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }
}

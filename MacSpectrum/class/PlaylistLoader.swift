//
//  PlaylistLoader.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/4/18.
//

import Foundation

/// 一条歌词文件解析出来的元数据。
/// 歌词库的命名约定（实测 649 个文件 100% 符合）：
///     艺术家 - 歌名 - 秒数 - 专辑_qm.lrc
///     例：Adele - Someone Like You - 285 - 21 (Explicit)_qm.lrc
struct LyricMeta {
    /// 去空格 + 小写 + NFC 归一后的完整文件名（保留 _qm，不含 .lrc）。
    /// 一个串两用：既是要塞进 Song.lyric 的老语义（findAlbumImages 依赖），也是匹配键。
    let sanitized: String
    /// 带原始大小写与空格的专辑名。列表要展示的就是它，拆不出来为「未知」。
    let album: String
}

class PlaylistLoader {

    /// 与 LyricManager.loadLyric 完全同一套清洗（lowercased → NFC → 去空格）。
    /// 两边必须一致，否则会出现「歌词墙有词但列表专辑列写未知」这种分裂。
    static func sanitize(_ s: String) -> String {
        s.lowercased().precomposedStringWithCanonicalMapping.replacingOccurrences(of: " ", with: "")
    }

    /// 从歌词文件名尾段取专辑名。段数不足 4、或第 3 段不是纯秒数的，一律当解析失败。
    /// 取 parts[3...] 而不是 parts[3]，因为专辑名自己可能带 " - "
    ///（例：Achim Reichel - Aloha Heja He - 243 - Die Hit Giganten - Rock aus Deutschland）。
    static func album(fromLrcStem stem: String) -> String {
        var name = stem
        if name.hasSuffix("_qm") { name = String(name.dropLast(3)) }
        let parts = name.components(separatedBy: " - ")
        guard parts.count >= 4,
              Int(parts[2].trimmingCharacters(in: .whitespaces)) != nil else { return "未知" }
        let album = parts[3...].joined(separator: " - ").trimmingCharacters(in: .whitespaces)
        return album.isEmpty ? "未知" : album
    }

    /// 按第一个 " - " 拆。拆不开（比如就叫 a.mp3）时艺术家记「未知」、歌名就是整串，
    /// 与 PlaybackControlBar.titleComponents 的语义一致；后半保留后续的 " - "。
    static func splitArtistTitle(_ raw: String) -> (artist: String, title: String) {
        guard let range = raw.range(of: " - ") else { return ("未知", raw) }
        let artist = String(raw[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let title = String(raw[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !artist.isEmpty, !title.isEmpty else { return ("未知", raw) }
        return (artist, title)
    }

    static func loadLyrics(from lyricPath: String) -> [LyricMeta] {

        let fm = FileManager.default
        let lyricFolderURL = URL(fileURLWithPath: lyricPath)

        var metas: [LyricMeta] = []

        if let lyricFiles = try? fm.contentsOfDirectory(at: lyricFolderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            // 排序后再匹配：同名前缀撞上多个歌词时（实测 19 个），保证每次启动选到同一个。
            for lrcURL in lyricFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if lrcURL.pathExtension.lowercased() == "lrc" {
                    let stem = lrcURL.deletingPathExtension().lastPathComponent
                    metas.append(LyricMeta(sanitized: sanitize(stem),
                                           album: album(fromLrcStem: stem)))
                }
            }
        }
        return metas
    }
    
    static func load(from rootPath: String, in lyrics: [LyricMeta]) -> [Playlist] {
        
        let rootURL = URL(fileURLWithPath: rootPath)
        let fm = FileManager.default
        
        guard let folders = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        let playlists: [Playlist] = folders
            .filter { $0.hasDirectoryPath }
            .compactMap { folder in
                
                guard let files = try? fm.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { return nil }
                
                let songs: [Song] = files
                    .filter {
                        let ext = $0.pathExtension.lowercased()
                        return ext == "mp3" || ext == "ogg"
                    }
                    .map {
                        let title = $0.deletingPathExtension().lastPathComponent
                        let split = splitArtistTitle(title)
                        // 前缀匹配而不是老的精确相等：歌词文件名是「艺术家 - 歌名 - 秒数 - 专辑」，
                        // 歌曲名永远是其前缀。实测命中率 77.5%，且与「这首歌到底有没有词」基本对齐。
                        let key = sanitize(title)
                        let meta = lyrics.first { $0.sanitized.hasPrefix(key) }
                        let fileSize = Int64((try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                        return Song(
                            title: title,
                            url: $0,
                            lyric: meta?.sanitized ?? "",
                            artist: split.artist,
                            songTitle: split.title,
                            album: meta?.album ?? "未知",
                            size: fileSize
                        )
                    }
                    .sorted {
                        $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    }
                
                return Playlist(
                    name: folder.lastPathComponent,
                    url: folder,
                    songs: songs
                )
            }
        
        return playlists.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

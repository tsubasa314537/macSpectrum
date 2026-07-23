//
//  PlaylistLoader.swift
//  MacSpectrum
//
//  Created by 郭鹏 on 2026/4/18.
//

import Foundation

class PlaylistLoader {
    
    static func loadLyrics(from lyricPath: String) -> [String: String] {
        
        
        let fm = FileManager.default
        
        let lyricFolderURL = URL(fileURLWithPath: lyricPath)
        
        var lyricDictionary: [String: String] = [:] // Key: 纯小写歌名, Value: 歌词URL
        
        if let lyricFiles = try? fm.contentsOfDirectory(at: lyricFolderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for lrcURL in lyricFiles {
                if lrcURL.pathExtension.lowercased() == "lrc" {
                    // 拿到去掉后置后缀的干净歌词文件名（已无百分号），转为纯小写
                    let cleanLrcNames = lrcURL.deletingPathExtension()
                        .lastPathComponent
                        .components(separatedBy: "-")
                    
      
                    if cleanLrcNames.count >= 2 {
                        let title = cleanLrcNames[0]
                        + "- " +
                        cleanLrcNames[1]
                            .trimmingCharacters(in: .whitespaces)
                        let lrc = lrcURL.deletingPathExtension().lastPathComponent
                            .replacingOccurrences(of: " ", with: "")
                            .lowercased()
                        // 塞进字典备用
//                        print("cleanLrcNames=======\(cleanLrcNames)")
//                        print("lrc=======\(lrc)")
                        lyricDictionary[title] = lrc
                    }
                }
            }
        }
//        print("lyricDictionary=======\(lyricDictionary)")
        return lyricDictionary
        
    }
    
    static func load(from rootPath: String, in lrcDic: [String: String]) -> [Playlist] {
        
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
                        if let lrc = lrcDic[title] {
                            return Song(
                                title: title,
                                url: $0,
                                lyric: lrc
                            )
                        } else {
                            return Song(
                                title: title,
                                url: $0,
                                lyric: ""
                            )
                        }
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

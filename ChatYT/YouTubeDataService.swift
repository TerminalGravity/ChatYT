//
//  YouTubeDataService.swift
//  ChatYT
//
//  Created by Jack Felke on 3/24/25.
//

import Foundation
import SwiftUI
import Combine

/// Service class for interfacing with the YouTube Data API
class YouTubeDataService: ObservableObject {
    
    // Singleton instance for app-wide access
    static let shared = YouTubeDataService()
    
    // YouTube Data API key
    private var apiKey: String {
        return GeminiService.shared.getAPIKey() // Reuse the same API key
    }
    
    // Base URL for the YouTube Data API
    private let baseURL = "https://www.googleapis.com/youtube/v3"
    
    private init() {}
    
    /// Check if a video ID is valid and accessible
    /// - Parameter videoID: The YouTube video ID to check
    /// - Returns: A tuple containing a Boolean indicating validity and the video title if available
    func validateVideoID(_ videoID: String) async -> (isValid: Bool, title: String?, error: String?) {
        print("Validating YouTube ID: \(videoID)")
        
        // First try validating as a video
        if let (isVideoValid, videoTitle, videoError) = await validateAsVideo(videoID) {
            if isVideoValid {
                return (true, videoTitle, nil)
            } else {
                // If not a valid video, try as a playlist
                if let (isPlaylistValid, playlistTitle, _) = await validateAsPlaylist(videoID) {
                    if isPlaylistValid {
                        return (true, playlistTitle, nil)
                    }
                }
                
                // Both failed, return the video error
                return (false, nil, videoError)
            }
        }
        
        return (false, nil, "Could not validate YouTube ID")
    }
    
    /// Validate ID as a YouTube video
    private func validateAsVideo(_ videoID: String) async -> (isValid: Bool, title: String?, error: String?)? {
        // Construct the API URL for video validation
        guard let url = URL(string: "\(baseURL)/videos?id=\(videoID)&part=snippet&key=\(apiKey)") else {
            print("Failed to construct YouTube video API URL")
            return (false, nil, "Invalid URL construction")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, nil, "Invalid HTTP response")
            }
            
            if httpResponse.statusCode == 403 {
                print("YouTube API access forbidden (403). API key may not have YouTube Data API permissions.")
                return (false, nil, "API key lacks YouTube Data API permissions")
            }
            
            guard httpResponse.statusCode == 200 else {
                print("YouTube API error: \(httpResponse.statusCode)")
                return (false, nil, "YouTube API returned status code \(httpResponse.statusCode)")
            }
            
            // Parse the response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]] {
                
                if items.isEmpty {
                    print("No video found with ID: \(videoID)")
                    return (false, nil, "No video found with this ID")
                }
                
                if let snippet = items[0]["snippet"] as? [String: Any],
                   let title = snippet["title"] as? String {
                    print("YouTube video validated: \(title)")
                    return (true, title, nil)
                } else {
                    print("Video found but couldn't extract title")
                    return (true, "Untitled YouTube Video", nil)
                }
            } else {
                print("Failed to parse YouTube API response")
                return (false, nil, "Failed to parse API response")
            }
        } catch {
            print("Error validating YouTube video: \(error.localizedDescription)")
            return (false, nil, "Network error: \(error.localizedDescription)")
        }
    }
    
    /// Validate ID as a YouTube playlist
    private func validateAsPlaylist(_ playlistID: String) async -> (isValid: Bool, title: String?, error: String?)? {
        // Construct the API URL for playlist validation
        guard let url = URL(string: "\(baseURL)/playlists?id=\(playlistID)&part=snippet&key=\(apiKey)") else {
            print("Failed to construct YouTube playlist API URL")
            return (false, nil, "Invalid URL construction")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("YouTube playlist API error: \(response)")
                return (false, nil, "API error when checking playlist")
            }
            
            // Parse the response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]] {
                
                if items.isEmpty {
                    print("No playlist found with ID: \(playlistID)")
                    return (false, nil, "No playlist found with this ID")
                }
                
                if let snippet = items[0]["snippet"] as? [String: Any],
                   let title = snippet["title"] as? String {
                    print("YouTube playlist validated: \(title)")
                    return (true, "Playlist: \(title)", nil)
                } else {
                    print("Playlist found but couldn't extract title")
                    return (true, "Untitled YouTube Playlist", nil)
                }
            } else {
                print("Failed to parse YouTube playlist API response")
                return (false, nil, "Failed to parse API response")
            }
        } catch {
            print("Error validating YouTube playlist: \(error.localizedDescription)")
            return (false, nil, "Network error: \(error.localizedDescription)")
        }
    }
    
    /// Get metadata for a YouTube video or playlist
    /// - Parameter id: The YouTube video or playlist ID
    /// - Returns: A dictionary containing metadata
    func getVideoMetadata(_ id: String) async -> [String: Any]? {
        // First try as video
        if let metadata = await getVideoDirectMetadata(id) {
            return metadata
        }
        
        // If not a video, try as playlist
        if let metadata = await getPlaylistMetadata(id) {
            return metadata
        }
        
        return nil
    }
    
    /// Get metadata specifically for a video
    private func getVideoDirectMetadata(_ videoID: String) async -> [String: Any]? {
        // Construct the API URL
        guard let url = URL(string: "\(baseURL)/videos?id=\(videoID)&part=snippet,contentDetails,statistics&key=\(apiKey)") else {
            print("Failed to construct YouTube API URL")
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("YouTube API error: \(response)")
                return nil
            }
            
            // Parse the response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]],
               !items.isEmpty {
                
                // Return the first item as the metadata
                return items[0]
            } else {
                print("YouTube video metadata not found")
                return nil
            }
        } catch {
            print("Error getting YouTube video metadata: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Get metadata for a playlist
    private func getPlaylistMetadata(_ playlistID: String) async -> [String: Any]? {
        // Construct the API URL
        guard let url = URL(string: "\(baseURL)/playlists?id=\(playlistID)&part=snippet,contentDetails&key=\(apiKey)") else {
            print("Failed to construct YouTube playlist API URL")
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("YouTube playlist API error: \(response)")
                return nil
            }
            
            // Parse the response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]],
               !items.isEmpty {
                
                var metadata = items[0]
                // Add a type field to distinguish
                metadata["type"] = "playlist"
                
                return metadata
            } else {
                print("YouTube playlist metadata not found")
                return nil
            }
        } catch {
            print("Error getting YouTube playlist metadata: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Check if a URL contains a playlist ID and extract it
    /// - Parameter url: The YouTube URL to check
    /// - Returns: The playlist ID if found, nil otherwise
    func extractPlaylistID(from url: String) -> String? {
        // Check for list parameter in query
        if let urlComponents = URLComponents(string: url),
           let queryItems = urlComponents.queryItems,
           let listParam = queryItems.first(where: { $0.name == "list" })?.value {
            return listParam
        }
        
        // Try regex patterns for different playlist URL formats
        let patterns = [
            "list=([\\w-]+)",  // Standard playlist parameter
            "youtube\\.com/playlist\\?list=([\\w-]+)",  // Direct playlist URL
            "youtube\\.com/watch\\?.*list=([\\w-]+)"  // Video in playlist
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: url, options: [], range: NSRange(location: 0, length: url.utf16.count)),
               let range = Range(match.range(at: 1), in: url) {
                let playlistID = String(url[range])
                print("Extracted playlist ID: \(playlistID)")
                return playlistID
            }
        }
        
        return nil
    }
    
    /// Check if a string is likely a playlist ID
    /// - Parameter id: The string to check
    /// - Returns: True if the string follows playlist ID patterns
    func isLikelyPlaylistID(_ id: String) -> Bool {
        // Most playlist IDs start with PL, LL, FL, UU, or similar
        let playlistPrefixes = ["PL", "FL", "LL", "UU", "OL", "RD", "UC"]
        for prefix in playlistPrefixes {
            if id.hasPrefix(prefix) {
                return true
            }
        }
        
        return false
    }
    
    /// Get playlist items (first few videos in the playlist)
    /// - Parameter playlistID: The YouTube playlist ID
    /// - Returns: Array of video details
    func getPlaylistItems(_ playlistID: String, maxResults: Int = 5) async -> [[String: Any]]? {
        // Construct the API URL
        guard let url = URL(string: "\(baseURL)/playlistItems?playlistId=\(playlistID)&part=snippet&maxResults=\(maxResults)&key=\(apiKey)") else {
            print("Failed to construct YouTube playlist items API URL")
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("YouTube playlist items API error: \(response)")
                return nil
            }
            
            // Parse the response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]] {
                return items
            } else {
                print("Failed to parse YouTube playlist items API response")
                return nil
            }
        } catch {
            print("Error getting YouTube playlist items: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Extract video details as a structured dictionary
    /// - Parameter videoID: The YouTube video ID
    /// - Returns: A dictionary with key information about the video
    func extractVideoDetails(_ videoID: String) async -> [String: String]? {
        // Check if this looks like a playlist ID
        if isLikelyPlaylistID(videoID) {
            return await extractPlaylistDetails(videoID)
        }
        
        // Otherwise treat as regular video
        guard let metadata = await getVideoMetadata(videoID) else {
            return nil
        }
        
        var details: [String: String] = [:]
        details["type"] = "video"
        
        if let snippet = metadata["snippet"] as? [String: Any] {
            details["title"] = snippet["title"] as? String
            details["description"] = snippet["description"] as? String
            details["publishedAt"] = snippet["publishedAt"] as? String
            details["channelTitle"] = snippet["channelTitle"] as? String
            
            if let thumbnails = snippet["thumbnails"] as? [String: Any],
               let high = thumbnails["high"] as? [String: Any] {
                details["thumbnailUrl"] = high["url"] as? String
            }
        }
        
        if let contentDetails = metadata["contentDetails"] as? [String: Any] {
            details["duration"] = contentDetails["duration"] as? String
        }
        
        if let statistics = metadata["statistics"] as? [String: Any] {
            if let viewCount = statistics["viewCount"] as? String {
                details["viewCount"] = viewCount
            }
            if let likeCount = statistics["likeCount"] as? String {
                details["likeCount"] = likeCount
            }
            if let commentCount = statistics["commentCount"] as? String {
                details["commentCount"] = commentCount
            }
        }
        
        return details
    }
    
    /// Extract playlist details as a structured dictionary
    /// - Parameter playlistID: The YouTube playlist ID
    /// - Returns: A dictionary with key information about the playlist
    func extractPlaylistDetails(_ playlistID: String) async -> [String: String]? {
        guard let metadata = await getPlaylistMetadata(playlistID) else {
            return nil
        }
        
        var details: [String: String] = [:]
        details["type"] = "playlist"
        
        if let snippet = metadata["snippet"] as? [String: Any] {
            details["title"] = snippet["title"] as? String
            details["description"] = snippet["description"] as? String
            details["publishedAt"] = snippet["publishedAt"] as? String
            details["channelTitle"] = snippet["channelTitle"] as? String
            
            if let thumbnails = snippet["thumbnails"] as? [String: Any],
               let high = thumbnails["high"] as? [String: Any] {
                details["thumbnailUrl"] = high["url"] as? String
            }
        }
        
        if let contentDetails = metadata["contentDetails"] as? [String: Any],
           let itemCount = contentDetails["itemCount"] as? Int {
            details["itemCount"] = String(itemCount)
        }
        
        // Get the first few videos in the playlist
        if let playlistItems = await getPlaylistItems(playlistID, maxResults: 3) {
            var videoTitles = ""
            for (index, item) in playlistItems.enumerated() {
                if let snippet = item["snippet"] as? [String: Any],
                   let title = snippet["title"] as? String {
                    videoTitles += "\(index + 1). \(title)\n"
                }
            }
            if !videoTitles.isEmpty {
                details["videoSamples"] = videoTitles
            }
        }
        
        return details
    }
} 
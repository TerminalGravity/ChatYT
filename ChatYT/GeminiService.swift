//
//  GeminiService.swift
//  ChatYT
//
//  Created by Jack Felke on 3/24/25.
//

import Foundation
import Security
import SwiftUI
import Combine
import Network

/// Service class for interfacing with the Gemini API
class GeminiService: ObservableObject {
    
    // Singleton instance for app-wide access
    static let shared = GeminiService()
    
    // API key and endpoint
    @Published private(set) var apiKey: String?
    
    // Use standard Gemini API endpoint
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent"
    
    // Alternative endpoints to try if the main one fails
    private let fallbackURLs = [
        "https://us-generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent",
        "https://eu-generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent",
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.0-pro:generateContent"
    ]
    
    // Keychain constants
    private let keychainService = "com.chatyt.app"
    private let keychainAccount = "geminiApiKey"
    
    private init() {
        // Try to retrieve the API key from the keychain
        apiKey = getAPIKeyFromKeychain()
    }
    
    /// Save API key to Keychain
    func setAPIKey(_ key: String) {
        apiKey = key
        saveAPIKeyToKeychain(key)
        // Publish change notification
        objectWillChange.send()
    }
    
    /// Get the current API key
    func getAPIKey() -> String {
        return apiKey ?? ""
    }
    
    /// Check if API key is set
    var isAPIKeySet: Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }
    
    // MARK: - Keychain Methods
    
    private func saveAPIKeyToKeychain(_ apiKey: String) {
        guard !apiKey.isEmpty else { return }
        
        // Delete any existing key first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add the new key
        let apiKeyData = apiKey.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: apiKeyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Error saving API key to Keychain: \(status)")
        }
    }
    
    private func getAPIKeyFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let retrievedData = dataTypeRef as? Data {
            return String(data: retrievedData, encoding: .utf8)
        } else {
            return nil
        }
    }
    
    /// Check network connectivity to the Gemini API
    /// - Returns: True if connection is available, false otherwise
    func checkAPIConnectivity() async -> Bool {
        // Test if we can connect to Google's DNS servers
        let hostnames = ["8.8.8.8", "8.8.4.4", "googleapis.com", "google.com"]
        
        // Try multiple hosts to diagnose connectivity issues
        for hostname in hostnames {
            print("Testing connectivity to: \(hostname)")
            
            // Create a simple URL session
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = 5.0
            sessionConfig.waitsForConnectivity = true
            let session = URLSession(configuration: sessionConfig)
            
            // For IP addresses, use a socket connection
            if hostname.contains(".") && hostname.components(separatedBy: ".").count == 4 {
                do {
                    let socket = NWConnection(host: NWEndpoint.Host(hostname), port: NWEndpoint.Port(integerLiteral: 53), using: .udp)
                    socket.stateUpdateHandler = { state in
                        print("Socket connection state: \(state)")
                    }
                    socket.start(queue: .global())
                    
                    // Wait briefly for connection attempt
                    try await Task.sleep(for: .seconds(1))
                    
                    // If we reach this point, we have some network connectivity
                    return true
                } catch {
                    print("Socket connection error: \(error.localizedDescription)")
                    // Continue to next hostname
                }
                continue
            }
            
            // For domain names, try a simple HTTP request
            guard let url = URL(string: "https://\(hostname)") else { continue }
            
            do {
                // Send a HEAD request to check connectivity
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                
                let (_, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    print("Connection to \(hostname) successful with status: \(httpResponse.statusCode)")
                    return true
                }
            } catch {
                print("Connection to \(hostname) failed: \(error.localizedDescription)")
                // Continue to next hostname
            }
        }
        
        // If all connection attempts failed
        print("All connectivity tests failed")
        return false
    }
    
    /// Generate a response from Gemini AI
    /// - Parameter prompt: The text prompt to send to the API
    /// - Returns: The generated response text, or nil if an error occurred
    func generateResponse(prompt: String) async -> String? {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            print("API key not set")
            return "⚠️ Gemini API key not configured. Please set it in settings."
        }
        
        // Check network connectivity first
        if await !checkAPIConnectivity() {
            return "⚠️ Network connectivity issue detected. Please check your internet connection and ensure your app has proper network permissions."
        }
        
        // Try main endpoint
        if let response = await tryEndpoint(baseURL, withPrompt: prompt) {
            return response
        }
        
        // Try fallback endpoints
        for fallbackURL in fallbackURLs {
            print("Primary endpoint failed, trying fallback: \(fallbackURL)")
            if let response = await tryEndpoint(fallbackURL, withPrompt: prompt) {
                return response
            }
        }
        
        return "Error: Could not connect to any Gemini API endpoints. Please check your network connection and API key."
    }
    
    /// Try to connect to a specific endpoint with the given prompt
    private func tryEndpoint(_ endpointURL: String, withPrompt prompt: String) async -> String? {
        // Fix URL construction by using URLComponents
        guard let baseURL = URL(string: endpointURL) else {
            print("Invalid base URL")
            return "Error: Invalid API base URL"
        }
        
        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
        urlComponents?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        guard let url = urlComponents?.url else {
            print("Failed to construct URL")
            return "Error: Failed to construct API URL"
        }
        
        print("Sending request to: \(url.absoluteString.replacingOccurrences(of: apiKey ?? "", with: "[REDACTED]"))")
        
        // Build the request payload
        let payload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": 2048,
            ]
        ]
        
        return await sendRequest(url: url, payload: payload)
    }
    
    /// Process a YouTube video using Gemini AI
    /// - Parameters:
    ///   - videoID: The YouTube video ID or playlist ID
    ///   - prompt: The custom prompt to use (with {videoID} placeholder)
    func processYouTubeVideo(videoID: String, prompt: String) async -> String? {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            print("API key not set")
            return "⚠️ Gemini API key not configured. Please set it in settings."
        }
        
        // Check network connectivity first
        if await !checkAPIConnectivity() {
            return "⚠️ Network connectivity issue detected. Please check your internet connection and ensure your app has proper network permissions."
        }
        
        // Validate the YouTube ID before processing
        let (isValid, title, error) = await YouTubeDataService.shared.validateVideoID(videoID)
        
        if !isValid {
            print("Invalid YouTube ID: \(videoID), Error: \(error ?? "Unknown error")")
            return "⚠️ The YouTube content with ID '\(videoID)' could not be found or is not accessible. Please verify the URL and ensure the content is publicly available."
        }
        
        print("Successfully validated YouTube content: \(title ?? "Untitled")")
        
        // Check if this is a playlist
        let isPlaylist = title?.hasPrefix("Playlist:") ?? false
        
        // Determine appropriate URL format based on content type
        let youtubeUrl: String
        if isPlaylist {
            youtubeUrl = "https://www.youtube.com/playlist?list=\(videoID)"
            print("Processing YouTube Playlist URL: \(youtubeUrl)")
        } else {
            youtubeUrl = "https://www.youtube.com/watch?v=\(videoID)"
            print("Processing YouTube Video URL: \(youtubeUrl)")
        }
        
        // Prepare a custom prompt based on content type
        var contentTypePrompt = prompt
        
        // If this is a playlist and the prompt doesn't mention it
        if isPlaylist && !prompt.lowercased().contains("playlist") {
            contentTypePrompt = "This is a YouTube playlist. " + prompt
        }
        
        // Add content title if available
        if let contentTitle = title?.replacingOccurrences(of: "Playlist: ", with: "") {
            if !contentTypePrompt.contains(contentTitle) {
                contentTypePrompt = "Title: \"\(contentTitle)\". " + contentTypePrompt
            }
        }
        
        // Replace placeholders in prompt
        let userPrompt = contentTypePrompt.replacingOccurrences(of: "{videoID}", with: videoID)
        print("Using prompt: \(userPrompt)")
        
        // Try main endpoint first for video analysis
        let payload = buildVideoPayload(url: youtubeUrl, prompt: userPrompt, isLocalFile: false)
        
        if let response = await tryVideoRequest(url: baseURL, payload: payload) {
            return response
        }
        
        // Try fallback endpoints
        for fallbackURL in fallbackURLs {
            print("Primary endpoint failed, trying fallback: \(fallbackURL)")
            if let response = await tryVideoRequest(url: fallbackURL, payload: payload) {
                return response
            }
        }
        
        // If all API calls fail, try to at least return information about the content
        // from YouTube Data API as a fallback user experience
        if let metadata = await YouTubeDataService.shared.extractVideoDetails(videoID) {
            let contentType = isPlaylist ? "playlist" : "video"
            let title = metadata["title"] ?? "Untitled YouTube Content"
            let channelTitle = metadata["channelTitle"] ?? "Unknown Channel"
            
            var fallbackResponse = "⚠️ I couldn't analyze the YouTube \(contentType) content through Gemini, but I can provide basic information about it:\n\n"
            fallbackResponse += "**Title**: \(title)\n"
            fallbackResponse += "**Channel**: \(channelTitle)\n"
            
            if let description = metadata["description"], !description.isEmpty {
                let shortDescription = description.split(separator: "\n").first ?? ""
                fallbackResponse += "**Description**: \(shortDescription)\n"
            }
            
            if let viewCount = metadata["viewCount"] {
                fallbackResponse += "**Views**: \(viewCount)\n"
            }
            
            if isPlaylist, let itemCount = metadata["itemCount"] {
                fallbackResponse += "**Videos in playlist**: \(itemCount)\n"
            }
            
            fallbackResponse += "\nPlease try asking specific questions about this \(contentType), and I'll try to assist based on available information."
            
            return fallbackResponse
        }
        
        return "Error: Could not connect to any Gemini API endpoints or access the YouTube content. Please check your network connection, API key, and ensure the URL is correct."
    }
    
    /// Process a local video file using Gemini AI
    /// - Parameters:
    ///   - filePath: The local file path to the video
    ///   - fileName: The name of the file
    ///   - prompt: The custom prompt to use
    func processLocalVideo(filePath: String, fileName: String, prompt: String) async -> String? {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            print("API key not set")
            return "⚠️ Gemini API key not configured. Please set it in settings."
        }
        
        // Check network connectivity first
        if await !checkAPIConnectivity() {
            return "⚠️ Network connectivity issue detected. Please check your internet connection and ensure your app has proper network permissions."
        }
        
        // Validate the file exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: filePath) {
            print("Local file not found: \(filePath)")
            return "⚠️ The local video file could not be found. Please check if the file exists."
        }
        
        print("Processing local video file: \(fileName)")
        
        // Prepare a custom prompt for the local file
        var contentTypePrompt = prompt
        
        // Add file name to prompt if not already included
        if !contentTypePrompt.contains(fileName) {
            contentTypePrompt = "Local Video File: \"\(fileName)\". " + contentTypePrompt
        }
        
        // Try to get file attributes for additional context
        do {
            let attributes = try fileManager.attributesOfItem(atPath: filePath)
            if let fileSize = attributes[.size] as? UInt64 {
                let fileSizeMB = Double(fileSize) / (1024.0 * 1024.0)
                contentTypePrompt += "\n\nFile size: \(String(format: "%.2f", fileSizeMB)) MB"
            }
            
            if let creationDate = attributes[.creationDate] as? Date {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .short
                contentTypePrompt += "\nCreation date: \(dateFormatter.string(from: creationDate))"
            }
        } catch {
            print("Error getting file attributes: \(error.localizedDescription)")
        }
        
        print("Using prompt for local file: \(contentTypePrompt)")
        
        // Try main endpoint first for video analysis
        let payload = buildVideoPayload(url: "file://\(filePath)", prompt: contentTypePrompt, isLocalFile: true)
        
        if let response = await tryVideoRequest(url: baseURL, payload: payload) {
            return response
        }
        
        // Try fallback endpoints
        for fallbackURL in fallbackURLs {
            print("Primary endpoint failed, trying fallback: \(fallbackURL)")
            if let response = await tryVideoRequest(url: fallbackURL, payload: payload) {
                return response
            }
        }
        
        // If all API calls fail, return basic information about the file
        var fallbackResponse = "⚠️ I couldn't analyze the local video file through Gemini, but here's what I know about it:\n\n"
        fallbackResponse += "**File**: \(fileName)\n"
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: filePath)
            if let fileSize = attributes[.size] as? UInt64 {
                let fileSizeMB = Double(fileSize) / (1024.0 * 1024.0)
                fallbackResponse += "**Size**: \(String(format: "%.2f", fileSizeMB)) MB\n"
            }
            
            if let creationDate = attributes[.creationDate] as? Date {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .short
                fallbackResponse += "**Created**: \(dateFormatter.string(from: creationDate))\n"
            }
            
            // Try to get file extension
            let fileExtension = URL(fileURLWithPath: filePath).pathExtension
            if !fileExtension.isEmpty {
                fallbackResponse += "**Format**: \(fileExtension.uppercased())\n"
            }
        } catch {
            fallbackResponse += "**Error**: Could not read additional file attributes.\n"
        }
        
        fallbackResponse += "\nPlease try asking specific questions about this video file, and I'll try to assist based on available information."
        
        return fallbackResponse
    }
    
    /// Build the payload for video or playlist analysis
    private func buildVideoPayload(url contentUrl: String, prompt: String, isLocalFile: Bool = false) -> [String: Any] {
        // Build a multimodal request payload following Gemini's video understanding format
        var parts: [[String: Any]] = []
        
        // According to docs: place video before text prompt for best results
        if isLocalFile {
            // For local files, we need to read the file and encode it as base64
            let filePath = contentUrl.replacingOccurrences(of: "file://", with: "")
            
            // Check file size first - Gemini API has size limits
            if let fileAttributes = try? FileManager.default.attributesOfItem(atPath: filePath),
               let fileSize = fileAttributes[.size] as? Int {
                
                // API typically has ~10MB limit for base64 encoded files
                let maxSizeInBytes = 10 * 1024 * 1024 // 10MB
                
                if fileSize > maxSizeInBytes {
                    print("File is too large for direct upload: \(fileSize) bytes. Max size is \(maxSizeInBytes) bytes.")
                    
                    // Add a text note about the file being too large
                    parts.append([
                        "text": "The video file is too large for direct analysis (\(String(format: "%.1f", Double(fileSize) / 1024.0 / 1024.0)) MB). Please upload a shorter clip or lower resolution version under 10MB, or provide a YouTube link instead."
                    ])
                } else {
                    // File size is acceptable, proceed with encoding
                    if let fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) {
                        let base64Data = fileData.base64EncodedString()
                        
                        // Get the MIME type based on file extension
                        var mimeType = "video/mp4"  // Default
                        let fileExtension = URL(fileURLWithPath: filePath).pathExtension.lowercased()
                        
                        // Set appropriate MIME type based on file extension
                        switch fileExtension {
                        case "mp4":
                            mimeType = "video/mp4"
                        case "mov":
                            mimeType = "video/quicktime"
                        case "avi":
                            mimeType = "video/x-msvideo"
                        case "wmv":
                            mimeType = "video/x-ms-wmv"
                        case "flv":
                            mimeType = "video/x-flv"
                        case "webm":
                            mimeType = "video/webm"
                        case "mkv":
                            mimeType = "video/x-matroska"
                        default:
                            mimeType = "video/mp4"  // Default fallback
                        }
                        
                        // Add data part using base64 encoding
                        parts.append([
                            "inlineData": [
                                "data": base64Data,
                                "mimeType": mimeType
                            ]
                        ])
                        
                        print("Local video file encoded as base64 with MIME type: \(mimeType), size: \(String(format: "%.2f", Double(fileSize) / 1024.0 / 1024.0)) MB")
                    } else {
                        print("Failed to read local file at path: \(filePath)")
                        
                        // Add a text note about the failed file read
                        parts.append([
                            "text": "Failed to read local video file at: \(filePath)"
                        ])
                    }
                }
            } else {
                print("Failed to get file attributes for: \(filePath)")
                
                // Add a text note about the failed file attribute retrieval
                parts.append([
                    "text": "Failed to access file attributes for: \(filePath)"
                ])
            }
        } else {
            // For YouTube URLs, we need to provide the URL for the model to analyze
            // The model will fetch and process the YouTube content
            parts.append([
                "text": "Please analyze this YouTube video: \(contentUrl)\n\nThe URL contains a video I'd like you to understand and summarize."
            ])
        }
        
        // Add the text prompt after the video data
        var enhancedPrompt = prompt
        
        // Add timestamp format hint for better temporal understanding
        enhancedPrompt += "\n\nNote: Please provide any timestamps in MM:SS format where relevant."
        
        // Add video duration context based on Gemini limitations
        if !isLocalFile {
            enhancedPrompt += "\nPlease focus on the first 2 minutes of content if the video is longer."
        }
        
        parts.append([
            "text": enhancedPrompt
        ])
        
        return [
            "contents": [
                "role": "USER",
                "parts": parts
            ],
            "generationConfig": [
                "temperature": 0.4,        // Balanced for both accuracy and detail
                "topP": 0.8,              // More deterministic responses
                "maxOutputTokens": 1024,   // Conservative token limit
                "stopSequences": []        // No early stopping
            ],
            "safetySettings": [
                [
                    "category": "HARM_CATEGORY_DANGEROUS_CONTENT",
                    "threshold": "BLOCK_LOW_AND_ABOVE"
                ],
                [
                    "category": "HARM_CATEGORY_HATE_SPEECH",
                    "threshold": "BLOCK_LOW_AND_ABOVE"
                ],
                [
                    "category": "HARM_CATEGORY_HARASSMENT",
                    "threshold": "BLOCK_LOW_AND_ABOVE"
                ],
                [
                    "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                    "threshold": "BLOCK_LOW_AND_ABOVE"
                ]
            ]
        ]
    }
    
    /// Try a video request with the specified endpoint
    private func tryVideoRequest(url endpointURL: String, payload: [String: Any]) async -> String? {
        // Always use Gemini Pro Vision for video content
        var modifiedEndpoint = endpointURL
        
        // Force using vision-capable models
        if modifiedEndpoint.contains("gemini-1.0") {
            // Use Gemini 1.0 Pro Vision for older versions
            modifiedEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.0-pro-vision:generateContent"
        } else {
            // Default to Gemini 1.5 Pro Vision for newer versions
            modifiedEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro-vision:generateContent"
        }
        
        print("Using vision model endpoint: \(modifiedEndpoint)")
        
        // Fix URL construction by using URLComponents
        guard let baseURL = URL(string: modifiedEndpoint) else {
            print("Invalid base URL")
            return "Error: Invalid API base URL"
        }
        
        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
        urlComponents?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        guard let url = urlComponents?.url else {
            print("Failed to construct URL")
            return "Error: Failed to construct API URL"
        }
        
        return await sendRequest(url: url, payload: payload)
    }
    
    /// Send a request to the Gemini API
    /// - Parameters:
    ///   - url: The API endpoint URL
    ///   - payload: The request payload
    /// - Returns: The response text or error message
    private func sendRequest(url: URL, payload: [String: Any]) async -> String? {
        // Configure session with more reliable settings
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30.0
        sessionConfig.timeoutIntervalForResource = 60.0
        sessionConfig.allowsCellularAccess = true
        sessionConfig.waitsForConnectivity = true
        
        // Avoid using multipathServiceType as it's unavailable on macOS
        // Instead, use more conservative connection settings
        sessionConfig.httpMaximumConnectionsPerHost = 1
        
        // Create a custom session with these settings
        let session = URLSession(configuration: sessionConfig)
        
        // Convert payload to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            print("Failed to serialize JSON")
            return "Error: Failed to serialize request"
        }
        
        // Create HTTP request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        // Send request and handle response
        do {
            print("Attempting connection to: \(url.host ?? "unknown host")")
            
            let (data, response) = try await session.data(for: request)
            
            // Check HTTP response code
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response")
                return "Error: Invalid HTTP response"
            }
            
            // Log response for debugging
            let responseText = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            print("Response status: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                print("HTTP error: \(httpResponse.statusCode)")
                print("Error details: \(responseText)")
                
                // Extract error message if available
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    return "API Error: \(message)"
                }
                
                return "API Error (\(httpResponse.statusCode)): Failed to generate response"
            }
            
            // Parse response with improved error handling
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("Response structure: \(json.keys.joined(separator: ", "))")
                
                if let candidates = json["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first {
                    
                    print("Candidate structure: \(firstCandidate.keys.joined(separator: ", "))")
                    
                    if let content = firstCandidate["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]],
                       let firstPart = parts.first,
                       let text = firstPart["text"] as? String {
                        return text.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        // Try alternative response format
                        if let text = firstCandidate["text"] as? String {
                            return text.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        
                        print("Failed to extract text from candidate")
                        print("Content structure: \(String(describing: firstCandidate["content"]))")
                        return "Error: Could not extract response text from API"
                    }
                } else {
                    print("No candidates found in response")
                    print("Full response structure: \(json)")
                    return "Error: No response candidates found"
                }
            }
            
            print("Failed to parse response as JSON")
            print("Raw response: \(responseText)")
            return "Error: Failed to parse API response"
            
        } catch let error as NSError {
            // Network error with more detailed information
            print("Network error: \(error.localizedDescription)")
            print("Error domain: \(error.domain), code: \(error.code)")
            
            if error.domain == NSURLErrorDomain {
                switch error.code {
                case NSURLErrorNotConnectedToInternet:
                    return "Error: No internet connection. Please check your network settings."
                case NSURLErrorTimedOut:
                    return "Error: Request timed out. Please try again."
                case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                    if let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
                        return "Error: Cannot connect to server at \(url.host ?? "unknown host"). This might be due to network restrictions or DNS issues."
                    }
                    return "Error: Cannot connect to the API server. This might be due to network restrictions or DNS issues."
                case NSURLErrorDNSLookupFailed:
                    return "Error: DNS lookup failed. Your network may be blocking access to Google APIs."
                default:
                    return "Network Error (\(error.code)): \(error.localizedDescription)"
                }
            }
            
            return "Error: \(error.localizedDescription)"
        }
    }
} 
//
//  ContentView.swift
//  ChatYT
//
//  Created by Jack Felke on 3/24/25.
//

import SwiftUI
import CoreData
import WebKit

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var youtubeURL: String = ""
    @State private var videoID: String?
    @State private var settingsPresented = false
    @State private var selectedConversation: Conversation?
    @State private var showUrlError = false
    @State private var urlErrorMessage = ""
    @State private var apiKeyConfigured: Bool = false
    @State private var isProcessingURL: Bool = false
    
    // New state variables for modals
    @State private var showYouTubeURLModal = false
    @State private var showFilePickerModal = false
    @State private var newYouTubeURL = ""
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Conversation.createdAt, ascending: false)],
        animation: .default)
    private var conversations: FetchedResults<Conversation>
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // App header with logo and title
                HStack {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.largeTitle)
                        .foregroundColor(.blue)
                    
                    Text("ChatYT")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    Button(action: { settingsPresented = true }) {
                        Image(systemName: "gear")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .help("Settings")
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                // Main content
                List {
                    Section {
                        VStack(spacing: 12) {
                            Text("Chat with YouTube Videos")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .center)
                            
                            Button(action: {
                                showNewConversationMenu()
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                    
                                    Text("New Conversation")
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .disabled(isProcessingURL)
                            
                            if isProcessingURL {
                                HStack {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .scaleEffect(0.8)
                                    
                                    Text("Processing content...")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                            }
                            
                            if showUrlError {
                                Text(urlErrorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    
                    if !apiKeyConfigured {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.yellow)
                                        .font(.title3)
                                    
                                    VStack(alignment: .leading) {
                                        Text("API Key Not Configured")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Text("ChatYT requires a Gemini API key to analyze videos")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button("Set Key") {
                                        settingsPresented = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.yellow.opacity(0.1))
                    }
                    
                    Section {
                        // Conversation list header
                        HStack {
                            Text("Recent Conversations")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Text("\(conversations.count) videos")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        
                        // Conversations list
                        if conversations.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                    .padding()
                                
                                Text("No conversations yet")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Text("Enter a YouTube URL above to get started")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else {
                            ForEach(conversations) { conversation in
                                NavigationLink(value: conversation) {
                                    HStack {
                                        Image(systemName: "play.circle.fill")
                                            .font(.title3)
                                            .foregroundColor(.red)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(conversation.title ?? "Untitled Video")
                                                .font(.headline)
                                                .lineLimit(1)
                                            
                                            Text("Created: \(conversation.createdAt ?? Date(), formatter: dateFormatter)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(action: {
                                        withAnimation {
                                            viewContext.delete(conversation)
                                            try? viewContext.save()
                                        }
                                    }) {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            .onDelete(perform: deleteConversations)
                        }
                    }
                }
                .listStyle(.inset)
                .navigationDestination(for: Conversation.self) { conversation in
                    ChatView(conversation: conversation)
                }
            }
        } detail: {
            if let selectedConversation = selectedConversation {
                ChatView(conversation: selectedConversation)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("Welcome to ChatYT")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Select a conversation from the sidebar or enter a YouTube URL to start chatting")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    
                    Spacer()
                        .frame(height: 40)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "1.circle.fill")
                                .foregroundColor(.blue)
                            Text("Enter a YouTube URL")
                                .fontWeight(.semibold)
                        }
                        
                        HStack {
                            Image(systemName: "2.circle.fill")
                                .foregroundColor(.blue)
                            Text("ChatYT will analyze the video content")
                                .fontWeight(.semibold)
                        }
                        
                        HStack {
                            Image(systemName: "3.circle.fill")
                                .foregroundColor(.blue)
                            Text("Ask questions about the video")
                                .fontWeight(.semibold)
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .sheet(isPresented: $settingsPresented) {
            SettingsView()
        }
        .onAppear {
            checkAPIKeyStatus()
        }
        .onChange(of: settingsPresented) { _, isPresented in
            if !isPresented {
                // When settings sheet is dismissed, refresh API key status
                checkAPIKeyStatus()
            }
        }
    }
    
    private func processYoutubeUrl() {
        guard !youtubeURL.isEmpty else { return }
        
        isProcessingURL = true
        showUrlError = false
        urlErrorMessage = ""
        
        Task {
            if let id = extractVideoID(from: youtubeURL) {
                // First check if video is valid using YouTube Data API
                let (isValid, title, error) = await YouTubeDataService.shared.validateVideoID(id)
                
                if isValid {
                    await startNewConversationWithValidation(videoID: id, title: title)
                } else {
                    // Invalid video ID or API error
                    await MainActor.run {
                        showUrlError = true
                        if let errorMsg = error {
                            urlErrorMessage = "Error: \(errorMsg)"
                        } else {
                            urlErrorMessage = "This YouTube video does not exist or is not accessible."
                        }
                        isProcessingURL = false
                    }
                }
            } else {
                // Couldn't extract video ID
                await MainActor.run {
                    showUrlError = true
                    urlErrorMessage = "Invalid YouTube URL. Please enter a valid URL."
                    isProcessingURL = false
                }
            }
        }
    }
    
    private func extractVideoID(from url: String) -> String? {
        // Clean and prepare the URL for processing
        let sanitizedUrl = sanitizeUrl(url)
        
        // Handle YouTube Shorts URLs specially first
        if sanitizedUrl.contains("/shorts/") {
            return extractShortsVideoID(from: sanitizedUrl)
        }
        
        // First, check for standard video IDs with regex patterns for the most common formats
        let patterns = [
            "v=([\\w-]{11})",  // Standard YouTube URL with query parameter
            "youtu\\.be/([\\w-]{11})",  // Shortened URL
            "youtube\\.com/embed/([\\w-]{11})",  // Embed URL
            "youtube\\.com/v/([\\w-]{11})",  // Old embed format
            "youtube\\.com/watch/([\\w-]{11})",  // Another format
            "/shorts/([\\w-]{11})"  // YouTube Shorts
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: sanitizedUrl, options: [], range: NSRange(location: 0, length: sanitizedUrl.utf16.count)) {
                if let range = Range(match.range(at: 1), in: sanitizedUrl) {
                    let id = String(sanitizedUrl[range])
                    print("Extracted YouTube ID: \(id)")
                    return id
                }
            }
        }
        
        // If standard patterns fail, try URL parsing approach
        if let urlComponents = URLComponents(string: sanitizedUrl) {
            // Method 1: Check query parameters (most common case)
            if let queryItems = urlComponents.queryItems,
               let videoIDParam = queryItems.first(where: { $0.name == "v" })?.value {
                if videoIDParam.count == 11 {
                    print("Extracted YouTube ID from URL parameters: \(videoIDParam)")
                    return videoIDParam
                } else {
                    print("Found video ID parameter, but length isn't 11 characters: \(videoIDParam)")
                }
            }
            
            // Method 2: Handle youtu.be format
            if let host = urlComponents.host, host.contains("youtu.be") {
                let pathComponents = urlComponents.path.split(separator: "/").map { String($0) }
                if let lastComponent = pathComponents.last, lastComponent.count == 11 {
                    print("Extracted YouTube ID from youtu.be path: \(lastComponent)")
                    return lastComponent
                }
            }
            
            // Method 3: Check for shorts in the path
            if urlComponents.path.contains("/shorts/") {
                let components = urlComponents.path.components(separatedBy: "/shorts/")
                if components.count > 1 {
                    let shortsID = components[1].prefix(11)
                    if shortsID.count == 11 {
                        print("Extracted YouTube Shorts ID: \(shortsID)")
                        return String(shortsID)
                    }
                }
            }
        }
        
        // If all else fails, try direct URL validation with broader matching
        print("Standard extraction methods failed, trying direct URL validation")
        return attemptDirectUrlValidation(url: sanitizedUrl)
    }
    
    /// Sanitize and normalize YouTube URL
    private func sanitizeUrl(_ urlString: String) -> String {
        var cleanUrl = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add https:// if no protocol is specified
        if !cleanUrl.hasPrefix("http://") && !cleanUrl.hasPrefix("https://") {
            cleanUrl = "https://" + cleanUrl
        }
        
        // Handle mobile YouTube URLs
        cleanUrl = cleanUrl.replacingOccurrences(of: "m.youtube", with: "youtube")
        cleanUrl = cleanUrl.replacingOccurrences(of: "youtube.co.", with: "youtube.com")
        
        // Remove any tracking parameters or unnecessary query items
        if let urlComponents = URLComponents(string: cleanUrl),
           let queryItems = urlComponents.queryItems {
            // Keep only essential query parameters
            let essentialParams = ["v", "list"]
            let filteredQueryItems = queryItems.filter { item in
                return essentialParams.contains(item.name)
            }
            
            var components = urlComponents
            components.queryItems = filteredQueryItems.isEmpty ? nil : filteredQueryItems
            
            if let cleanerUrl = components.url?.absoluteString {
                return cleanerUrl
            }
        }
        
        return cleanUrl
    }
    
    /// Extract video ID from YouTube Shorts URL
    private func extractShortsVideoID(from url: String) -> String? {
        // Extract ID from /shorts/VIDEO_ID format
        if let range = url.range(of: "/shorts/([\\w-]{11})", options: .regularExpression) {
            let matched = url[range]
            if let idStartIndex = matched.lastIndex(of: "/") {
                let idIndex = matched.index(after: idStartIndex)
                let id = matched[idIndex...]
                if id.count == 11 {
                    print("Extracted YouTube Shorts ID: \(id)")
                    return String(id)
                }
            }
        }
        return nil
    }
    
    private func attemptDirectUrlValidation(url originalUrl: String) -> String? {
        // Extract a video ID to try using multiple approaches
        var possibleIds = [String]()
        
        // Approach 1: Standard watch URL
        if originalUrl.contains("watch?v=") {
            let components = originalUrl.components(separatedBy: "watch?v=")
            if components.count > 1, let id = components.last?.components(separatedBy: "&").first, id.count == 11 {
                possibleIds.append(id)
            }
        }
        
        // Approach 2: Shortened youtu.be URL
        if originalUrl.contains("youtu.be/") {
            let components = originalUrl.components(separatedBy: "youtu.be/")
            if components.count > 1, let id = components.last?.components(separatedBy: "?").first, id.count == 11 {
                possibleIds.append(id)
            }
        }
        
        // Approach 3: Embed URL
        if originalUrl.contains("/embed/") {
            let components = originalUrl.components(separatedBy: "/embed/")
            if components.count > 1, let id = components.last?.components(separatedBy: "?").first, id.count == 11 {
                possibleIds.append(id)
            }
        }
        
        // Approach 4: Old embed format
        if originalUrl.contains("/v/") {
            let components = originalUrl.components(separatedBy: "/v/")
            if components.count > 1, let id = components.last?.components(separatedBy: "?").first, id.count == 11 {
                possibleIds.append(id)
            }
        }
        
        // Approach 5: YouTube Shorts
        if originalUrl.contains("/shorts/") {
            let components = originalUrl.components(separatedBy: "/shorts/")
            if components.count > 1, let id = components.last?.components(separatedBy: "?").first, id.count == 11 {
                possibleIds.append(id)
            }
        }
        
        // Approach 6: Try to extract any 11-character path component that matches the pattern
        if let url = URL(string: originalUrl) {
            let pathComponents = url.pathComponents
            for component in pathComponents {
                if component.count == 11 && component.range(of: "^[\\w-]{11}$", options: .regularExpression) != nil {
                    possibleIds.append(component)
                }
            }
        }
        
        // Filter IDs to make sure they match the YouTube ID pattern
        let validIds = possibleIds.filter { id in
            id.count == 11 && id.range(of: "^[\\w-]{11}$", options: .regularExpression) != nil
        }
        
        if let firstValidId = validIds.first {
            print("Found valid YouTube ID using fallback method: \(firstValidId)")
            return firstValidId
        }
        
        // Last resort: Look for anything that looks like a YouTube ID in the URL
        let pattern = "[\\w-]{11}"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: originalUrl, options: [], range: NSRange(location: 0, length: originalUrl.utf16.count)),
           let range = Range(match.range, in: originalUrl) {
            let potentialId = String(originalUrl[range])
            print("Last resort ID extraction: \(potentialId)")
            return potentialId
        }
        
        return nil
    }
    
    private func startNewConversationWithValidation(videoID: String, title: String?) async {
        // Create the conversation with video details from YouTube if available
        let newConversation = Conversation(context: viewContext)
        newConversation.videoID = videoID
        newConversation.createdAt = Date()
        
        if let title = title {
            newConversation.title = title
        } else {
            // Try to get video details as a fallback
            if let details = await YouTubeDataService.shared.extractVideoDetails(videoID) {
                newConversation.title = details["title"] ?? "YouTube Video: \(videoID)"
            } else {
                newConversation.title = "YouTube Video: \(videoID)"
            }
        }
        
        do {
            try viewContext.save()
            
            await MainActor.run {
                withAnimation {
                    self.selectedConversation = newConversation
                }
                
                // Clear the input and processing state
                youtubeURL = ""
                isProcessingURL = false
            }
        } catch {
            let nsError = error as NSError
            print("Error creating conversation: \(nsError), \(nsError.userInfo)")
            
            await MainActor.run {
                isProcessingURL = false
            }
        }
    }
    
    private func deleteConversations(offsets: IndexSet) {
        withAnimation {
            offsets.map { conversations[$0] }.forEach(viewContext.delete)
            
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                print("Error deleting conversations: \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    private func checkAPIKeyStatus() {
        apiKeyConfigured = GeminiService.shared.isAPIKeySet
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}

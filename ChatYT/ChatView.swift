//
//  ChatView.swift
//  ChatYT
//
//  Created by Jack Felke on 3/24/25.
//

import SwiftUI
import WebKit
import CoreData
import Combine
import UniformTypeIdentifiers

struct ChatView: View {
    @ObservedObject var conversation: Conversation
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest private var messages: FetchedResults<Message>
    @State private var currentInput: String = ""
    @State private var isProcessing = false
    @State private var showExportSheet = false
    @State private var exportFormat: FileFormat = .markdown
    @State private var scrollViewProxy: ScrollViewProxy? = nil
    @State private var initialSummaryStarted = false
    @State private var loadingMessage: String = "Analyzing video content..."
    
    // YouTube video player
    @State private var showVideoPlayer = false
    @State private var videoMetadata: [String: String]? = nil
    
    init(conversation: Conversation) {
        self.conversation = conversation
        
        // Custom fetch request to get messages for this conversation, sorted by timestamp
        _messages = FetchRequest<Message>(
            sortDescriptors: [NSSortDescriptor(keyPath: \Message.timestamp, ascending: true)],
            predicate: NSPredicate(format: "conversation == %@", conversation),
            animation: .default
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with video information and controls
            VStack(spacing: 2) {
                HStack {
                    // Video title and info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.title ?? "Untitled Conversation")
                            .font(.headline)
                            .fontWeight(.bold)
                            .lineLimit(1)
                        
                        if let videoID = conversation.videoID {
                            HStack(spacing: 4) {
                                Text("ID: \(videoID)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Circle()
                                    .fill(Color.secondary)
                                    .frame(width: 3, height: 3)
                                
                                Text("Created: \(conversation.createdAt ?? Date(), formatter: dateFormatter)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Action buttons
                    HStack(spacing: 12) {
                        Button(action: { showVideoPlayer.toggle() }) {
                            Label("View Video", systemImage: "play.rectangle.fill")
                                .labelStyle(.iconOnly)
                                .font(.title3)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.blue)
                        .help("Watch Video")
                        
                        Button(action: { showExportSheet = true }) {
                            Label("Export", systemImage: "square.and.arrow.up")
                                .labelStyle(.iconOnly)
                                .font(.title3)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.blue)
                        .help("Export Conversation")
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                Divider()
            }
            .background(Color(NSColor.windowBackgroundColor))
            
            // Chat messages scrolling area
            ScrollViewReader { scrollView in
                ScrollView {
                    LazyVStack(alignment: .center, spacing: 16) {
                        // Only show messages if we have any or we're still in initial loading
                        if !messages.isEmpty || initialSummaryStarted {
                            ForEach(messages, id: \.self) { message in
                                MessageView(message: message)
                                    .id(message.objectID)
                                    .padding(.horizontal)
                                    .transition(.opacity)
                            }
                            
                            // Show typing indicator when processing
                            if isProcessing {
                                HStack(spacing: 12) {
                                    Image(systemName: "ellipsis")
                                        .font(.system(.title3, design: .rounded))
                                        .foregroundColor(.secondary)
                                    
                                    Text(loadingMessage)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(16)
                                .padding(.horizontal)
                            }
                        } else {
                            // Show a prominent loading indicator when no messages are present yet
                            VStack(spacing: 20) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(1.5)
                                    .padding()
                                
                                Text("Connecting to YouTube...")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Text("Getting video content for analysis")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.vertical, 100)
                        }
                    }
                    .padding(.vertical)
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: messages.count) { oldValue, newValue in
                    scrollToBottom()
                }
                .onAppear {
                    scrollViewProxy = scrollView
                    scrollToBottom()
                    if !initialSummaryStarted {
                        initializeChat()
                    }
                }
            }
            
            // Message input area
            VStack(spacing: 0) {
                Divider()
                
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(NSColor.controlBackgroundColor))
                        
                        TextField("Type your message...", text: $currentInput)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .disabled(isProcessing)
                            .onSubmit {
                                if !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing {
                                    sendMessage()
                                }
                            }
                    }
                    .frame(height: 40)
                    
                    Button(action: sendMessage) {
                        ZStack {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: "arrow.up")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                    }
                    .disabled(currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                }
                .padding(.vertical, 12)
                .padding(.horizontal)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .sheet(isPresented: $showVideoPlayer) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    
                    Text("YouTube Video")
                        .font(.headline)
                        .padding()
                    
                    Spacer()
                    
                    Button("Close") {
                        showVideoPlayer = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding()
                }
                .background(Color(NSColor.windowBackgroundColor))
                
                if let videoID = conversation.videoID {
                    YouTubePlayerView(videoID: videoID)
                        .frame(width: 800, height: 450)
                }
            }
            .frame(width: 800, height: 500)
        }
        .sheet(isPresented: $showExportSheet) {
            ExportView(conversation: conversation, format: $exportFormat)
        }
        .onAppear {
            if messages.isEmpty {
                initializeChat()
            }
        }
    }
    
    private func initializeChat() {
        // Check if API key is set
        if !GeminiService.shared.isAPIKeySet {
            addMessage(content: "⚠️ Gemini API key not configured. Please set it in settings before continuing.", isUser: false)
            return
        }
        
        initialSummaryStarted = true
        isProcessing = true
        loadingMessage = "Analyzing video content..."
        
        // Get video metadata from YouTube Data API
        Task {
            if let videoID = conversation.videoID {
                // Try to get video details
                videoMetadata = await YouTubeDataService.shared.extractVideoDetails(videoID)
                
                // Update conversation title if available and not already set with a meaningful title
                if let title = videoMetadata?["title"], 
                   conversation.title == nil || conversation.title?.hasPrefix("YouTube Video:") == true {
                    conversation.title = title
                    try? viewContext.save()
                }
                
                // Add welcome message
                let videoTitle = videoMetadata?["title"] ?? "this YouTube video"
                addMessage(content: "Welcome to ChatYT! I'll help you analyze '\(videoTitle)'.", isUser: false)
                
                // Build an enhanced prompt with video metadata
                var enhancedPrompt = ""
                if let metadata = videoMetadata {
                    enhancedPrompt = "Summarize the following YouTube video:\n"
                    enhancedPrompt += "Title: \(metadata["title"] ?? "Unknown")\n"
                    enhancedPrompt += "Channel: \(metadata["channelTitle"] ?? "Unknown")\n"
                    if let description = metadata["description"], !description.isEmpty {
                        enhancedPrompt += "Description: \(description)\n"
                    }
                    enhancedPrompt += "Video ID: \(videoID)"
                } else {
                    // Fallback to default prompt
                    let settings = getOrCreateSettings()
                    enhancedPrompt = settings.promptTemplate?.replacingOccurrences(of: "{videoID}", with: videoID) ?? 
                        "Summarize the following YouTube video in detail. Video ID: \(videoID)"
                }
                
                // Generate the initial summary
                loadingMessage = "Generating summary..."
                let initialResponse = await GeminiService.shared.processYouTubeVideo(
                    videoID: videoID,
                    prompt: enhancedPrompt
                )
                
                if let response = initialResponse {
                    addMessage(content: response, isUser: false)
                } else {
                    addMessage(content: "I couldn't generate a summary for this video. Please try again or ask a specific question about the video.", isUser: false)
                }
            } else {
                addMessage(content: "No video ID found. Please try again with a valid YouTube video.", isUser: false)
            }
            isProcessing = false
        }
    }
    
    private func sendMessage() {
        // Check if API key is set
        if !GeminiService.shared.isAPIKeySet {
            addMessage(content: "⚠️ Gemini API key not configured. Please set it in settings before continuing.", isUser: false)
            return
        }
        
        let userMessage = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        
        // Add user message to chat
        addMessage(content: userMessage, isUser: true)
        currentInput = ""
        
        // Generate response
        isProcessing = true
        loadingMessage = "Thinking..."
        
        Task {
            let prompt = createContextualPrompt(userMessage)
            if let response = await generateGeminiResponse(prompt: prompt) {
                addMessage(content: response, isUser: false)
            } else {
                addMessage(content: "I couldn't generate a response. Please try again.", isUser: false)
            }
            isProcessing = false
        }
    }
    
    private func addMessage(content: String, isUser: Bool) {
        let newMessage = Message(context: viewContext)
        newMessage.content = content
        newMessage.isUser = isUser
        newMessage.timestamp = Date()
        newMessage.conversation = conversation
        
        do {
            try viewContext.save()
        } catch {
            print("Error saving message: \(error.localizedDescription)")
        }
    }
    
    private func createContextualPrompt(_ userMessage: String) -> String {
        // Create a prompt that includes context from previous messages
        guard let videoID = conversation.videoID else {
            return userMessage
        }
        
        var contextualPrompt = "For YouTube video"
        
        // Add metadata if available
        if let metadata = videoMetadata {
            contextualPrompt += " titled '\(metadata["title"] ?? "Unknown")'"
            if let channelTitle = metadata["channelTitle"] {
                contextualPrompt += " by \(channelTitle)"
            }
        } 
        
        contextualPrompt += " with ID \(videoID), the user asks: \(userMessage)\n\n"
        contextualPrompt += "Previous conversation context:\n"
        
        // Add up to 10 previous message pairs for context
        let recentMessagePairs = Array(messages.suffix(10))
        for message in recentMessagePairs {
            let prefix = message.isUser ? "User" : "Assistant"
            contextualPrompt += "\(prefix): \(message.content ?? "")\n"
        }
        
        return contextualPrompt
    }
    
    private func generateGeminiResponse(prompt: String) async -> String? {
        // Use the GeminiService to generate a response
        return await GeminiService.shared.generateResponse(prompt: prompt)
    }
    
    private func getOrCreateSettings() -> Settings {
        let fetchRequest: NSFetchRequest<Settings> = Settings.fetchRequest()
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            if let settings = results.first {
                return settings
            }
        } catch {
            print("Error fetching settings: \(error.localizedDescription)")
        }
        
        // Create default settings if none exist
        let newSettings = Settings(context: viewContext)
        newSettings.promptTemplate = "Summarize the following YouTube video in detail. Video ID: {videoID}"
        newSettings.exportFileFormat = FileFormat.markdown.rawValue
        
        do {
            try viewContext.save()
        } catch {
            print("Error creating settings: \(error.localizedDescription)")
        }
        
        return newSettings
    }
    
    private func scrollToBottom() {
        if let lastMessage = messages.last, let scrollView = scrollViewProxy {
            withAnimation {
                scrollView.scrollTo(lastMessage.objectID, anchor: .bottom)
            }
        }
    }
}

// YouTube video player using WKWebView
struct YouTubePlayerView: NSViewRepresentable {
    let videoID: String
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        loadVideo(in: webView)
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        loadVideo(in: webView)
    }
    
    private func loadVideo(in webView: WKWebView) {
        guard let url = URL(string: "https://www.youtube.com/embed/\(videoID)") else { return }
        webView.load(URLRequest(url: url))
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("YouTube video loaded")
        }
    }
}

// Message bubble view
struct MessageView: View {
    let message: Message
    
    var body: some View {
        HStack(alignment: .top) {
            if !message.isUser {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundColor(.blue)
                    .padding(.top, 6)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                HStack {
                    if message.isUser {
                        Spacer()
                    }
                    
                    VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                        Text(message.isUser ? "You" : "ChatYT")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(message.isUser ? .blue : .secondary)
                        
                        Text(message.content ?? "")
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(message.isUser 
                                ? Color.blue.opacity(0.15) 
                                : Color(NSColor.controlBackgroundColor))
                    .cornerRadius(16)
                    
                    if !message.isUser {
                        Spacer()
                    }
                }
                
                Text(message.timestamp ?? Date(), style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            }
            
            if message.isUser {
                Image(systemName: "person.circle.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
                    .padding(.top, 6)
            }
        }
    }
}

// Add date formatter
private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

enum FileFormat: String, CaseIterable, Identifiable {
    case json = "JSON"
    case markdown = "Markdown"
    case text = "Text"
    
    var id: String { self.rawValue }
    
    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .markdown: return "md"
        case .text: return "txt"
        }
    }
    
    var mimeType: String {
        switch self {
        case .json: return "application/json"
        case .markdown: return "text/markdown"
        case .text: return "text/plain"
        }
    }
}

struct ExportView: View {
    let conversation: Conversation
    @Binding var format: FileFormat
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var exportLocation: URL?
    @FetchRequest private var messages: FetchedResults<Message>
    
    init(conversation: Conversation, format: Binding<FileFormat>) {
        self.conversation = conversation
        self._format = format
        
        _messages = FetchRequest<Message>(
            sortDescriptors: [NSSortDescriptor(keyPath: \Message.timestamp, ascending: true)],
            predicate: NSPredicate(format: "conversation == %@", conversation),
            animation: .default
        )
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Export Conversation")
                .font(.title)
            
            Picker("Format", selection: $format) {
                ForEach(FileFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            Button("Export") {
                exportConversation()
            }
            .buttonStyle(.borderedProminent)
            
            Text("Preview:")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            
            ScrollView {
                Text(previewContent)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 600, height: 500)
    }
    
    private var previewContent: String {
        switch format {
        case .json:
            return formatAsJSON()
        case .markdown:
            return formatAsMarkdown()
        case .text:
            return formatAsText()
        }
    }
    
    private func exportConversation() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .plainText]
        panel.nameFieldStringValue = "conversation-\(Date().timeIntervalSince1970).\(format.fileExtension)"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try previewContent.write(to: url, atomically: true, encoding: .utf8)
                    print("Conversation exported to: \(url.path)")
                } catch {
                    print("Error exporting conversation: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func formatAsJSON() -> String {
        let messageArray = messages.map { message -> [String: Any] in
            return [
                "content": message.content ?? "",
                "isUser": message.isUser,
                "timestamp": ISO8601DateFormatter().string(from: message.timestamp ?? Date())
            ]
        }
        
        let conversationDict: [String: Any] = [
            "title": conversation.title ?? "Untitled Conversation",
            "videoID": conversation.videoID ?? "",
            "createdAt": ISO8601DateFormatter().string(from: conversation.createdAt ?? Date()),
            "messages": messageArray
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: conversationDict, options: [.prettyPrinted]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "Error: Could not format as JSON"
    }
    
    private func formatAsMarkdown() -> String {
        var markdown = "# \(conversation.title ?? "Untitled Conversation")\n\n"
        markdown += "**Video ID:** \(conversation.videoID ?? "Unknown")\n"
        markdown += "**Created:** \(conversation.createdAt ?? Date())\n\n"
        markdown += "## Conversation\n\n"
        
        for message in messages {
            let author = message.isUser ? "**User**" : "**Assistant**"
            markdown += "\(author): \(message.content ?? "")\n\n"
        }
        
        return markdown
    }
    
    private func formatAsText() -> String {
        var text = "\(conversation.title ?? "Untitled Conversation")\n"
        text += "Video ID: \(conversation.videoID ?? "Unknown")\n"
        text += "Created: \(conversation.createdAt ?? Date())\n\n"
        text += "CONVERSATION:\n\n"
        
        for message in messages {
            let author = message.isUser ? "User" : "Assistant"
            text += "\(author): \(message.content ?? "")\n\n"
        }
        
        return text
    }
}

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let conversation = Conversation(context: context)
        conversation.title = "Sample Conversation"
        conversation.videoID = "dQw4w9WgXcQ"
        conversation.createdAt = Date()
        
        let message1 = Message(context: context)
        message1.content = "What is this video about?"
        message1.isUser = true
        message1.timestamp = Date()
        message1.conversation = conversation
        
        let message2 = Message(context: context)
        message2.content = "This video is 'Never Gonna Give You Up' by Rick Astley, a popular music video from the 1980s that became an internet meme known as 'Rickrolling'."
        message2.isUser = false
        message2.timestamp = Date().addingTimeInterval(60)
        message2.conversation = conversation
        
        try? context.save()
        
        return ChatView(conversation: conversation)
            .environment(\.managedObjectContext, context)
    }
} 
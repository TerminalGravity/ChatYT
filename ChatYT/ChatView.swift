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
    @State private var isLocalFile = false
    @State private var localFilePath: String? = nil
    @State private var localFileName: String? = nil
    
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
                    
                    Text(isLocalFile ? "Media Player" : "YouTube Video")
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
                    if isLocalFile {
                        LocalMediaPlayerView(title: conversation.title ?? "Local Media")
                            .frame(width: 800, height: 450)
                    } else {
                        YouTubePlayerView(videoID: videoID)
                            .frame(width: 800, height: 450)
                    }
                }
            }
            .frame(width: 800, height: 500)
        }
        .sheet(isPresented: $showExportSheet) {
            ExportView(conversation: conversation, format: $exportFormat)
        }
        .onAppear {
            // Check if this is a local file
            if let videoID = conversation.videoID {
                isLocalFile = videoID.hasPrefix("local_file_")
            }
            
            if messages.isEmpty {
                initializeChat()
            }
        }
    }
    
    private func initializeChat() {
        initialSummaryStarted = true
        isProcessing = true
        
        Task {
            // Set loading message based on content type
            if let localFilePath = conversation.localFilePath, !localFilePath.isEmpty {
                isLocalFile = true
                self.localFilePath = localFilePath
                self.localFileName = conversation.localFileName
                loadingMessage = "Analyzing local video file..."
            } else {
                isLocalFile = false
                loadingMessage = "Analyzing YouTube content..."
            }
            
            // Start analysis based on content type
            if isLocalFile, let filePath = localFilePath {
                await analyzeLocalVideo(filePath: filePath, fileName: localFileName ?? "")
            } else if let videoID = conversation.videoID {
                await analyzeYouTubeVideo(videoID: videoID)
            } else {
                // No content to analyze
                createSystemMessage(content: "No video content to analyze. Please ask a question to start a conversation.")
                isProcessing = false
            }
        }
    }
    
    private func analyzeYouTubeVideo(videoID: String) async {
        // Default prompt for YouTube analysis
        let defaultPrompt = "Please analyze this YouTube video with ID {videoID}. Provide a detailed summary of its content, key topics, main arguments or points, and any notable information. If it's a long video, focus on the most important parts."
        
        let prompt = conversation.analysisPrompt ?? defaultPrompt
        
        // Fetch video data and summary from Gemini
        if let response = await GeminiService.shared.processYouTubeVideo(videoID: videoID, prompt: prompt) {
            // Create a message with the response
            createSystemMessage(content: response)
        } else {
            // Handle error case
            createSystemMessage(content: "⚠️ I couldn't analyze this YouTube video. Please check if the video is available or try a different video.")
        }
        
        // End loading state
        isProcessing = false
    }
    
    private func analyzeLocalVideo(filePath: String, fileName: String) async {
        // Default prompt for local video analysis
        let defaultPrompt = "Please analyze this local video file. Provide any information you can extract from its metadata and suggest possible ways I can interact with this content."
        
        let prompt = conversation.analysisPrompt ?? defaultPrompt
        
        // Fetch analysis from Gemini for the local file
        if let response = await GeminiService.shared.processLocalVideo(filePath: filePath, fileName: fileName, prompt: prompt) {
            // Create a message with the response
            createSystemMessage(content: response)
        } else {
            // Handle error case
            createSystemMessage(content: "⚠️ I couldn't analyze this local video file. Please check if the file is accessible or try a different file.")
        }
        
        // End loading state
        isProcessing = false
    }
    
    private func sendMessage() {
        guard !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Create user message
        let userMessage = Message(context: viewContext)
        userMessage.id = UUID()
        userMessage.content = currentInput
        userMessage.timestamp = Date()
        userMessage.isFromUser = true
        userMessage.conversation = conversation
        
        // Update conversation's modified timestamp
        conversation.modifiedAt = Date()
        
        // Clear input field and save
        saveContext()
        currentInput = ""
        
        // Start processing system response
        isProcessing = true
        loadingMessage = "Generating response..."
        
        Task {
            // Handle message differently depending on content type
            if isLocalFile, let filePath = localFilePath {
                // For local files, include the file path in the prompt context
                let contextPrompt = "The user is asking about a local video file: \"\(localFileName ?? "Unknown")\". Path: \(filePath). " + (userMessage.content ?? "")
                await generateResponse(prompt: contextPrompt)
            } else if let videoID = conversation.videoID {
                // For YouTube videos, include video ID in context
                let contextPrompt = "The user is asking about YouTube video ID: \(videoID). " + (userMessage.content ?? "")
                await generateResponse(prompt: contextPrompt)
            } else {
                // Generic conversation without specific content
                await generateResponse(prompt: userMessage.content ?? "")
            }
        }
    }
    
    private func generateResponse(prompt: String) async {
        // Get response from Gemini service
        if let response = await GeminiService.shared.generateResponse(prompt: prompt) {
            // Create a message with the response
            createSystemMessage(content: response)
        } else {
            // Handle error case
            createSystemMessage(content: "⚠️ I couldn't generate a response at this time. Please try again later.")
        }
        
        // End loading state
        isProcessing = false
    }
    
    private func createSystemMessage(content: String) {
        // Ensure we're using the conversation's managed object context
        let context = conversation.managedObjectContext ?? viewContext
        
        // Create message in the same context as the conversation
        let newMessage = Message(context: context)
        newMessage.content = content
        newMessage.isFromUser = false
        newMessage.timestamp = Date()
        newMessage.conversation = conversation
        
        do {
            try context.save()
        } catch {
            print("Error saving message: \(error.localizedDescription)")
        }
    }
    
    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            print("Error saving context: \(error.localizedDescription)")
        }
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
            if !message.isFromUser {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundColor(.blue)
                    .padding(.top, 6)
            }
            
            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
                HStack {
                    if message.isFromUser {
                        Spacer()
                    }
                    
                    VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 8) {
                        Text(message.isFromUser ? "You" : "ChatYT")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(message.isFromUser ? .blue : .secondary)
                        
                        Text(message.content ?? "")
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(message.isFromUser 
                                ? Color.blue.opacity(0.15) 
                                : Color(NSColor.controlBackgroundColor))
                    .cornerRadius(16)
                    
                    if !message.isFromUser {
                        Spacer()
                    }
                }
                
                Text(message.timestamp ?? Date(), style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            }
            
            if message.isFromUser {
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
                "isUser": message.isFromUser,
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
            let author = message.isFromUser ? "**User**" : "**Assistant**"
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
            let author = message.isFromUser ? "User" : "Assistant"
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
        message1.isFromUser = true
        message1.timestamp = Date()
        message1.conversation = conversation
        
        let message2 = Message(context: context)
        message2.content = "This video is 'Never Gonna Give You Up' by Rick Astley, a popular music video from the 1980s that became an internet meme known as 'Rickrolling'."
        message2.isFromUser = false
        message2.timestamp = Date().addingTimeInterval(60)
        message2.conversation = conversation
        
        try? context.save()
        
        return ChatView(conversation: conversation)
            .environment(\.managedObjectContext, context)
    }
}

struct LocalMediaPlayerView: View {
    let title: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "film")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.title)
            
            Text("Local media player functionality would be implemented here")
                .foregroundColor(.secondary)
            
            Text("This would integrate with AVKit for playback of local media files")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
} 
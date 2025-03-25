# ChatYT - YouTube Video Summarization with Gemini AI

ChatYT is a macOS application that uses Google's Gemini AI to analyze and chat about YouTube videos. The app allows you to enter a YouTube video URL, generates a summary of the video content, and then lets you have a conversation with the AI about the video.

## Features

- **YouTube Video Analysis**: Analyze any YouTube video by entering its URL
- **AI Summarization**: Get detailed summaries of video content using Gemini AI
- **Interactive Chat**: Ask questions and get insights about the video content
- **Persistent Conversations**: All conversations are saved using Core Data
- **Export Options**: Export your conversations in multiple formats (JSON, Markdown, Text)
- **Customizable Prompts**: Customize the AI prompts used for summarization
- **Embedded Video Player**: Watch the YouTube video directly within the app

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later (for development)
- A Gemini API key

## Setup

1. Clone or download this repository
2. Open the project in Xcode
3. Build and run the application
4. In the settings screen, enter your Gemini API key
   - You can get an API key from [Google AI Studio](https://makersuite.google.com/app/apikey)

## Usage

1. **Start a Conversation**:
   - Enter a YouTube URL in the text field
   - Press Enter or click the arrow button
   - The app will generate a summary of the video

2. **Chat About the Video**:
   - Type your questions or comments in the chat input field
   - Gemini AI will respond with insights about the video content

3. **View the Video**:
   - Click the "View Video" button to open the YouTube video player

4. **Export Conversations**:
   - Click the "Export" button to save your conversation
   - Choose from JSON, Markdown, or Text formats

5. **Customize Settings**:
   - Click the "Settings" button to open the settings view
   - Set your Gemini API key
   - Customize the prompt template
   - Configure default export preferences

## Development

### Architecture

- **SwiftUI**: User interface
- **Core Data**: Persistence of conversations and settings
- **Gemini AI API**: AI-powered chat and summarization
- **WKWebView**: YouTube video playback

### Core Components

- **ContentView**: Main navigation and YouTube URL input
- **ChatView**: Conversation interface with the AI
- **SettingsView**: Configuration options
- **GeminiService**: Integration with the Gemini AI API
- **Data Model**: Core Data entities for conversations, messages, and settings

## Extending the App

You can extend the app's functionality by:

1. **Implementing YouTube Data API**: Fetch video metadata and transcripts
2. **Adding Authentication**: Support for user accounts
3. **Enhancing Export Options**: Additional export formats or cloud integration
4. **Implementing History Search**: Search functionality for past conversations
5. **Supporting Multiple Video Sources**: Add support for other video platforms

## Privacy and Security

- The app stores your Gemini API key in UserDefaults
- No data is sent to external servers except for API calls to Google's Gemini AI
- Chat history is stored locally on your device using Core Data

## License

This project is for personal use.

## Acknowledgments

- Google Gemini AI for the language model capabilities
- YouTube for video content
- Apple for SwiftUI and Core Data frameworks 
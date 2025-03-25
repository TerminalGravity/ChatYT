//
//  SettingsView.swift
//  ChatYT
//
//  Created by Jack Felke on 3/24/25.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var promptTemplate: String = ""
    @State private var exportFileFormat: FileFormat = .markdown
    @State private var exportLocation: URL?
    @State private var geminiApiKey: String = ""
    @State private var showExportLocationPicker = false
    
    @FetchRequest(
        sortDescriptors: [],
        animation: .default)
    private var settingsResults: FetchedResults<Settings>
    
    private var settings: Settings? {
        return settingsResults.first
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Configure ChatYT to work with Gemini API and customize your experience")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    // API Key Section
                    GroupBox(label: 
                        Label("Gemini API Configuration", systemImage: "key.fill")
                            .font(.headline)
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Enter your Gemini API key below. This is required for the app to function.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            SecureField("API Key", text: $geminiApiKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding(.vertical, 4)
                            
                            HStack {
                                Link(destination: URL(string: "https://makersuite.google.com/app/apikey")!) {
                                    Label("Get API Key", systemImage: "arrow.up.right.square")
                                        .font(.callout)
                                }
                                
                                Spacer()
                                
                                Text(geminiApiKey.isEmpty ? "Not configured" : "Configured")
                                    .font(.caption)
                                    .foregroundColor(geminiApiKey.isEmpty ? .red : .green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(geminiApiKey.isEmpty ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                        .padding()
                    }
                    .padding(.horizontal)
                    
                    // Prompt Template Section
                    GroupBox(label: 
                        Label("Prompt Configuration", systemImage: "text.bubble.fill")
                            .font(.headline)
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Customize how ChatYT analyzes YouTube videos")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("Use {videoID} as a placeholder for the YouTube video ID.")
                                .font(.caption)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                            
                            TextEditor(text: $promptTemplate)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 120)
                                .padding(4)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .padding()
                    }
                    .padding(.horizontal)
                    
                    // Export Preferences Section
                    GroupBox(label: 
                        Label("Export Preferences", systemImage: "square.and.arrow.up.fill")
                            .font(.headline)
                    ) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Configure how conversations are exported")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Default Format")
                                    .font(.callout)
                                
                                Picker("", selection: $exportFileFormat) {
                                    ForEach(FileFormat.allCases) { format in
                                        Text(format.rawValue).tag(format)
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Default Save Location")
                                    .font(.callout)
                                
                                HStack {
                                    Text(exportLocation?.lastPathComponent ?? "Not selected")
                                        .font(.callout)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(Color(NSColor.textBackgroundColor))
                                        .cornerRadius(6)
                                    
                                    Button(action: {
                                        showExportLocationPicker = true
                                    }) {
                                        Text("Browse")
                                            .fontWeight(.medium)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .padding()
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            
            // Footer with save button
            VStack {
                Divider()
                
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Save Settings") {
                        saveSettings()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .frame(minWidth: 600, minHeight: 600)
        .onAppear(perform: loadSettings)
        .sheet(isPresented: $showExportLocationPicker) {
            ExportLocationPicker(selectedURL: $exportLocation)
        }
    }
    
    private func loadSettings() {
        // Load settings from Core Data
        let fetchRequest: NSFetchRequest<Settings> = Settings.fetchRequest()
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            if let settings = results.first {
                self.promptTemplate = settings.promptTemplate ?? "Summarize the following YouTube video in detail. Video ID: {videoID}"
                if let formatString = settings.exportFileFormat,
                   let format = FileFormat(rawValue: formatString) {
                    self.exportFileFormat = format
                }
                self.exportLocation = settings.exportLocation
                // Load the API key from GeminiService
                self.geminiApiKey = GeminiService.shared.getAPIKey()
            } else {
                // Create default settings if none exist
                self.promptTemplate = "Summarize the following YouTube video in detail. Video ID: {videoID}"
                self.geminiApiKey = GeminiService.shared.getAPIKey()
                createDefaultSettings()
            }
        } catch {
            print("Error loading settings: \(error.localizedDescription)")
            self.promptTemplate = "Summarize the following YouTube video in detail. Video ID: {videoID}"
            self.geminiApiKey = GeminiService.shared.getAPIKey()
        }
    }
    
    private func saveSettings() {
        // Save API key to GeminiService
        if !geminiApiKey.isEmpty {
            GeminiService.shared.setAPIKey(geminiApiKey)
        }
        
        if let settings = self.settings {
            // Update existing settings
            settings.promptTemplate = promptTemplate
            settings.exportFileFormat = exportFileFormat.rawValue
            settings.exportLocation = exportLocation
        } else {
            // Create new settings
            let newSettings = Settings(context: viewContext)
            newSettings.promptTemplate = promptTemplate
            newSettings.exportFileFormat = exportFileFormat.rawValue
            newSettings.exportLocation = exportLocation
        }
        
        do {
            try viewContext.save()
            print("Settings saved successfully")
        } catch {
            print("Error saving settings: \(error.localizedDescription)")
        }
    }
    
    private func createDefaultSettings() {
        let newSettings = Settings(context: viewContext)
        newSettings.promptTemplate = "Summarize the following YouTube video in detail. Video ID: {videoID}"
        newSettings.exportFileFormat = FileFormat.markdown.rawValue
        
        do {
            try viewContext.save()
        } catch {
            print("Error creating default settings: \(error.localizedDescription)")
        }
    }
}

struct ExportLocationPicker: View {
    @Binding var selectedURL: URL?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Select Default Save Location")
                .font(.headline)
                .padding(.top)
            
            Text("Choose a folder where your exported conversations will be saved by default")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Select Folder") {
                    selectFolder()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom)
        }
        .frame(width: 400, height: 150)
        .onAppear {
            // Slight delay before opening the panel to ensure the sheet is fully displayed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                selectFolder()
            }
        }
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder for saving exported conversations"
        panel.prompt = "Select Folder"
        
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    selectedURL = url
                }
                dismiss()
            }
        } else {
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    selectedURL = url
                }
                dismiss()
            }
        }
    }
}

// Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
} 
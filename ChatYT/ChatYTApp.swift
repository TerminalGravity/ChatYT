//
//  ChatYTApp.swift
//  ChatYT
//
//  Created by Jack Felke on 3/24/25.
//

import SwiftUI

@main
struct ChatYTApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

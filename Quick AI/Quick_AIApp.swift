//
//  Quick_AIApp.swift
//  Quick AI
//
//  Created by Camin McCluskey on 05/02/2026.
//

import SwiftUI
import CoreData

@main
struct Quick_AIApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

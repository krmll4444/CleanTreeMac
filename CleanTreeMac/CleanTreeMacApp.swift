//
//  CleanTreeMacApp.swift
//  CleanTreeMac
//
//  Created by Олег Курей on 13.06.2026.
//

import SwiftUI
import CoreData

@main
struct CleanTreeMacApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

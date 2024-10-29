//
//  ExtendTimer.swift
//  podcasts
//
//  Created by Ruan Viljoen on 2024/08/10.
//  Copyright © 2024 Shifty Jelly. All rights reserved.
//

import AppIntents
import WidgetKit

@available(iOS 17, *)

struct ExtendTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Extend Timer"

    func perform() async throws -> some IntentResult {
        // Implement the logic to increase the value here
        incrementTimer()
        return .result()
    }
}

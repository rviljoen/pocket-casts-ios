//
//  SleepTimerAttributes.swift
//  podcasts
//
//  Created by Ruan Viljoen on 2024/08/07.
//  Copyright © 2024 Shifty Jelly. All rights reserved.
//

import ActivityKit
import Foundation

struct SleepTimerAttributes: ActivityAttributes {
    var timerName = "Sleep Timer"

    public struct ContentState: Codable, Hashable {
        var startTime: Date
        var endTime: Date
        var playing: Bool
    }
}

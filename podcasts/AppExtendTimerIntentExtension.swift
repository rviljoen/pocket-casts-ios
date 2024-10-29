//
//  AppExtendTimerIntentExtension.swift
//  podcasts
//
//  Created by Ruan Viljoen on 2024/08/10.
//  Copyright © 2024 Shifty Jelly. All rights reserved.
//

import PocketCastsUtils
import PocketCastsDataModel

@available(iOS 17, *)

extension ExtendTimerIntent {
    func incrementTimer() {
        PlaybackManager.shared.sleepTimeRemaining += 5.minutes
        PlaybackManager.shared.startOrUpdateLiveActivity()
    }
}

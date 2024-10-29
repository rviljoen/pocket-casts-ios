//
//  SleepTimerWidget.swift
//  podcasts
//
//  Created by Ruan Viljoen on 2024/08/07.
//  Copyright © 2024 Shifty Jelly. All rights reserved.
//
import WidgetKit
import SwiftUI
import ActivityKit

@available(iOS 16.1, *)
struct SleepTimerWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepTimerAttributes.self) { context in
            // Lock screen/banner UI
            HStack {
                Image("AppIcon-Sleepy")
                    .resizable()
                    .frame(width: 54, height: 54)

                if context.state.playing {
                    Button(intent: ExtendTimerIntent()) {
                        Text("+5m")
                            .font(.headline)
                            .fontWeight(.bold)
                            .frame(width: 54, height: 54)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()

                    Text(context.state.endTime, style: .timer)
                        .font(.largeTitle)
                        .monospacedDigit()
                        //We need to add multi-line to work around the problem where Text fields styled with .timer
                        //seems to always be left-aligned.
                        //See: https://stackoverflow.com/questions/68692440/right-aligning-textdate-style-timer-text-in-an-ios-widgetkit-widget
                        //And: https://forums.developer.apple.com/forums/thread/662642
                        .multilineTextAlignment(.trailing)
                } else {
                    Spacer()
                    let timerLeft = context.state.endTime.timeIntervalSinceNow
                    Text(DateComponentsFormatter().string(from: timerLeft)!)
                        .font(.largeTitle)
                        .monospacedDigit()
                }
            }
            .widgetURL(URL(string: "pktc://shortcuts/sleep"))
            .padding()
            .activityBackgroundTint(Color.widgetBlack.opacity(0.25))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        Image("AppIcon-Sleepy")
                            .resizable()
                            .frame(width: 48, height: 48)
                        if context.state.playing {
                            Button(intent: ExtendTimerIntent()) {
                                Text("+5m")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .frame(width: 48, height: 48)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .clipShape(Circle())
                                    .scaledToFit()
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.playing {
                        Text(context.state.endTime, style: .timer)
                            .font(.largeTitle)
                            .monospacedDigit()
                    } else {
                        let timerLeft = context.state.endTime.timeIntervalSinceNow
                        Text(DateComponentsFormatter().string(from: timerLeft)!)
                            .font(.largeTitle)
                            .monospacedDigit()
                    }
                }
            } compactLeading: {
                timerProgressView(state: context.state)
            } compactTrailing: {
            ///
            } minimal: {
                timerProgressView(state: context.state)
            }
            .widgetURL(URL(string: "pktc://shortcuts/sleep"))
        }
    }
}

struct timerProgressView: View {

    let state: SleepTimerAttributes.ContentState

    var body: some View {
        if state.playing {
            ProgressView(
                timerInterval: state.startTime...state.endTime,
                countsDown: true,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .progressViewStyle(.circular)
            .tint(Color.red)
        } else {
            Image("AppIcon-Sleepy")
                .resizable()
                .frame(width: 24, height: 24)
        }
    }
}

func extendTimer() {
    let intent = ExtendTimerIntent()
    Task {
        try await intent.perform()
    }
}

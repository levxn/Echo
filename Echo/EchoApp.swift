import os
import SwiftUI

@main
struct EchoApp: App {
    @State private var model: PipelineModel
    @State private var link: PhoneLink
    @State private var pipeline: Pipeline
    @State private var voices: VoiceBookModel
    @State private var privacy = RecordingPrivacy()

    init() {
        // Dev hook: `-reset-demo <token>` wipes the day (not the API key) before anything opens the database.
        DemoReset.runIfNeeded(token: DemoReset.requestedToken())
        let model = PipelineModel()
        _model = State(initialValue: model)
        let pipeline = Pipeline(model: model)
        let voices = VoiceBookModel(store: model.store)
        pipeline.voices = voices
        _voices = State(initialValue: voices)
        let privacy = RecordingPrivacy()
        pipeline.privacy = privacy
        _privacy = State(initialValue: privacy)
        let link = PhoneLink(model: model)
        link.onChunkReceived = { pipeline.enqueue($0) }
        _pipeline = State(initialValue: pipeline)
        _link = State(initialValue: link)
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, link: link, voices: voices, privacy: privacy).task {
                await model.load()
                await voices.load()
                let authorized = await OnDeviceASR.authorize()
                Log.app.info("speech authorized: \(authorized)")
                // Resume anything a previous launch left unprocessed.
                model.chunks.filter { $0.status == .received || $0.status == .vad }.forEach { pipeline.enqueue($0) }
                await pipeline.backfillIndex()
            }
        }
    }
}

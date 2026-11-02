import os
import SwiftUI

@main
struct EchoApp: App {
    @State private var model: PipelineModel
    @State private var link: PhoneLink
    @State private var pipeline: Pipeline
    @State private var voices: VoiceBookModel
    @State private var privacy = RecordingPrivacy()
    @State private var watcher: PromiseWatcher
    @State private var places: PlacesModel

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
        let places = PlacesModel(store: model.store)
        pipeline.places = places
        _places = State(initialValue: places)
        let watcher = PromiseWatcher(model: model)
        pipeline.watcher = watcher
        _watcher = State(initialValue: watcher)
        let link = PhoneLink(model: model)
        link.onChunkReceived = { pipeline.enqueue($0) }
        pipeline.onWakeQuestion = { [link] question in link.wakeQuestion?(question) }
        _pipeline = State(initialValue: pipeline)
        _link = State(initialValue: link)
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, link: link, voices: voices, privacy: privacy, watcher: watcher, places: places).task {
                await model.load()
                await voices.load()
                await places.load()
                // A first launch asks after the welcome screen has said why (see FirstImpression).
                if !Welcome.isPending() {
                    let authorized = await OnDeviceASR.authorize()
                    Log.app.info("speech authorized: \(authorized)")
                }
                // Resume anything a previous launch left unprocessed.
                model.chunks.filter { $0.status == .received || $0.status == .vad }.forEach { pipeline.enqueue($0) }
                await pipeline.backfillIndex()
            }
        }
    }
}

import SwiftUI

@main
struct EchoApp: App {
    @State private var model: PipelineModel
    @State private var link: PhoneLink

    init() {
        let model = PipelineModel()
        _model = State(initialValue: model)
        _link = State(initialValue: PhoneLink(model: model))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model).task { await model.load() }
        }
    }
}

import Foundation
import HealthKit
import os

/// Keeps the watch app running with the wrist down. watchOS suspends an app that isn't in front unless it is running a workout
/// session, so listening all day borrows one. The session is only a way to stay awake: nothing is measured and no workout is
/// ever saved to Health.
@MainActor
protocol BackgroundKeepAlive: AnyObject {
    /// True if the app will keep running in the background.
    func begin() async -> Bool
    func end() async
}

@MainActor
final class WorkoutBackgroundCapture: NSObject, BackgroundKeepAlive, HKWorkoutSessionDelegate {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func begin() async -> Bool {
        guard session == nil, HKHealthStore.isHealthDataAvailable() else { return session != nil }
        do { try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: []) } catch {
            Log.app.error("workout permission: \(error.localizedDescription)")
            return false
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            self.session = session
            self.builder = builder
            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            return true
        } catch {
            Log.app.error("workout session: \(error.localizedDescription)")
            session = nil; builder = nil
            return false
        }
    }

    func end() async {
        session?.end()
        try? await builder?.endCollection(at: Date())
        builder?.discardWorkout()
        session = nil
        builder = nil
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Log.app.error("workout session failed: \(error.localizedDescription)")
    }
}

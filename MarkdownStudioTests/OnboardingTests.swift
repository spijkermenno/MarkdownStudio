import Foundation
import Testing
@testable import Markdown_Studio

@MainActor
@Suite(.serialized)
struct OnboardingTests {
    /// Runs `body` against a throwaway defaults suite so the real flag is never touched.
    private func withTemporaryDefaults(_ body: () -> Void) {
        let name = "OnboardingTests-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        let original = Onboarding.defaults
        Onboarding.defaults = suite
        defer {
            Onboarding.defaults = original
            suite.removePersistentDomain(forName: name)
        }
        body()
    }

    @Test func finishingTheLastTourStepCompletesOnboarding() {
        withTemporaryDefaults {
            #expect(!Onboarding.isCompleted)
            let session = DocumentSession(text: Onboarding.tourText, fileURL: nil, viewMode: .editor, splitOrientation: .horizontal)
            session.startTour()
            #expect(session.tourStep == 0)
            #expect(session.viewMode == .split)
            for _ in 1..<TourStep.all.count { session.moveTour(by: 1) }
            #expect(session.tourStep == TourStep.all.count - 1)
            #expect(!Onboarding.isCompleted)          // not until Finish is pressed
            session.endTour(completed: true)
            #expect(session.tourStep == nil)
            #expect(Onboarding.isCompleted)
        }
    }

    @Test func endingTheTourEarlyDoesNotComplete() {
        withTemporaryDefaults {
            let session = DocumentSession(text: "", fileURL: nil, viewMode: .split, splitOrientation: .horizontal)
            session.startTour()
            session.moveTour(by: 3)
            #expect(session.tourTarget == .preview)
            session.moveTour(by: -10)
            #expect(session.tourStep == 0)
            session.endTour(completed: false)
            #expect(!Onboarding.isCompleted)
        }
    }

    @Test func tourPointsAtEveryMainArea() {
        let targets = Set(TourStep.all.map { "\($0.target)" })
        #expect(targets.isSuperset(of: ["viewModes", "editor", "preview", "sidebar", "statusBar", "shareButtons"]))
    }
}

import XCTest
@testable import TwoTrill

final class CutPlannerTests: XCTestCase {
    private let grid = BeatGrid(bpm: 120, firstBeat: 0.2, downbeatIndex: 0)

    private func takes(_ count: Int, length: Double = 40) -> [TakeCoverage] {
        (0..<count).map { _ in TakeCoverage(id: UUID(), start: -0.2, end: length) }
    }

    private func planner(_ style: CutStyle = .balanced, clipStart: Double = 10.2, length: Double = 30) -> CutPlanner {
        CutPlanner(grid: grid, clipStart: clipStart, clipLength: length, envelope: nil, style: style)
    }

    func testCoversWholeClipWithoutGaps() {
        for style in CutStyle.allCases {
            for seed in UInt64(1)...20 {
                let plan = planner(style).plan(takes: takes(4), seed: seed)
                XCTAssertEqual(plan.segments.first?.start, 0)
                XCTAssertEqual(plan.segments.last?.end ?? 0, 30, accuracy: 1e-9)
                for (a, b) in zip(plan.segments, plan.segments.dropFirst()) {
                    XCTAssertEqual(a.end, b.start, accuracy: 1e-9)
                    XCTAssertGreaterThan(a.duration, 0.15)
                }
            }
        }
    }

    func testSameSeedSameEdit() {
        let t = takes(3)
        XCTAssertEqual(planner().plan(takes: t, seed: 42), planner().plan(takes: t, seed: 42))
        XCTAssertNotEqual(planner().plan(takes: t, seed: 42), planner().plan(takes: t, seed: 43))
    }

    func testNeverRepeatsTheSameTakeBackToBack() {
        for seed in UInt64(1)...30 {
            let plan = planner(.hype).plan(takes: takes(3), seed: seed)
            for (a, b) in zip(plan.segments, plan.segments.dropFirst()) where a.zoom == b.zoom {
                XCTAssertNotEqual(a.takeID, b.takeID)
            }
        }
    }

    func testCutsLandOnTheBeatGrid() {
        let clipStart = 10.2
        let plan = planner(clipStart: clipStart).plan(takes: takes(4), seed: 7)
        let half = grid.period / 2
        for segment in plan.segments.dropLast() {
            let gridPosition = (segment.end + clipStart - grid.firstBeat) / half
            XCTAssertEqual(gridPosition, gridPosition.rounded(), accuracy: 1e-6)
        }
    }

    func testUsesEveryTake() {
        let t = takes(5)
        let plan = planner().plan(takes: t, seed: 3)
        XCTAssertEqual(Set(plan.segments.map(\.takeID)), Set(t.map(\.id)))
    }

    func testOnlyUsesTakesThatCoverTheShot() {
        let full = TakeCoverage(id: UUID(), start: -0.2, end: 40)
        let other = TakeCoverage(id: UUID(), start: -0.2, end: 40)
        let firstHalfOnly = TakeCoverage(id: UUID(), start: -0.2, end: 15)
        for seed in UInt64(1)...20 {
            let plan = planner().plan(takes: [full, other, firstHalfOnly], seed: seed)
            for segment in plan.segments where segment.takeID == firstHalfOnly.id {
                XCTAssertLessThanOrEqual(segment.end, 15.05)
            }
        }
    }

    func testSingleTakeIsOneShotUnlessPunchedIn() {
        let plan = planner(.chill).plan(takes: takes(1), seed: 1)
        XCTAssertEqual(plan.segments.count, 1)
    }

    func testHypeCutsFasterThanChill() {
        let t = takes(4)
        let average = { (style: CutStyle) -> Double in
            let counts = (UInt64(1)...20).map { self.planner(style).plan(takes: t, seed: $0).segments.count }
            return Double(counts.reduce(0, +)) / Double(counts.count)
        }
        XCTAssertGreaterThan(average(.hype), average(.balanced))
        XCTAssertGreaterThan(average(.balanced), average(.chill))
    }

    func testHalfSpeedTakeCoversTwiceItsLength() {
        // Filmed for 16 s with the song at 2x: covers 32 s of the clip.
        let take = Take(fileName: "t.mov", syncOffset: 0.1, duration: 16, songRate: 2)
        XCTAssertEqual(take.coverage.start, -0.2, accuracy: 1e-9)
        XCTAssertEqual(take.coverage.end, 31.8, accuracy: 1e-9)
        XCTAssertEqual(take.videoTime(atClipTime: 10), 5.1, accuracy: 1e-9)
    }
}

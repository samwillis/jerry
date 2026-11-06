import XCTest
@testable import ExpeditionCore

final class TeamMissionTests: XCTestCase {
    func testLeaderIsPermanentAndSingleJobDoesNotInviteAnyone() throws {
        var team = TeamMission()
        XCTAssertEqual(team.members, [.leader])
        try team.start(.init(jobs: [.init(marker: "blue", instruction: "Inspect")]))
        XCTAssertEqual(team.members, [.leader])
        try team.complete("blue", by: .leader, generation: team.generation)
        XCTAssertTrue(team.isComplete); XCTAssertEqual(team.members, [.leader])
        team.stop(); XCTAssertEqual(team.members, [.leader])
    }
    func testThreeIndependentJobsInviteTwoHelpersAndRetireThem() throws {
        var team = TeamMission()
        try team.start(.init(jobs: ["blue", "amber", "purple"].map { .init(marker: $0, instruction: "Inspect") }))
        XCTAssertEqual(team.members.count, 3)
        let generation = team.generation
        for member in ExpeditionMember.allCases { try team.complete(team.assignments[member]!, by: member, generation: generation) }
        XCTAssertTrue(team.isComplete); XCTAssertEqual(team.members, [.leader])
    }
    func testDependentJobsDoNotRecruitIdleFriends() throws {
        var team = TeamMission()
        try team.start(.init(jobs: [.init(marker: "blue", instruction: "First"), .init(marker: "amber", instruction: "Second", dependsOn: ["blue"]), .init(marker: "purple", instruction: "Third", dependsOn: ["amber"])]))
        for marker in ["blue", "amber", "purple"] {
            XCTAssertEqual(team.members, [.leader]); XCTAssertEqual(team.assignments[.leader], marker)
            try team.complete(marker, by: .leader, generation: team.generation)
        }
        XCTAssertTrue(team.isComplete)
    }
    func testInvalidPlansAndLateCompletionsAreRejected() throws {
        var team = TeamMission()
        XCTAssertThrowsError(try team.start(.init(jobs: [.init(marker: "blue", instruction: "x", dependsOn: ["amber"]), .init(marker: "amber", instruction: "x", dependsOn: ["blue"])])))
        XCTAssertThrowsError(try team.start(.init(jobs: [.init(marker: "blue", instruction: "x"), .init(marker: "blue", instruction: "x")])))
        try team.start(.init(jobs: [.init(marker: "blue", instruction: "Inspect")]))
        let old = team.generation
        team.stop()
        XCTAssertThrowsError(try team.complete("blue", by: .leader, generation: old))
        XCTAssertEqual(team.members, [.leader])
    }
}

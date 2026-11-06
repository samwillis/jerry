import Foundation

public enum ExpeditionMember: String, CaseIterable, Codable, Sendable {
    case leader, scout, rigger
    public var title: String { switch self { case .leader: "Explorer"; case .scout: "Scout"; case .rigger: "Rigger" } }
}

/// Prototype jobs inspect the app's own coloured survey flags. No desktop input.
public struct SurveyJob: Codable, Equatable, Sendable {
    public let marker: String
    public let instruction: String
    public let dependsOn: [String]
    public init(marker: String, instruction: String, dependsOn: [String] = []) {
        self.marker = marker; self.instruction = instruction; self.dependsOn = dependsOn
    }
}
public struct SurveyPlan: Codable, Equatable, Sendable {
    public let jobs: [SurveyJob]
    public init(jobs: [SurveyJob]) { self.jobs = jobs }
    public func validate() throws {
        let ids = jobs.map(\.marker)
        guard (1...3).contains(jobs.count), Set(ids).count == ids.count,
              jobs.allSatisfy({ ["blue", "amber", "purple"].contains($0.marker) && !$0.instruction.isEmpty && $0.instruction.count <= 240 && Set($0.dependsOn).count == $0.dependsOn.count && $0.dependsOn.allSatisfy(ids.contains) && !$0.dependsOn.contains($0.marker) }) else { throw MissionError.invalidPlan }
        var visited = Set<String>()
        for _ in jobs.indices {
            for job in jobs where job.dependsOn.allSatisfy(visited.contains) { visited.insert(job.marker) }
        }
        guard visited.count == jobs.count else { throw MissionError.invalidPlan }
    }
}
public enum MissionError: Error, LocalizedError {
    case invalidPlan, staleRun
    public var errorDescription: String? {
        switch self { case .invalidPlan: "The plan must contain up to three unique survey flags with valid, acyclic dependencies."; case .staleRun: "This mission has been stopped or replaced." }
    }
}

/// Only ready independent jobs recruit helpers. One job (even a chain of three)
/// uses the permanent explorer. The model never gets a free-form spawn tool.
public struct TeamMission: Sendable {
    public private(set) var plan: SurveyPlan?
    public private(set) var assignments: [ExpeditionMember: String] = [:]
    public private(set) var completed: Set<String> = []
    public private(set) var generation = UUID()
    public init() {}
    public var members: Set<ExpeditionMember> { Set(assignments.keys).union([.leader]) }
    public var isComplete: Bool { plan.map { completed.count == $0.jobs.count } ?? false }
    public mutating func start(_ plan: SurveyPlan) throws {
        try plan.validate()
        generation = UUID(); self.plan = plan; completed = []; assignments = [:]
        schedule()
    }
    public mutating func complete(_ marker: String, by member: ExpeditionMember, generation: UUID) throws {
        guard generation == self.generation, assignments[member] == marker else { throw MissionError.staleRun }
        completed.insert(marker); assignments[member] = nil; schedule()
    }
    public mutating func stop() { generation = UUID(); plan = nil; completed = []; assignments = [:] }
    private mutating func schedule() {
        guard let plan else { return }
        var occupied = Set(assignments.values)
        for member in ExpeditionMember.allCases where assignments[member] == nil {
            if let job = plan.jobs.first(where: { !completed.contains($0.marker) && !occupied.contains($0.marker) && $0.dependsOn.allSatisfy(completed.contains) }) {
                assignments[member] = job.marker; occupied.insert(job.marker)
            }
        }
    }
}

import Foundation

@MainActor
class FlowPersistenceService {
    static let shared = FlowPersistenceService()

    private let flowsKey = "recorded_flows_v1"
    private let logger = DebugLogger.shared

    func saveFlows(_ flows: [RecordedFlow]) {
        do {
            let data = try JSONEncoder().encode(flows)
            UserDefaults.standard.set(data, forKey: flowsKey)
            logger.log("FlowPersistence: saved \(flows.count) flows", category: .persistence, level: .info)
        } catch {
            logger.log("FlowPersistence: save failed — \(error.localizedDescription)", category: .persistence, level: .error)
        }
    }

    func loadFlows() -> [RecordedFlow] {
        guard let data = UserDefaults.standard.data(forKey: flowsKey) else { return [] }
        do {
            let flows = try JSONDecoder().decode([RecordedFlow].self, from: data)
            logger.log("FlowPersistence: loaded \(flows.count) flows", category: .persistence, level: .info)
            return flows
        } catch {
            logger.log("FlowPersistence: load failed — \(error.localizedDescription)", category: .persistence, level: .error)
            return []
        }
    }

    func exportFlow(_ flow: RecordedFlow) -> Data? {
        try? JSONEncoder().encode(flow)
    }

    func importFlow(from data: Data) -> RecordedFlow? {
        try? JSONDecoder().decode(RecordedFlow.self, from: data)
    }
}

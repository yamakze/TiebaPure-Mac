import Foundation

@MainActor
enum HistoryStorage {
    static func repair<Entry: Equatable>(
        _ stored: [Entry],
        canRepair: Bool,
        replaceAll: ([Entry], () throws -> Void) throws -> Void,
        sanitize: ([Entry]) -> [Entry],
        faultInjector: PersistenceFaultInjector
    ) -> PersistenceLoadResult<[Entry]> {
        let items = sanitize(stored)
        if canRepair, stored != items {
            do {
                try replaceAll(items) { try faultInjector.check(.repair) }
            } catch {
                return PersistenceLoadResult(value: items, repairError: error)
            }
        }
        return PersistenceLoadResult(value: items, repairError: nil)
    }
}

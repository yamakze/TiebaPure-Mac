import Foundation

@MainActor
enum HistoryStorage {
    static func initialSnapshot<Entry: Equatable, LegacyValue>(
        capability: PersistenceCapability,
        collection: String,
        defaults: UserDefaults,
        legacyKey: String,
        legacyValue: LegacyValue?,
        decodeLegacy: (LegacyValue) -> [Entry]?,
        load: () throws -> [Entry],
        replaceAll: ([Entry], () throws -> Void) throws -> Void,
        sanitize: ([Entry]) -> [Entry],
        faultInjector: PersistenceFaultInjector
    ) -> (items: [Entry], availability: PersistenceAvailability) {
        func readLegacy() -> [Entry]? {
            guard let legacyValue else { return nil }
            guard let items = decodeLegacy(legacyValue) else {
                PersistenceDiagnostics.report(
                    LegacyStorageMigration.DecodeError.invalidTopLevelArray,
                    operation: "decode legacy \(collection)"
                )
                return nil
            }
            return items
        }

        guard capability.canAccessBackend else {
            return (readLegacy().map(sanitize) ?? [], .unavailable)
        }
        let stored: [Entry]
        do {
            stored = try load()
        } catch {
            PersistenceDiagnostics.report(error, operation: "load \(collection)")
            return (readLegacy().map(sanitize) ?? [], .unavailable)
        }

        guard legacyValue != nil else {
            let result = repair(
                stored,
                canRepair: capability.acceptsUserMutations,
                replaceAll: replaceAll,
                sanitize: sanitize,
                faultInjector: faultInjector
            )
            if let error = result.repairError {
                PersistenceDiagnostics.report(error, operation: "repair \(collection)")
                return (result.value, .unavailable)
            }
            return (result.value, capability.availability)
        }

        guard let source = stored.isEmpty ? readLegacy() : stored else {
            return ([], .unavailable)
        }
        let items = sanitize(source)
        do {
            try LegacyStorageMigration.persistThenRemoveLegacyValue(
                defaults: defaults,
                key: legacyKey,
                destinationIsDurable: capability.isDurable
            ) {
                try replaceAll(items) { try faultInjector.check(.legacyMigration) }
            }
            return (items, capability.availability)
        } catch {
            PersistenceDiagnostics.report(error, operation: "migrate \(collection)")
            return (items, .unavailable)
        }
    }

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

// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Combine
import Foundation
import MastodonCore
import MastodonSDK

public protocol CacheableFeed {
    var hasResults: Bool { get }
}

public enum MastodonFeedLoaderError: Error {
    case requestNotImplemented
}

@MainActor
protocol MastodonFeedCacheManager<CachedType> {
    associatedtype CachedType

    func currentResults() -> CachedType?
    var currentLastReadMarker: LastReadMarkers.MarkerPosition? { get }
    var mostRecentlyFetchedResults: CachedType? { get }
    func updateByInserting(newlyFetched: CachedType, at insertionPoint: MastodonFeedLoaderRequest.InsertLocation)
    func didFetchMarkers(_ updatedMarkers: Mastodon.Entity.Marker)
    func updateToNewerMarker(_ newMarker: LastReadMarkers.MarkerPosition, enforceForwardProgress: Bool)
    func commitToCache() async
}

public struct MastodonFeedLoaderResult<ResultType> {
    let allRecords: [ResultType]
    let canLoadOlder: Bool
}

public enum MastodonFeedLoaderRequest: Equatable {
    case older
    case newer
    case reload
    case newerThan(String)
    case olderThan(String)
    
    var resultsInsertionPoint: InsertLocation {
        switch self {
        case .older:
            return .end
        case .newer:
            return .start
        case .reload:
            return .replace
        case .newerThan(let id):
            return .asNewerThan(id)
        case .olderThan(let id):
            return .asOlderThan(id)
        }
    }
    enum InsertLocation {
        case start
        case end
        case replace
        case asNewerThan(String)
        case asOlderThan(String)
    }
}

@MainActor
public class MastodonFeedLoader<PublishedType: Identifiable, CachedType: CacheableFeed> {
    private var activeFilterBoxSubscription: AnyCancellable?
    private var loadRequestQueue = [MastodonFeedLoaderRequest]()
    let cacheManager: (any MastodonFeedCacheManager<CachedType>)
    
    @Published private(set) var records = MastodonFeedLoaderResult<PublishedType>(
        allRecords: [], canLoadOlder: true)
    @Published private(set) var currentError: Error? = nil
    
    init(_ cacheManager: (any MastodonFeedCacheManager<CachedType>)) {
        self.cacheManager = cacheManager
        
        activeFilterBoxSubscription = StatusFilterService.shared
            .$activeFilterBox
            .sink { _ in
                // TODO: reload completely
            }
    }
    
    private var isFetching: Bool = false {
        didSet {
            if !isFetching, let waitingRequest = nextRequestThatCanBeLoadedNow() {
                Task {
                    do {
                        try await load(waitingRequest)
                        currentError = nil
                    } catch {
                        currentError = error
                    }
                }
            }
        }
    }
    
    private func nextRequestThatCanBeLoadedNow() -> MastodonFeedLoaderRequest? {
        guard !isFetching else { return nil }
        guard !loadRequestQueue.isEmpty else { return nil }
        let nextRequest = loadRequestQueue.removeFirst()
        isFetching = true
        return nextRequest
    }
    
    func setRecords(_ records: MastodonFeedLoaderResult<PublishedType>) {
        self.records = records
    }
    
    // MARK: Subclasses Must Override
    func fetchResults(for request: MastodonFeedLoaderRequest) async throws -> CachedType {
        fatalError("Subclasses must override fetchResults(for:)")
    }
    func filteredResults(fromCachedType: CachedType) -> [PublishedType] {
        fatalError("Subclasses must override publishedType(fromCachedType:)")
    }
}

extension MastodonFeedLoader {
    public func doFirstLoad() {
        Task {
            do {
                try loadCached()
            } catch {
            }
            do {
                if let authBox = AuthenticationServiceProvider.shared.currentActiveUser.value {
                    let markers = try await APIService.shared.lastReadMarkers(authenticationBox: authBox)
                    cacheManager.didFetchMarkers(markers)
                }
            } catch {
            }
            requestLoad(.newer)
        }
    }
    
    public func requestLoad(_ request: MastodonFeedLoaderRequest) {
        if !loadRequestQueue.contains(request) {
            loadRequestQueue.append(request)
        }
        if let nextDoableRequest = nextRequestThatCanBeLoadedNow() {
            Task {
                do {
                    try await load(nextDoableRequest)
                    currentError = nil
                } catch {
                    currentError = error
                }
            }
        }
    }
    
    public var permissionToLoadImmediately: Bool {
        // This is only intended for use with pull to refresh, in order to properly update the progress spinner.
        if isFetching {
            return false
        } else {
            isFetching = true
            return true
        }
    }
    public func loadImmediately(_ request: MastodonFeedLoaderRequest) async {
        // This is only intended for use with pull to refresh, in order to properly update the progress spinner.
        guard isFetching else { assertionFailure("request permissionToLoadImmediately before calling loadImmediately"); return }
        do {
            try await load(request)
            currentError = nil
        } catch {
            currentError = error
        }
    }
    
    func load(_ request: MastodonFeedLoaderRequest) async throws
    {
        defer { isFetching = false }
        let unfiltered = try await fetchResults(for: request)
        updateAfterInserting(newlyFetchedResults: unfiltered, at: request.resultsInsertionPoint)
    }
    
    func updateAfterInserting(newlyFetchedResults: CachedType, at insertionPoint: MastodonFeedLoaderRequest.InsertLocation) {
        updateCacheByInserting(newlyFetchedResults: newlyFetchedResults, at: insertionPoint)
        
        let currentResults = cacheManager.currentResults() ?? newlyFetchedResults
        let filtered = filteredResults(fromCachedType: currentResults)
        
        let canLoadOlder: Bool? = {
            switch insertionPoint {
            case .start, .asOlderThan, .asNewerThan:
                return records.canLoadOlder
            case .end:
                return nil
            case .replace:
                return true
            }
        }()
        replaceRecords(filtered, canLoadOlder: canLoadOlder)
        currentError = nil
    }
    
    private func noMoreResultsToFetch() {
        if records.canLoadOlder {
            setRecords(MastodonFeedLoaderResult(allRecords: records.allRecords, canLoadOlder: false))
        }
    }
    
    private func replaceRecords(_ filtered: [PublishedType], canLoadOlder: Bool? = nil) {
        let actuallyCanLoadOlder = {
            if let newLast = filtered.last?.id, let oldLast = records.allRecords.last?.id {
                return canLoadOlder ?? (newLast != oldLast)
            } else {
                return canLoadOlder ?? true
            }
        }()
        
        setRecords(MastodonFeedLoaderResult(allRecords: checkForDuplicates(filtered), canLoadOlder: actuallyCanLoadOlder))
    }
    
    private func checkForDuplicates(_ items: [PublishedType]) -> [PublishedType] {
        var added = Set<PublishedType.ID>()
        var deduped = [PublishedType]()
        for item in items {
            let id = item.id
            if added.contains(id) {
                continue
            } else {
                deduped.append(item)
                added.insert(id)
            }
        }
        return deduped
    }
}

extension MastodonFeedLoader {
    public func commitToCache() async {
        await cacheManager.commitToCache()
    }
    
    public func updateCachedResults(_ updater: (CachedType)->(CachedType)) {
        guard let cached = cacheManager.currentResults() else { return }
        let updatedCache = updater(cached)
        updateAfterInserting(newlyFetchedResults: updatedCache, at: .replace)
    }
    
    private func loadCached() throws {
        guard !isFetching else { return }
        isFetching = true
        defer {
            isFetching = false
        }
        if let currentResults = cacheManager.currentResults() {
            replaceRecords(filteredResults(fromCachedType: currentResults), canLoadOlder: true)
        }
    }

    private func updateCacheByInserting(newlyFetchedResults: CachedType,
                                        at insertionPoint: MastodonFeedLoaderRequest.InsertLocation) {
        switch insertionPoint {
        case .start, .asNewerThan, .asOlderThan:
            guard newlyFetchedResults.hasResults else { return }
        case .replace:
            break
        case .end:
            guard newlyFetchedResults.hasResults else {
                noMoreResultsToFetch()
                return
            }
        }
        cacheManager.updateByInserting(newlyFetched: newlyFetchedResults, at: insertionPoint)
    }
}

extension MastodonFeedLoader {
    var lastReadMarker: LastReadMarkers.MarkerPosition? {
        return cacheManager.currentLastReadMarker
    }
    
    public func markAsRead(_ identifier: String) {
        cacheManager.updateToNewerMarker(.local(lastReadID: identifier), enforceForwardProgress: true)
    }
    
    public func isUnread(_ identifier: String) -> Bool {
        if let lastRead = cacheManager.currentLastReadMarker?.lastReadID {
            return LastReadMarkers.id(lastRead, isOlderThan: identifier)
        } else {
            return false
        }
    }
    
    public func lastRead() -> String? {
        return cacheManager.currentLastReadMarker?.lastReadID
    }
}

//
//  NotificationTimelineViewModel+LoadOldestState.swift
//  Mastodon
//
//  Created by MainasuK on 2022-1-21.
//

import CoreDataStack
import Foundation
import GameplayKit
import MastodonSDK
import MastodonCore

extension NotificationTimelineViewModel {
    class LoadOldestState: GKState {
        
        let id = UUID()

        weak var viewModel: NotificationTimelineViewModel?
        
        init(viewModel: NotificationTimelineViewModel) {
            self.viewModel = viewModel
        }
        
        @MainActor
        func enter(state: LoadOldestState.Type) {
            stateMachine?.enter(state)
        }
    }
}

extension NotificationTimelineViewModel.LoadOldestState {
    @MainActor
    class Initial: NotificationTimelineViewModel.LoadOldestState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            guard let viewModel = viewModel else { return false }
            guard !viewModel.feedLoader.records.allRecords.isEmpty else { return false }
            return stateClass == Loading.self
        }
    }
    
    class Loading: NotificationTimelineViewModel.LoadOldestState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == Fail.self || stateClass == Idle.self || stateClass == NoMore.self
        }
        
        @MainActor
        override func didEnter(from previousState: GKState?) {
            super.didEnter(from: previousState)
            
            guard let viewModel = viewModel, let stateMachine = stateMachine else { return }
            
            guard let lastFeedRecord = viewModel.feedLoader.records.allRecords.last else {
                stateMachine.enter(Fail.self)
                return
            }
            
            let scope: APIService.MastodonNotificationScope?
            let accountID: String?

            switch viewModel.scope {
            case .everything:
                scope = .everything
                accountID = nil
            case .mentions:
                scope = .mentions
                accountID = nil
            case .fromAccount(let account):
                scope = nil
                accountID = account.id
            }

            Task {
                let _maxID: Mastodon.Entity.Notification.ID? = lastFeedRecord.id
                
                guard let maxID = _maxID else {
                    self.enter(state: Fail.self)
                    return
                }
                
                do {
                    let response = try await APIService.shared.notifications(
                        olderThan: maxID,
                        fromAccount: accountID,
                        scope: scope,
                        authenticationBox: viewModel.authenticationBox
                    )
                    
                    let notifications = response.value
                    // enter no more state when no new statuses
                    if notifications.isEmpty || (notifications.count == 1 && notifications[0].id == maxID) {
                        self.enter(state: NoMore.self)
                    } else {
                        self.enter(state: Idle.self)
                    }
                    
                } catch {
                    self.enter(state: Fail.self)
                }
            }   // end Task
        }
    }
    
    class Fail: NotificationTimelineViewModel.LoadOldestState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == Loading.self || stateClass == Idle.self
        }
    }
    
    class Idle: NotificationTimelineViewModel.LoadOldestState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == Loading.self
        }
    }

    class NoMore: NotificationTimelineViewModel.LoadOldestState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            // reset state if needs
            stateClass == Idle.self
        }
        
        override func didEnter(from previousState: GKState?) {
            guard let viewModel = viewModel else { return }
            DispatchQueue.main.async {
                guard let diffableDataSource = viewModel.diffableDataSource else {
                    assertionFailure()
                    return
                }
                var snapshot = diffableDataSource.snapshot()
                snapshot.deleteItems([.bottomLoader])
                diffableDataSource.apply(snapshot)
            }
        }
    }
}

// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import SwiftUI

enum AsyncBool {
    case unknown
    case fetching
    case isTrue
    case settingToTrue
    case isFalse
    case settingToFalse
    
    static func fromBool(_ value: Bool?) -> AsyncBool {
        guard let value else { return .unknown }
        if value {
            return .isTrue
        } else {
            return .isFalse
        }
    }
}

struct StatefulCountedActionViewModel {
    struct UpdatableDisplayDetails {
        let count: Int?
        let isSelected: AsyncBool
    }
    
    let type: PostAction
    var displayDetails: UpdatableDisplayDetails
    var doAction: (()->())?
    var iconName: String {
        return type.systemIconName(filled: displayDetails.isSelected == .isTrue)
    }
    var countLabel: String? {
        guard let count = displayDetails.count, count > 0 else { return nil }
        return count.formatted(.number.notation(.compactName))
    }
    var color: Color {
        if displayDetails.isSelected == .isTrue {
            switch type {
            case .reply: return .secondary
            case .boost: return .green
            case .favourite: return .yellow
            case .bookmark: return .red
            }
        } else {
            return .secondary
        }
    }
}

struct StatefulCountedActionButton: View {
    let viewModel: StatefulCountedActionViewModel
    
    var body: some View {
        Button(action: { viewModel.doAction?() }) {
            HStack(spacing: 4) {
                switch viewModel.displayDetails.isSelected {
                case .isFalse, .isTrue:
                    Image(systemName: viewModel.iconName)
                        .font(.subheadline)
                case .fetching, .settingToFalse, .settingToTrue:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .font(.subheadline)
                case .unknown:
                    Image(systemName: "questionmark")
                        .font(.subheadline)
                }
                ZStack(alignment: .leading) {
                    Text("0000")         // to keep the required space
                        .fontWeight(.semibold)
                        .hidden()
                    Text(viewModel.countLabel ?? "")
                        .contentTransition(.numericText(value: Double(viewModel.displayDetails.count ?? 0)))
                }
                .font(.footnote)
            }
            .fontWeight(viewModel.displayDetails.isSelected == .isTrue ? .semibold : .regular)
            .foregroundStyle(viewModel.color)
        }
        .buttonStyle(.borderless) // Without this, all the buttons in the row activate when one is tapped.  What a remarkably unexpected result with no documentation.
    }
}


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

class StatefulCountedActionViewModel: ObservableObject {
    struct UpdatableDisplayDetails {
        var count: Int?
        var isSelected: AsyncBool
    }
    
    @Published var displayDetails: UpdatableDisplayDetails
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
    
    private let type: PostAction
    
    init(_ type: PostAction) {
        self.type = type
        displayDetails = UpdatableDisplayDetails(count: nil, isSelected: .unknown)
    }
    
    func update(count: Int? = nil, isSelected: AsyncBool? = .unknown) {
        displayDetails = UpdatableDisplayDetails(count: count ?? displayDetails.count, isSelected: isSelected ?? displayDetails.isSelected)
    }
}

struct StatefulCountedActionButton: View {
    @ObservedObject var viewModel: StatefulCountedActionViewModel
    
    init(viewModel: StatefulCountedActionViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        Button(action: { viewModel.doAction?() }) {
            HStack(spacing: 4) {
                Image(systemName: viewModel.iconName)
                    .font(.subheadline)
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
    }
}


import SwiftUI

/// One numbered setup step: what it is, why, and the button that does it.
struct SetupStepRow: View {
    /// Where a step stands in the sequence.
    enum Status {
        /// Waiting on an earlier step.
        case upcoming
        /// The step to do now.
        case current
        /// Already done.
        case done
    }

    /// Position in the sequence, shown as a serif numeral.
    let number: Int
    /// What the step does.
    let title: String
    /// Why it's needed, or what to do next.
    let detail: String
    /// Where the step stands.
    let status: Status
    /// Label of the button that performs the step.
    let actionTitle: String
    /// Short confirmation shown once the step is done.
    let doneTitle: String
    /// Performs the step.
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            marker
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(SetupStyle.stepTitleFont)
                Text(detail)
                    .font(SetupStyle.detailFont)
                    .foregroundStyle(SetupStyle.ash)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 24)
            trailing
        }
        .padding(.vertical, 20)
        .opacity(status == .upcoming ? 0.38 : 1)
        .animation(SetupStyle.settle, value: status)
        .animation(SetupStyle.settle, value: detail)
    }

    /// The serif numeral, replaced by a check once the step is done.
    @ViewBuilder private var marker: some View {
        if status == .done {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .transition(.scale.combined(with: .opacity))
        } else {
            Text("\(number)")
                .font(SetupStyle.stepNumberFont)
                .foregroundStyle(status == .current ? SetupStyle.cream : SetupStyle.ash)
        }
    }

    /// The step's button, or its confirmation once done.
    @ViewBuilder private var trailing: some View {
        switch status {
        case .done:
            Text(doneTitle)
                .font(SetupStyle.detailFont)
                .foregroundStyle(SetupStyle.ash)
        case .current:
            Button(actionTitle, action: action)
                .buttonStyle(SetupButtonStyle(isProminent: true))
                .keyboardShortcut(.defaultAction)
        case .upcoming:
            Button(actionTitle, action: action)
                .buttonStyle(SetupButtonStyle(isProminent: false))
                .disabled(true)
        }
    }
}

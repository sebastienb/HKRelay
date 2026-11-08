#if targetEnvironment(macCatalyst)
import BridgeCore
import SwiftUI

struct CommandNotificationView: View {
    let activity: CommandActivity

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(activity.failureCount > 0 ? Color.orange : Color.accentColor)
                .frame(width: 46, height: 46)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("HKRelay").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Text(activity.title).font(.headline).lineLimit(1)
                Text(activity.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        if activity.activeCount > 0 { return "house.fill" }
        return activity.failureCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var status: String {
        if activity.activeCount > 1 { return "\(activity.activeCount) running" }
        if activity.activeCount == 1 { return "Running…" }
        if activity.failureCount > 0 { return "Couldn’t complete" }
        return activity.completedCount > 1 ? "\(activity.completedCount) completed" : "Done"
    }
}
#endif

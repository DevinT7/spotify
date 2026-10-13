import Observation
import SwiftUI

@Observable @MainActor
final class ToastCenter {
    struct Toast: Identifiable { let id = UUID(); let text: String; let icon: String; let isError: Bool }
    var current: Toast?
    func show(_ text: String, icon: String = "checkmark.circle.fill", error: Bool = false) {
        let t = Toast(text: text, icon: icon, isError: error)
        withAnimation(.spring(duration: 0.3)) { current = t }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if current?.id == t.id { withAnimation { current = nil } }
        }
    }
}

import SwiftUI

@main
struct TempoApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.12, green: 0.84, blue: 0.38)
    static let bg = Color(red: 0.05, green: 0.05, blue: 0.06)
    static let card = Color.white.opacity(0.07)
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showPlayer = false

    var body: some View {
        Group {
            if model.auth.isSignedIn {
                TabView {
                    tab(HomeView(), "Home", "house.fill")
                    tab(SearchView(), "Search", "magnifyingglass")
                    tab(LibraryView(), "Library", "books.vertical.fill")
                    tab(QueueView(), "Queue", "text.line.last.and.arrowtriangle.forward")
                }
                .task { await model.bootstrap() }
                .fullScreenCover(isPresented: $showPlayer) { NowPlayingView() }
                .overlay(alignment: .top) { ToastView() }
            } else {
                LoginView()
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private func tab<V: View>(_ v: V, _ title: String, _ icon: String) -> some View {
        NavigationStack { v.navigationDestinations() }
            .safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayer { showPlayer = true } }
            .tabItem { Label(title, systemImage: icon) }
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let t = model.toast.current {
            Label(t.text, systemImage: t.icon)
                .font(.subheadline.weight(.semibold)).lineLimit(1)
                .foregroundStyle(t.isError ? .red : .white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        @Bindable var auth = model.auth
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "waveform.circle.fill").font(.system(size: 80)).foregroundStyle(Theme.accent)
            Text("Tempo").font(.system(size: 40, weight: .heavy, design: .rounded))
            Text("A faster front door to your Spotify Premium.").foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text("SPOTIFY CLIENT ID").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                TextField("32-character client id", text: $auth.clientID)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                Text("Create an app at developer.spotify.com/dashboard and add the redirect URI \(AuthManager.redirectURI)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Button {
                busy = true; error = nil
                Task {
                    do { try await model.auth.signIn() } catch { self.error = error.localizedDescription }
                    busy = false
                }
            } label: {
                Text(busy ? "Waiting for Spotify…" : "Sign in with Spotify").font(.headline)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.accent, in: Capsule()).foregroundStyle(.black)
            }.disabled(busy)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(24)
    }
}

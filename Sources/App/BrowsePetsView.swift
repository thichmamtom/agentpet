import SwiftUI
import AppKit

/// A searchable gallery to download new pets into the app.
struct BrowsePetsView: View {
    @StateObject private var browser = PetBrowser()
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Browse pets").font(.headline)
                Spacer()
                Button("Done") { onClose() }
            }
            .padding(12)
            Divider()

            NativeSearchField(text: $browser.query, placeholder: "Search pets")
                .padding(.horizontal, 12).padding(.top, 12)

            Picker("Category", selection: $browser.category) {
                ForEach(PetBrowser.categories, id: \.value) { Text($0.label).tag($0.value) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12).padding(.vertical, 8)

            content
        }
        .frame(width: 460, height: 580)
        .preferredColorScheme(.dark)
        .noFocusRing()
        .onAppear { browser.loadIfNeeded() }
    }

    @ViewBuilder private var content: some View {
        if browser.isLoading {
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading pets…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = browser.errorText {
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
                Text(error).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Retry") { browser.loadIfNeeded() }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(browser.results) { pet in
                        RemotePetRow(pet: pet, browser: browser)
                        Divider()
                    }
                }
            }
        }
    }
}

private struct RemotePetRow: View {
    let pet: RemotePet
    @ObservedObject var browser: PetBrowser

    var body: some View {
        HStack(spacing: 12) {
            FirstFrameThumb(urlString: pet.spritesheetUrl)
                .frame(width: 44, height: 48)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))

            VStack(alignment: .leading, spacing: 2) {
                Text(pet.name).font(.system(size: 13, weight: .medium))
                Text("by \(pet.author)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()

            if browser.downloading.contains(pet.slug) {
                ProgressView().controlSize(.small)
            } else if browser.installed.contains(pet.slug) {
                Label("Added", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
            } else {
                Button("Get") { browser.download(pet) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

/// Shows just the top-left frame of an 8×9 spritesheet, loaded on demand.
private struct FirstFrameThumb: View {
    let urlString: String
    // A custom loader (not AsyncImage) so we can send the Referer the Petdex
    // CDN now requires; otherwise the thumbnail request 403s.
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 44 * 8, height: 48 * 9)
                    .frame(width: 44, height: 48, alignment: .topLeading)
                    .clipped()
            } else if failed {
                Image(systemName: "pawprint").foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: urlString) {
            guard let url = URL(string: urlString) else { failed = true; return }
            do {
                let (data, _) = try await URLSession.shared.data(for: PetdexAssets.request(url))
                if let img = NSImage(data: data) { image = img } else { failed = true }
            } catch { failed = true }
        }
    }
}

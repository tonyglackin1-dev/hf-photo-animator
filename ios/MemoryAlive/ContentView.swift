import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var model = MemoryAliveViewModel()
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Group {
                    if let image = model.previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(.secondary.opacity(0.12))
                            .overlay(Text("Choose an old photo"))
                            .aspectRatio(4/5, contentMode: .fit)
                    }
                }
                .frame(maxHeight: 520)

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                HStack {
                    actionButton("Restore", systemImage: "wand.and.stars", action: model.restore)
                    actionButton("Colourise", systemImage: "paintpalette", action: model.colourise)
                    actionButton("Bring to Life", systemImage: "face.smiling", action: model.animatePortrait)
                }

                if model.isWorking {
                    ProgressView(model.status)
                } else {
                    Text(model.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("Memory Alive")
        }
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue else { return }
            Task { await model.load(item: newValue) }
        }
    }

    @ViewBuilder
    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(.bordered)
        .disabled(model.previewImage == nil || model.isWorking)
    }
}

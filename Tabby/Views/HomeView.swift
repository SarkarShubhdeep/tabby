import PhotosUI
import SwiftUI
import VisionKit

struct HomeView: View {
    @Environment(BillSession.self) private var session
    @Environment(Router.self) private var router
    @State private var showScanner = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                Text("Tabby")
                    .font(.largeTitle.bold())
                Text("Snap the bill, tap who had what,\nand get everyone's share.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 12) {
                if VNDocumentCameraViewController.isSupported {
                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan Bill", systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    session.startNewBill()
                    router.path = [.review]
                } label: {
                    Label("Enter Manually", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.horizontal)
        }
        .padding(.bottom)
        .disabled(isReading)
        .overlay {
            if isReading {
                ProgressView("Reading bill…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { images in
                showScanner = false
                read(images)
            } onCancel: {
                showScanner = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await loadPhoto(item) }
        }
        .alert("Couldn't read the bill", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "That photo couldn't be opened."
                return
            }
            read([image])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func read(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        isReading = true
        Task {
            defer { isReading = false }
            do {
                let rows = try await TextRecognizer.rows(in: images)
                session.startNewBill()
                session.load(ReceiptParser.parse(rows: rows))
                router.path = [.review]
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

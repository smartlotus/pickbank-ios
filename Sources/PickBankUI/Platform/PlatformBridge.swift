import PickBankCore
import SwiftUI
#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

public extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}

public enum PickBankBundle {
    public static var resources: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    public static func petAssetURL(subdirectory: String, fileName: String) -> URL? {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        let subPath = subdirectory.isEmpty ? "PetAssets" : "PetAssets/\(subdirectory)"

        if let url = resources.url(forResource: base, withExtension: ext, subdirectory: subPath) {
            return url
        }
        if let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: subPath) {
            return url
        }
        if let rootURL = resources.resourceURL?
            .appendingPathComponent("PetAssets", isDirectory: true)
            .appendingPathComponent(subdirectory, isDirectory: true)
            .appendingPathComponent(fileName),
           FileManager.default.fileExists(atPath: rootURL.path) {
            return rootURL
        }
        return nil
    }

    public static func loadPetImage(subdirectory: String, fileName: String) -> PlatformImage? {
        guard let url = petAssetURL(subdirectory: subdirectory, fileName: fileName),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return PlatformImage(data: data)
    }

    public static func loadManifest() -> PetAssetManifest? {
        guard let url = petAssetURL(subdirectory: "", fileName: "pet_manifest.json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(PetAssetManifest.self, from: data)
    }
}

public enum PickBankPasteboard {
    public static func copy(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

public extension View {
    @ViewBuilder
    func pickbankDecimalKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func pickbankNumbersAndPunctuationKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.numbersAndPunctuation)
        #else
        self
        #endif
    }

    @ViewBuilder
    func pickbankInlineNavBar() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func pickbankNoAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    @ViewBuilder
    func pickbankInsetGroupedList() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }

    @ViewBuilder
    func pickbankHoverLift() -> some View {
        #if os(iOS)
        self.hoverEffect(.lift)
        #else
        self
        #endif
    }
}

public struct ShareSheetBridge: View {
    public let items: [Any]
    @Environment(\.dismiss) private var dismiss

    public init(items: [Any]) {
        self.items = items
    }

    public var body: some View {
        #if canImport(UIKit)
        UIKitActivitySheet(items: items)
        #else
        VStack(spacing: 14) {
            Text("文件已保存")
                .font(.headline)
            if let url = items.first as? URL {
                Text(url.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            Button("完成") { dismiss() }
        }
        .padding(24)
        #endif
    }
}

#if canImport(UIKit)
private struct UIKitActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

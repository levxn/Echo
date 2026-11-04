import SwiftUI
import UIKit

/// Meta's Muse mark, shown wherever Muse itself produced the content (an answer, a draft, a summary) and as the Ask tab's icon.
///
/// The mark is Meta's trademark, so Echo uses only the official asset, never a redrawn copy: add it to `Assets.xcassets` as an image set
/// named `MuseMark` (an SVG with "Preserve Vector Data" is best). Until it is there, every place falls back to the cloud symbol it used
/// before, so nothing looks broken and adding the file is the only step.
enum MuseMark {
    static let assetName = "MuseMark"
    /// True once the official asset has been added to the app.
    static var isAvailable: Bool { UIImage(named: assetName) != nil }
}

/// The Muse mark at the size of the text beside it, or the cloud symbol if the asset isn't there yet.
struct MuseIcon: View {
    /// Roughly the height of the text it sits beside.
    var size: CGFloat = 14
    var fallbackSymbol = "cloud.fill"

    var body: some View {
        if MuseMark.isAvailable {
            Image(MuseMark.assetName)
                .resizable()
                .scaledToFit()
                .frame(height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: fallbackSymbol)
        }
    }
}

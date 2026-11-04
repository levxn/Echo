import MapKit
import SwiftUI

/// Where the watch was when it heard things: a map, and the places in the order they were heard most. Name a place so Echo can say
/// "at the office", or mark it as somewhere nothing should be recorded. Kept on this phone; a name is only yours.
struct PlacesSection: View {
    let model: PipelineModel
    /// Only this day's places; every day's when nil.
    var day: String?
    @Environment(PlacesModel.self) private var places
    @State private var naming: PlaceCluster?
    @State private var nameText = ""

    private var clusters: [PlaceCluster] { PlaceLogic.clusters(from: day.map { model.chunks(on: $0) } ?? model.chunks, places: places.places) }

    var body: some View {
        if !clusters.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader("Places", meta: "\(clusters.count)")
                Label("Roughly where the watch was when it heard things. Kept on this phone and never sent to Muse.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Map(initialPosition: .automatic) {
                    ForEach(clusters) { cluster in
                        Marker(cluster.title, systemImage: cluster.place?.noRecord == true ? "eye.slash.fill" : "mic.fill",
                               coordinate: CLLocationCoordinate2D(latitude: cluster.coordinate.lat, longitude: cluster.coordinate.lon))
                            .tint(cluster.place == nil ? Palette.blue : (cluster.place?.noRecord == true ? Palette.rose : Palette.teal))
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .mapControlVisibility(.hidden)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.stroke))
                .accessibilityLabel("Map of \(clusters.count) places")

                VStack(spacing: Spacing.sm) {
                    ForEach(clusters) { cluster in row(cluster) }
                }
            }
            .alert("Name this place", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
                TextField("Home, the office…", text: $nameText)
                Button("Save") {
                    if let cluster = naming { Task { await places.name(cluster, as: nameText) } }
                    naming = nil
                }
                Button("Cancel", role: .cancel) { naming = nil }
            } message: {
                Text("Only you see this name.")
            }
        }
    }

    private func row(_ cluster: PlaceCluster) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: cluster.place?.noRecord == true ? "eye.slash.fill" : (cluster.place == nil ? "mappin.and.ellipse" : "mappin.circle.fill"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(cluster.place?.noRecord == true ? Palette.rose : (cluster.place == nil ? Palette.blue : Palette.teal))
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(cluster.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("\(cluster.count) moment\(cluster.count == 1 ? "" : "s")" + (cluster.place?.noRecord == true ? " · never recorded here" : ""))
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
            Menu {
                Button(cluster.place == nil ? "Name this place…" : "Rename…", systemImage: "pencil") {
                    nameText = cluster.place?.name ?? ""
                    naming = cluster
                }
                if let place = cluster.place {
                    Button(place.noRecord ? "Allow recording here" : "Never record here", systemImage: place.noRecord ? "mic.fill" : "eye.slash") {
                        Task { await places.setNoRecord(place.id, !place.noRecord) }
                    }
                    Button("Forget this name", systemImage: "trash", role: .destructive) { Task { await places.forget(place.id) } }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More for \(cluster.title)")
        }
        .frame(minHeight: 44)
        .echoRow(vertical: Spacing.xs)
        .accessibilityElement(children: .contain)
    }
}

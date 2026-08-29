import SwiftUI

struct Lozenge: View {
  let category: BPCategory
  var large = false

  var body: some View {
    Text(category.rating == "Good" ? "Good · Normal" : "Bad · \(category.label)")
      .font(large ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
      .padding(.horizontal, large ? 12 : 8)
      .padding(.vertical, large ? 6 : 3)
      .foregroundStyle(.white)
      .background(Theme.zone(category.tone), in: Capsule())
  }
}

struct StatCard: View {
  let title: String
  var value: String? = nil
  var accessory: AnyView? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title.uppercased())
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Theme.muted)
      if let accessory {
        accessory
      } else {
        Text(value ?? "—")
          .font(.title2.weight(.semibold))
          .foregroundStyle(Theme.ink)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    )
  }
}

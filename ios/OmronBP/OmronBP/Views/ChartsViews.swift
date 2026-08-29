import Charts
import SwiftUI

struct TimeSeriesChartView: View {
  let readings: [BPReading]

  private var chronological: [BPReading] { readings.reversed() }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Readings over time")
          .font(.headline)
        Spacer()
      }
      HStack(spacing: 12) {
        legend(Theme.sys, "Systolic")
        legend(Theme.dia, "Diastolic")
        legend(Theme.pulse, "Pulse")
        legend(Theme.dia, "120 / 80")
      }
      .font(.caption)
      .foregroundStyle(Theme.muted)

      Chart {
        ForEach([80, 120, 130, 140, 180], id: \.self) { value in
          RuleMark(y: .value("Guide", value))
            .foregroundStyle(guideColor(value).opacity(0.45))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        ForEach(Array(chronological.enumerated()), id: \.offset) { index, row in
          LineMark(
            x: .value("n", index),
            y: .value("mmHg", row.sys),
            series: .value("Series", "Systolic")
          )
          .foregroundStyle(Theme.sys)
          LineMark(
            x: .value("n", index),
            y: .value("mmHg", row.dia),
            series: .value("Series", "Diastolic")
          )
          .foregroundStyle(Theme.dia)
          LineMark(
            x: .value("n", index),
            y: .value("mmHg", row.bpm),
            series: .value("Series", "Pulse")
          )
          .foregroundStyle(Theme.pulse)
        }
      }
      .chartYScale(domain: 40...180)
      .chartXAxis(.hidden)
      .frame(height: 220)
      .overlay {
        if readings.isEmpty {
          Text("Connect to plot readings against 120/80.")
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
      }
    }
    .padding(12)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    )
  }

  private func legend(_ color: Color, _ title: String) -> some View {
    HStack(spacing: 4) {
      Circle().fill(color).frame(width: 8, height: 8)
      Text(title)
    }
  }

  private func guideColor(_ value: Int) -> Color {
    switch value {
    case 80, 120: return Theme.dia
    case 130: return Theme.stage1
    case 140: return Theme.stage2
    default: return Theme.crisis
    }
  }
}

struct RangeGuideChartView: View {
  let readings: [BPReading]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Recommended ranges (ACC/AHA)")
        .font(.headline)
      HStack(spacing: 6) {
        Lozenge(category: BPCategory.rate(sys: 110, dia: 70))
        Text("Elevated").font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
          .background(Theme.elevated, in: Capsule()).foregroundStyle(.white)
        Text("Stage 1").font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
          .background(Theme.stage1, in: Capsule()).foregroundStyle(.white)
        Text("Stage 2").font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
          .background(Theme.stage2, in: Capsule()).foregroundStyle(.white)
        Text("Crisis").font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
          .background(Theme.crisis, in: Capsule()).foregroundStyle(.white)
      }
      Canvas { context, size in
        let diaMin = 40.0, diaMax = 130.0, sysMin = 70.0, sysMax = 200.0
        let padL = 36.0, padR = 10.0, padT = 10.0, padB = 28.0
        let plotW = size.width - padL - padR
        let plotH = size.height - padT - padB
        func xAt(_ dia: Double) -> CGFloat { padL + ((dia - diaMin) / (diaMax - diaMin)) * plotW }
        func yAt(_ sys: Double) -> CGFloat { padT + ((sysMax - sys) / (sysMax - sysMin)) * plotH }

        let step = 4.0
        var dia = diaMin
        while dia < diaMax {
          var sys = sysMin
          while sys < sysMax {
            let tone = BPCategory.rate(sys: Int(sys + step / 2), dia: Int(dia + step / 2)).tone
            let rect = CGRect(
              x: xAt(dia),
              y: yAt(sys + step),
              width: max(1, xAt(dia + step) - xAt(dia)),
              height: max(1, yAt(sys) - yAt(sys + step))
            )
            context.fill(Path(rect), with: .color(Theme.zone(tone).opacity(0.28)))
            sys += step
          }
          dia += step
        }

        var dash = Path()
        dash.move(to: CGPoint(x: xAt(80), y: yAt(sysMin)))
        dash.addLine(to: CGPoint(x: xAt(80), y: yAt(sysMax)))
        dash.move(to: CGPoint(x: xAt(diaMin), y: yAt(120)))
        dash.addLine(to: CGPoint(x: xAt(diaMax), y: yAt(120)))
        context.stroke(dash, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

        context.stroke(
          Path(CGRect(x: padL, y: padT, width: plotW, height: plotH)),
          with: .color(Theme.line)
        )

        context.draw(Text("80").font(.caption2).foregroundColor(Theme.ink), at: CGPoint(x: xAt(80), y: size.height - 10))
        context.draw(Text("120").font(.caption2).foregroundColor(Theme.ink), at: CGPoint(x: 18, y: yAt(120)))
        context.draw(Text("Diastolic").font(.caption2).foregroundColor(Theme.ink), at: CGPoint(x: size.width / 2, y: size.height - 8))

        for (i, row) in readings.enumerated() {
          let x = xAt(min(diaMax, max(diaMin, Double(row.dia))))
          let y = yAt(min(sysMax, max(sysMin, Double(row.sys))))
          let r: CGFloat = i == 0 ? 6 : 4
          let dot = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
          context.fill(dot, with: .color(i == 0 ? Theme.ink : Theme.muted))
          context.stroke(dot, with: .color(Theme.card), lineWidth: 1.5)
        }
      }
      .frame(height: 220)
    }
    .padding(12)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    )
  }
}

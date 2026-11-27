import SwiftUI
import GoldfishCore

/// Name the fish, learn the loop, then teach the built-in sample chapter.
/// Works with no connection and no cloud quota.
/// Laid out like the Figma onboarding carousel: Finn's tank as the picture, page dots, a purple title,
/// Finn's line as the body, Skip at the top and Next at the bottom.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var name = "Finn"
    @FocusState private var nameFocused: Bool

    private let stepCount = 4

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if step < stepCount - 1 {
                    Button("Skip") { finish() }
                        .font(.poppins(.body))
                        .foregroundStyle(Theme.link)
                        .accessibilityHint("Starts with the sample chapter")
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 16)

            ScrollView {
                VStack(spacing: 0) {
                    PixelTank(mood: mood, scale: step == 2 ? 4 : 5, fishAt: UnitPoint(x: 0.5, y: 0.6), weeds: [0.06, 0.86])
                        .frame(maxWidth: 320)
                        .frame(height: step == 2 ? 180 : 240)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                        .padding(.top, step == 2 ? 8 : 24)

                    PageDots(count: stepCount, current: step)
                        .padding(.top, 30)

                    Text(title)
                        .font(.poppins(.title2))
                        .foregroundStyle(Theme.link)
                        .multilineTextAlignment(.center)
                        .padding(.top, 26)
                        .accessibilityAddTraits(.isHeader)

                    if let line = line {
                        Text(line)
                            .font(.poppins(.body))
                            .foregroundStyle(Theme.ink2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                            .padding(.horizontal, 18)
                    }

                    stepContent
                        .padding(.top, 22)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            bottomBar
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .screenBackground()
        .animation(.easeInOut, value: step)
    }

    private var mood: FishMood {
        switch step {
        case 0: return .confused
        case 1: return .curious
        case 2: return .listening
        default: return .happy
        }
    }

    private var title: String {
        switch step {
        case 0: return "Meet your goldfish"
        case 1: return "Give him a name"
        case 2: return "How it works"
        default: return "Ready to teach"
        }
    }

    /// Finn's line for the step. He speaks in quotes.
    private var line: String? {
        switch step {
        case 0:
            return "\u{201C}Who are you? I'm a goldfish. I know nothing, and I forget everything overnight.\u{201D}"
        case 1:
            return "\u{201C}What should I be called?\u{201D}"
        case 2:
            return nil
        default:
            return "\u{201C}When I get something wrong, I'll show you which of your sentences confused me. Let's start with a chapter about me!\u{201D}"
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 1:
            LabeledField(label: "Fish name") {
                FishView(mood: .happy, size: 24, showsBubble: false)
                    .accessibilityHidden(true)
                TextField("Fish name", text: $name)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { advance() }
                    .onAppear { nameFocused = true }
            }
        case 2:
            VStack(alignment: .leading, spacing: 18) {
                loopRow(FinnSprites.page, "Teach", "Explain each idea in your own words, from memory.")
                loopRow(FinnSprites.phone, "Quiz the fish", "\(displayName) answers on this iPhone, even offline.")
                loopRow(FinnSprites.mastered, "Your Turn", "Then you answer. Your answers decide what you have mastered.")
            }
        default:
            EmptyView()
        }
    }

    private func loopRow(_ mark: PixelSprite, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            IconTile(size: 44, fill: Theme.lavender) {
                PixelMark(sprite: mark, scale: 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.poppins(.headline))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.poppins(.subheadline, weight: .regular))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if step == stepCount - 1 {
            Button("Teach \(displayName) about goldfish") {
                advance()
            }
            .buttonStyle(.primary)
        } else {
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .font(.poppins(.callout, weight: .medium))
                        .foregroundStyle(Theme.link)
                }
                Spacer()
                Button(step == 1 ? "That's your name" : "Next") {
                    advance()
                }
                .buttonStyle(.primaryCompact)
            }
        }
    }

    private var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Finn" : trimmed
    }

    private func advance() {
        if step < stepCount - 1 {
            step += 1
        } else {
            finish()
        }
    }

    private func finish() {
        model.finishOnboarding(fishName: displayName)
    }
}

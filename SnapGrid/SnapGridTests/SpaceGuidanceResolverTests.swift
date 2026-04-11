import Testing
import Foundation
@testable import SnapGrid

@Suite("Space Guidance Resolver", .tags(.model))
struct SpaceGuidanceResolverTests {

    @Test("Combines enabled space prompts in deterministic order")
    func combinesCustomPromptsInSpaceOrder() {
        let later = Space(id: "later", name: "Later", order: 2)
        later.customPrompt = "Later prompt"
        later.useCustomPrompt = true

        let earlier = Space(id: "earlier", name: "Earlier", order: 0)
        earlier.customPrompt = "Earlier prompt"
        earlier.useCustomPrompt = true

        let disabled = Space(id: "disabled", name: "Disabled", order: 1)
        disabled.customPrompt = "Disabled prompt"
        disabled.useCustomPrompt = false

        let result = SpaceGuidanceResolver.resolve(for: [later, disabled, earlier])

        #expect(result.guidance == "Earlier prompt\n\nLater prompt")
        #expect(result.spaceContext == #"This image belongs to collections called "Earlier", "Disabled", "Later". Use these as context to inform your analysis."#)
    }

    @Test("Falls back to all-space guidance only when no enabled space prompt exists")
    func fallsBackToAllSpaceGuidanceOnlyWithoutSpacePrompts() {
        let oldPrompt = UserDefaults.standard.string(forKey: "allSpacePrompt")
        let oldUsePrompt = UserDefaults.standard.object(forKey: "useAllSpacePrompt")
        defer {
            if let oldPrompt {
                UserDefaults.standard.set(oldPrompt, forKey: "allSpacePrompt")
            } else {
                UserDefaults.standard.removeObject(forKey: "allSpacePrompt")
            }
            if let oldUsePrompt {
                UserDefaults.standard.set(oldUsePrompt, forKey: "useAllSpacePrompt")
            } else {
                UserDefaults.standard.removeObject(forKey: "useAllSpacePrompt")
            }
        }

        UserDefaults.standard.set("Fallback guidance", forKey: "allSpacePrompt")
        UserDefaults.standard.set(true, forKey: "useAllSpacePrompt")

        let plainSpace = Space(id: "plain", name: "Plain", order: 0)
        let fallbackResult = SpaceGuidanceResolver.resolve(for: [plainSpace])
        #expect(fallbackResult.guidance == "Fallback guidance")

        let promptedSpace = Space(id: "prompted", name: "Prompted", order: 0)
        promptedSpace.customPrompt = "Space-specific guidance"
        promptedSpace.useCustomPrompt = true

        let promptResult = SpaceGuidanceResolver.resolve(for: [promptedSpace])
        #expect(promptResult.guidance == "Space-specific guidance")
    }
}

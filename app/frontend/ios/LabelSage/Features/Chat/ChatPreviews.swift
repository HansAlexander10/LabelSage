import SwiftUI
import LabelSageCore

/// Preview data: the demo household (Alex and Mia) and the fixture products with no network delay.
enum ChatPreview {
    static let household: Household = (try? SampleData.household()) ?? Household(people: [])

    /// A model that has already answered `messages` (sent one after another).
    static func model(_ messages: [String]) -> ChatModel {
        let model = ChatModel(household: household, source: FixtureProductSource(delayMilliseconds: 0...0),
                              verdictService: AppServices.verdictService,
                              explanationService: ExplanationService { _ in nil })
        Task {
            for message in messages {
                model.send(message)
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        return model
    }

    static func screen(_ messages: [String]) -> some View {
        ChatScreen(model: model(messages))
            .environment(MascotPresence())
    }
}

#Preview("Start screen") {
    ChatScreen(household: ChatPreview.household, onOpenCamera: {}, onOpenProduct: { _ in }, onCompare: { _, _ in },
               onOpenFamily: {}, onUpdateHousehold: { _ in })
        .environment(MascotPresence())
}

#Preview("Check a product") {
    ChatPreview.screen(["Are the popped corn chips OK for me?"])
}

#Preview("Ask about an ingredient") {
    ChatPreview.screen(["What is tahini?"])
}

#Preview("Other options") {
    ChatPreview.screen(["kettle chips without seed oils"])
}

#Preview("Compare") {
    ChatPreview.screen(["Check the popped corn chips", "Check the canyon kettle chips", "Compare these two"])
}

#Preview("Change allergies: confirm") {
    ChatPreview.screen(["Mia reacted to hummus. Add sesame to her allergies"])
}

#Preview("Pivot") {
    ChatPreview.screen(["Is the peanut butter OK?", "What about me?"])
}

#Preview("Change card states") {
    ScrollView {
        VStack(spacing: Theme.spacing.l) {
            ForEach([ChangeProposal.State.proposed, .saved, .cancelled], id: \.self) { state in
                ChangeCard(proposal: ChangeProposal(personID: "mia", personName: "Mia", familyID: "sesame", label: "sesame",
                                                    isAllergen: true, severity: .allergy, state: state,
                                                    currentItems: ["peanut", "tree nuts"]),
                           onSeverity: { _ in }, onCancel: {}, onConfirm: {})
            }
        }
        .padding(Theme.spacing.screenGutter)
    }
    .background(Theme.screenTint.chat)
}

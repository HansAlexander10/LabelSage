import Testing
@testable import LabelSage

/// The two pieces of real logic in the T3 controls: `KindBadge` flipping and `GroupCard` selection.
struct KindBadgeTests {
    @Test func avoidAndPreferNotFlipIntoEachOther() {
        #expect(KindBadge.Kind.avoid.flipped == .preferNot)
        #expect(KindBadge.Kind.preferNot.flipped == .avoid)
    }

    @Test func dietAndGoalDoNotFlip() {
        #expect(KindBadge.Kind.diet.flipped == .diet)
        #expect(KindBadge.Kind.goal.flipped == .goal)
        #expect(!KindBadge.Kind.diet.isFlippable)
        #expect(!KindBadge.Kind.goal.isFlippable)
    }
}

struct GroupSelectionTests {
    let leaves = ["Almond", "Cashew", "Walnut"]

    @Test func countIgnoresPicksOutsideTheGroup() {
        let selection: Set<String> = ["Cashew", "Milk"]
        #expect(GroupSelection.count(selection, leaves: leaves) == 1)
        #expect(GroupSelection.countText(selection, leaves: leaves) == "1/3")
        #expect(GroupSelection.countText([], leaves: leaves) == "0/3")
    }

    @Test func allLeafPicksEveryLeafThenClearsThem() {
        let some: Set<String> = ["Cashew", "Milk"]
        let all = GroupSelection.toggledAll(some, leaves: leaves)
        #expect(all == ["Almond", "Cashew", "Walnut", "Milk"])
        #expect(GroupSelection.isAllOn(all, leaves: leaves))
        #expect(GroupSelection.toggledAll(all, leaves: leaves) == ["Milk"])
    }

    @Test func allLeafTurnsOnWhenEveryLeafIsPickedOneByOne() {
        var selection: Set<String> = []
        for leaf in leaves {
            #expect(!GroupSelection.isAllOn(selection, leaves: leaves))
            selection = GroupSelection.toggled(leaf, in: selection)
        }
        #expect(GroupSelection.isAllOn(selection, leaves: leaves))
        #expect(!GroupSelection.isAllOn(GroupSelection.toggled("Walnut", in: selection), leaves: leaves))
    }

    @Test func allTitleUsesTheLowercasedGroupName() {
        #expect(GroupSelection.allTitle(group: "Tree nuts") == "All tree nuts")
    }
}

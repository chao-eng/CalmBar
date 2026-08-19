import Foundation
import Testing
@testable import CalmBar

@Suite("Cleaner Module Tests")
struct CleanerTests {

    @Test("Test string normalization for associated file matching")
    func testStringNormalization() {
        let finder = AssociatedPathsFinder.shared
        #expect(finder.normalize("com.spotify.client") == "comspotifyclient")
        #expect(finder.normalize("Visual Studio Code") == "visualstudiocode")
        #expect(finder.normalize("Bartender 5.0.2") == "bartender502")
    }

    @Test("Test strip trailing digits from app name")
    func testStripTrailingDigits() {
        let finder = AssociatedPathsFinder.shared
        #expect(finder.stripTrailingDigits("Bartender 5") == "Bartender")
        #expect(finder.stripTrailingDigits("Firefox 120.0") == "Firefox")
        #expect(finder.stripTrailingDigits("CleanApp") == "CleanApp")
    }

    @Test("Test DevPathLibrary contains developer categories")
    func testDevPathLibraryCategories() {
        let categories = DevPathLibrary.getCategories()
        #expect(categories.count >= 6)

        let xcodeCategory = categories.first(where: { $0.name.contains("Xcode") })
        #expect(xcodeCategory != nil)
        #expect(xcodeCategory!.paths.contains(where: { $0.contains("DerivedData") }))

        let nodeCategory = categories.first(where: { $0.name.contains("Node") })
        #expect(nodeCategory != nil)
        #expect(nodeCategory!.paths.contains(where: { $0.contains(".npm") }))
    }

    @Test("Test AppArchitecture badge colors")
    func testArchitectureBadgeColor() {
        #expect(AppArchitecture.appleSilicon.badgeColor == .purple)
        #expect(AppArchitecture.intel.badgeColor == .blue)
        #expect(AppArchitecture.universal.badgeColor == .green)
    }

    @Test("Test OrphanedWorkspaceItem properties")
    func testOrphanedWorkspaceItemFormatting() {
        let item = OrphanedWorkspaceItem(
            ideName: "VS Code",
            workspaceName: "abc1234",
            storagePath: "/path/to/storage",
            projectOriginalFolderPath: "/Users/test/Projects/OldProject",
            sizeBytes: 1024 * 1024 * 50
        )
        #expect(item.projectFolderName == "OldProject")
        #expect(!item.formattedSize.isEmpty)
    }
}

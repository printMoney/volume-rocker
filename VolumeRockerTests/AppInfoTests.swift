import Testing
@testable import VolumeRocker

struct AppInfoTests {
    @Test func formatsVersionAndBuild() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "42"]
        #expect(AppInfo.versionString(from: info) == "1.2.3 (42)")
    }

    @Test func fallsBackWhenKeysAreMissing() {
        #expect(AppInfo.versionString(from: [:]) == "0.0.0 (0)")
    }

    @Test func repositoryLinksAreValid() {
        #expect(AppInfo.repositoryURL?.host() == "github.com")
        #expect(AppInfo.issuesURL?.lastPathComponent == "issues")
    }
}

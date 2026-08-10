import XCTest
import Foundation
@testable import forgery_lib
import GitKit

class StatusTests: XCTestCase {
    
    private var tempDirectory: String!
    private var fileManager: FileManager!
    
    override func setUp() {
        super.setUp()
        fileManager = FileManager.default
        
        // Create a unique temporary directory for each test
        let tempDir = NSTemporaryDirectory()
        tempDirectory = "\(tempDir)forgery-test-\(UUID().uuidString)"
        
        try! fileManager.createDirectory(atPath: tempDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    override func tearDown() {
        // Clean up temporary directory
        if let tempDir = tempDirectory {
            try? fileManager.removeItem(atPath: tempDir)
        }
        super.tearDown()
    }

    func testStarredRepositoryStructure() throws {
        // Setup: Create starred repository structure
        try createStarredRepoStructure()
        
        // Test: Get paths for a user and check starred repos are included
        let allReposOptions = allReposOptions()
        
        let userPaths = try UserPaths(
            basePath: tempDirectory,
            username: "testuser", 
            repoTypes: allReposOptions,
            createOnDisk: false
        )
        
        let expectedStarredPath = "\(tempDirectory!)/user/testuser/repos/starred"
        XCTAssertTrue(userPaths.validPaths.contains(expectedStarredPath), "Starred repo path should be included in valid paths")
        XCTAssertEqual(userPaths.starredRepoPath, expectedStarredPath, "Starred repo path should match expected path")
    }
    
    func testForkedRepositoryStructure() throws {
        // Setup: Create forked repository structure
        try createForkedRepoStructure()
        
        // Test: Get paths and verify forked repos are included via CommonPaths
        let allReposOptions = allReposOptions()
        
        let userPaths = try UserPaths(
            basePath: tempDirectory,
            username: "testuser",
            repoTypes: allReposOptions,
            createOnDisk: false
        )
        
        let expectedForkedPath = "\(tempDirectory!)/user/testuser/repos/forked"
        XCTAssertTrue(userPaths.validPaths.contains(expectedForkedPath), "Forked repo path should be included in valid paths")
        XCTAssertEqual(userPaths.commonPaths.repoPaths.forkPath, expectedForkedPath, "Forked repo path should match expected path")
    }
    
    func testDirectoryStructureDetection() throws {
        // Setup: Create mixed repository structure
        try createStarredRepoStructure()
        try createForkedRepoStructure()
        try createRegularRepoStructure()
        
        // Test: Verify that starred and forked paths are detected correctly
        let starredPath = "\(tempDirectory!)/user/testuser/repos/starred"
        let forkedPath = "\(tempDirectory!)/user/testuser/repos/forked" 
        let publicPath = "\(tempDirectory!)/user/testuser/repos/public"
        
        // Verify starred repos exist with owner/repo structure
        let starredContents = try fileManager.contentsOfDirectory(atPath: starredPath)
        XCTAssertTrue(starredContents.contains("owner1"), "Starred path should contain owner1 directory")
        XCTAssertTrue(starredContents.contains("owner2"), "Starred path should contain owner2 directory")
        XCTAssertTrue(starredContents.contains("github"), "Starred path should contain github directory")
        
        // Verify owner directories contain actual repos
        let owner1Contents = try fileManager.contentsOfDirectory(atPath: "\(starredPath)/owner1")
        XCTAssertTrue(owner1Contents.contains("awesome-repo"), "Owner1 should contain awesome-repo")
        XCTAssertTrue(owner1Contents.contains("another-repo"), "Owner1 should contain another-repo")
        
        // Verify forked repos exist with owner/repo structure
        let forkedContents = try fileManager.contentsOfDirectory(atPath: forkedPath)
        XCTAssertTrue(forkedContents.contains("apache"), "Forked path should contain apache directory")
        XCTAssertTrue(forkedContents.contains("facebook"), "Forked path should contain facebook directory")
        XCTAssertTrue(forkedContents.contains("microsoft"), "Forked path should contain microsoft directory")
        
        // Verify public repos have direct structure (no owner level)
        let publicContents = try fileManager.contentsOfDirectory(atPath: publicPath)
        XCTAssertTrue(publicContents.contains("my-public-repo"), "Public path should contain my-public-repo directly")
        XCTAssertTrue(publicContents.contains("my-blog"), "Public path should contain my-blog directly")
    }
    
    func testGitRepositoriesExist() throws {
        // Setup: Create test repositories
        try createStarredRepoStructure()
        try createForkedRepoStructure()
        try createRegularRepoStructure()
        
        // Test: Verify .git directories exist in the correct locations
        let testPaths = [
            "\(tempDirectory!)/user/testuser/repos/starred/owner1/awesome-repo/.git",
            "\(tempDirectory!)/user/testuser/repos/starred/github/swift/.git",
            "\(tempDirectory!)/user/testuser/repos/forked/apache/kafka/.git",
            "\(tempDirectory!)/user/testuser/repos/forked/facebook/react/.git",
            "\(tempDirectory!)/user/testuser/repos/public/my-public-repo/.git",
            "\(tempDirectory!)/user/testuser/repos/private/my-private-repo/.git"
        ]
        
        for gitPath in testPaths {
            XCTAssertTrue(fileManager.fileExists(atPath: gitPath), "Git directory should exist at \(gitPath)")
        }
    }
    
    func testRepoTypeFiltering() throws {
        // Test: Verify that repo type filtering works correctly
        let repoTypesNoStarred = RepoTypeOptions.Resolved(
            noRepos: false, noForkedRepos: false, noStarredRepos: true, noPublicRepos: false, noPrivateRepos: false,
            onlyStarredRepos: false, onlyForkedRepos: false, onlyPublicRepos: false, onlyPrivateRepos: false,
            noWikis: false, noGists: false, noForkedGists: false, noStarredGists: false, noPublicGists: false, noPrivateGists: false,
            onlyStarredGists: false, onlyForkedGists: false, onlyPublicGists: false, onlyPrivateGists: false
        )
        
        let userPaths = try UserPaths(
            basePath: tempDirectory,
            username: "testuser",
            repoTypes: repoTypesNoStarred,
            createOnDisk: false
        )
        
        let starredPath = "\(tempDirectory!)/user/testuser/repos/starred"
        XCTAssertFalse(userPaths.validPaths.contains(starredPath), "Starred repo path should be excluded when noStarredRepos is true")
    }
}

private extension StatusTests {
    /// Creates a RepoTypeOptions.Resolved with all repos enabled
    func allReposOptions() -> RepoTypeOptions.Resolved {
        return RepoTypeOptions.Resolved(
            noRepos: false, noForkedRepos: false, noStarredRepos: false, noPublicRepos: false, noPrivateRepos: false,
            onlyStarredRepos: false, onlyForkedRepos: false, onlyPublicRepos: false, onlyPrivateRepos: false,
            noWikis: false, noGists: false, noForkedGists: false, noStarredGists: false, noPublicGists: false, noPrivateGists: false,
            onlyStarredGists: false, onlyForkedGists: false, onlyPublicGists: false, onlyPrivateGists: false
        )
    }

    /// Creates a git repository at the specified path
    func createGitRepo(at path: String, withFile fileName: String = "test.txt", content: String = "test") throws {
        try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)

        let git = Git(path: path)
        try git.run(.raw("init"))
        try git.run(.raw("config user.name 'Test User'"))
        try git.run(.raw("config user.email 'test@example.com'"))

        // Create a test file
        let filePath = "\(path)/\(fileName)"
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)

        try git.run(.addAll)
        try git.run(.commit(message: "Initial commit", allowEmpty: false))
    }

    /// Creates a directory structure for starred repositories
    func createStarredRepoStructure() throws {
        // Create starred repos: basePath/user/username/repos/starred/owner/repo
        let starredPath = "\(tempDirectory!)/user/testuser/repos/starred"

        // Create multiple owners with repos
        try createGitRepo(at: "\(starredPath)/owner1/awesome-repo")
        try createGitRepo(at: "\(starredPath)/owner1/another-repo", withFile: "README.md", content: "# Another Repo")
        try createGitRepo(at: "\(starredPath)/owner2/cool-project")
        try createGitRepo(at: "\(starredPath)/github/swift", withFile: "Package.swift", content: "// Swift package")
    }

    /// Creates a directory structure for forked repositories
    func createForkedRepoStructure() throws {
        // Create forked repos: basePath/user/username/repos/forked/owner/repo
        let forkedPath = "\(tempDirectory!)/user/testuser/repos/forked"

        // Create multiple owners with repos
        try createGitRepo(at: "\(forkedPath)/apache/kafka")
        try createGitRepo(at: "\(forkedPath)/facebook/react", withFile: "index.js", content: "console.log('Hello React');")
        try createGitRepo(at: "\(forkedPath)/microsoft/vscode")
    }

    /// Creates a directory structure for regular (public/private) repositories
    func createRegularRepoStructure() throws {
        // Create regular repos: basePath/user/username/repos/public/repo (no owner level)
        let publicPath = "\(tempDirectory!)/user/testuser/repos/public"
        let privatePath = "\(tempDirectory!)/user/testuser/repos/private"

        try createGitRepo(at: "\(publicPath)/my-public-repo")
        try createGitRepo(at: "\(publicPath)/my-blog", withFile: "index.html", content: "<h1>My Blog</h1>")
        try createGitRepo(at: "\(privatePath)/my-private-repo")
    }
}

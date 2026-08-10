import XCTest
import Foundation
import ArgumentParser
@testable import forgery_lib
import GitKit

/// Tests for the Status command's repository checking functionality
class StatusCommandTests: XCTestCase {
    
    private var tempDirectory: String!
    private var fileManager: FileManager!
    
    override func setUp() {
        super.setUp()
        fileManager = FileManager.default
        
        // Create a unique temporary directory for each test
        let tempDir = NSTemporaryDirectory()
        tempDirectory = "\(tempDir)forgery-status-test-\(UUID().uuidString)"
        
        try! fileManager.createDirectory(atPath: tempDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    override func tearDown() {
        // Clean up temporary directory
        if let tempDir = tempDirectory {
            try? fileManager.removeItem(atPath: tempDir)
        }
        super.tearDown()
    }
    
    // MARK: - Tests for Directory Structure Handling
    
    func testRegularRepoDirectoryHandling() async throws {
        // Setup: Create regular repos with direct structure
        try await createGitRepoWithChanges(at: "\(tempDirectory!)/user/testuser/repos/public/test-repo", hasUncommittedChanges: true)
        
        // Get the paths that would be checked by Status command
        let allReposOptions = allReposOptions()
        
        let userPaths = try UserPaths(
            basePath: tempDirectory,
            username: "testuser",
            repoTypes: allReposOptions,
            createOnDisk: false
        )
        
        // Verify the public path is included
        let publicPath = "\(tempDirectory!)/user/testuser/repos/public"
        XCTAssertTrue(userPaths.validPaths.contains(publicPath), "Public repo path should be in validPaths")
        
        // Verify the repo exists and can be found
        let repoPath = "\(publicPath)/test-repo"
        let gitPath = "\(repoPath)/.git"
        XCTAssertTrue(fileManager.fileExists(atPath: gitPath), "Git repo should exist at expected path")
    }
    
    func testStarredRepoDirectoryHandling() async throws {
        // Setup: Create starred repos with owner/repo structure
        try await createGitRepoWithChanges(at: "\(tempDirectory!)/user/testuser/repos/starred/owner/test-starred-repo", hasUncommittedChanges: true)
        
        // Get the paths that would be checked by Status command
        let allReposOptions = allReposOptions()
        
        let userPaths = try UserPaths(
            basePath: tempDirectory,
            username: "testuser", 
            repoTypes: allReposOptions,
            createOnDisk: false
        )
        
        // Verify the starred path is included
        let starredPath = "\(tempDirectory!)/user/testuser/repos/starred"
        XCTAssertTrue(userPaths.validPaths.contains(starredPath), "Starred repo path should be in validPaths")
        
        // Verify the repo exists at the owner/repo level
        let repoPath = "\(starredPath)/owner/test-starred-repo"
        let gitPath = "\(repoPath)/.git"
        XCTAssertTrue(fileManager.fileExists(atPath: gitPath), "Starred git repo should exist at owner/repo path")
        
        // Verify the owner directory exists
        let ownerPath = "\(starredPath)/owner"
        XCTAssertTrue(fileManager.fileExists(atPath: ownerPath), "Owner directory should exist in starred path")
    }
    
    func testForkedRepoDirectoryHandling() async throws {
        // Setup: Create forked repos with owner/repo structure  
        try await createGitRepoWithChanges(at: "\(tempDirectory!)/user/testuser/repos/forked/upstream/test-forked-repo", hasUncommittedChanges: true)
        
        // Get the paths that would be checked by Status command
        let allReposOptions = allReposOptions()
        
        let userPaths = try UserPaths(
            basePath: tempDirectory,
            username: "testuser",
            repoTypes: allReposOptions,
            createOnDisk: false
        )
        
        // Verify the forked path is included via commonPaths
        let forkedPath = "\(tempDirectory!)/user/testuser/repos/forked"
        XCTAssertTrue(userPaths.validPaths.contains(forkedPath), "Forked repo path should be in validPaths")
        
        // Verify the repo exists at the owner/repo level
        let repoPath = "\(forkedPath)/upstream/test-forked-repo"
        let gitPath = "\(repoPath)/.git"
        XCTAssertTrue(fileManager.fileExists(atPath: gitPath), "Forked git repo should exist at owner/repo path")
    }
    
    func testMixedDirectoryStructures() async throws {
        // Setup: Create complete test directory structure
        try await createTestDirectoryStructure()
        
        // Get all valid paths that Status command would check
        let allReposOptions = allReposOptions()
        
        let userPaths = try UserPaths(
            basePath: tempDirectory,
            username: "testuser",
            repoTypes: allReposOptions,
            createOnDisk: false
        )
        
        let expectedPaths = [
            "\(tempDirectory!)/user/testuser/repos/public",    // Regular public repos (direct)
            "\(tempDirectory!)/user/testuser/repos/private",   // Regular private repos (direct)  
            "\(tempDirectory!)/user/testuser/repos/forked",    // Forked repos (owner/repo)
            "\(tempDirectory!)/user/testuser/repos/starred"    // Starred repos (owner/repo)
        ]
        
        for expectedPath in expectedPaths {
            XCTAssertTrue(userPaths.validPaths.contains(expectedPath), "Path \(expectedPath) should be in validPaths")
        }
        
        // Verify each type of repository structure exists
        XCTAssertTrue(fileManager.fileExists(atPath: "\(tempDirectory!)/user/testuser/repos/public/clean-repo/.git"))
        XCTAssertTrue(fileManager.fileExists(atPath: "\(tempDirectory!)/user/testuser/repos/starred/owner1/starred-clean/.git"))
        XCTAssertTrue(fileManager.fileExists(atPath: "\(tempDirectory!)/user/testuser/repos/forked/upstream1/forked-clean/.git"))
    }
    
    // MARK: - Tests for Status Detection
    
    func testLocalOnlyBranchDetection() async throws {
        // Setup: Create repo with local-only branch (no upstream)
        let repoPath = "\(tempDirectory!)/local-only-test"
        try fileManager.createDirectory(atPath: repoPath, withIntermediateDirectories: true, attributes: nil)
        
        let git = Git(path: repoPath)
        try await git.run(.raw("init"))
        try await git.run(.raw("config user.name 'Test User'"))
        try await git.run(.raw("config user.email 'test@example.com'"))
        
        // Create initial commit on main
        try "initial".write(toFile: "\(repoPath)/initial.txt", atomically: true, encoding: .utf8)
        try await git.run(.addAll)
        try await git.run(.commit(message: "Initial commit", allowEmpty: false))
        
        // Create local-only branch
        try await git.run(.checkout(branch: "feature-branch", create: true))
        try "feature".write(toFile: "\(repoPath)/feature.txt", atomically: true, encoding: .utf8)
        try await git.run(.addAll)
        try await git.run(.commit(message: "Feature commit", allowEmpty: false))
        
        // Test: Get branch info
        let branchInfo = try await getBranchInfo(repoPath: repoPath)
        
        XCTAssertTrue(branchInfo.localOnlyBranches.contains { $0.name == "feature-branch" }, "feature-branch should be detected as local-only")
        XCTAssertTrue(branchInfo.localOnlyBranches.contains { $0.name == "main" }, "main should be detected as local-only (no remote)")
        XCTAssertEqual(branchInfo.branchesWithUnpushedCommits.count, 0, "Should have no unpushed branches (no upstreams configured)")
        
        // Test: Repository summary should include local-only indicator
        let summary = try await summarizeStatus(repoPath: repoPath, pushWIPChanges: false)
        XCTAssertTrue(summary.status.contains(.localOnlyBranches), "Summary should indicate local-only branches")
        XCTAssertTrue(summary.description.contains("L"), "Status description should include L indicator")
        XCTAssertEqual(summary.localOnlyBranches.count, 2, "Should have 2 local-only branches")
    }
    
    func testMixedStatusIndicators() async throws {
        // Setup: Create repo with both uncommitted changes and local-only branches
        let repoPath = "\(tempDirectory!)/mixed-status-test"
        try fileManager.createDirectory(atPath: repoPath, withIntermediateDirectories: true, attributes: nil)
        
        let git = Git(path: repoPath)
        try await git.run(.raw("init"))
        try await git.run(.raw("config user.name 'Test User'"))
        try await git.run(.raw("config user.email 'test@example.com'"))
        
        // Create initial commit
        try "initial".write(toFile: "\(repoPath)/initial.txt", atomically: true, encoding: .utf8)
        try await git.run(.addAll)
        try await git.run(.commit(message: "Initial commit", allowEmpty: false))
        
        // Create local-only branch
        try await git.run(.checkout(branch: "local-feature", create: true))
        try "feature".write(toFile: "\(repoPath)/feature.txt", atomically: true, encoding: .utf8)
        try await git.run(.addAll)
        try await git.run(.commit(message: "Feature commit", allowEmpty: false))
        
        // Create uncommitted changes
        try "modified".write(toFile: "\(repoPath)/modified.txt", atomically: true, encoding: .utf8)
        
        // Test: Repository summary should include both indicators
        let summary = try await summarizeStatus(repoPath: repoPath, pushWIPChanges: false)
        
        XCTAssertTrue(summary.status.contains(.dirtyIndex), "Summary should indicate dirty index")
        XCTAssertTrue(summary.status.contains(.localOnlyBranches), "Summary should indicate local-only branches")
        XCTAssertTrue(summary.description.contains("M"), "Status description should include M indicator")
        XCTAssertTrue(summary.description.contains("L"), "Status description should include L indicator")
        XCTAssertEqual(summary.description, "ML", "Status should show ML for modifications and local-only branches")
    }
    
    func testMutualExclusivityOfPAndL() async throws {
        // Setup: Create repo with both types of branches to verify P and L logic
        let repoPath = "\(tempDirectory!)/mutual-exclusivity-test"
        try fileManager.createDirectory(atPath: repoPath, withIntermediateDirectories: true, attributes: nil)
        
        let git = Git(path: repoPath)
        try await git.run(.raw("init"))
        try await git.run(.raw("config user.name 'Test User'"))
        try await git.run(.raw("config user.email 'test@example.com'"))
        
        // Create initial commit on main
        try "initial".write(toFile: "\(repoPath)/initial.txt", atomically: true, encoding: .utf8)
        try await git.run(.addAll)
        try await git.run(.commit(message: "Initial commit", allowEmpty: false))
        
        // Create a local-only branch
        try await git.run(.checkout(branch: "local-feature", create: true))
        try "feature".write(toFile: "\(repoPath)/feature.txt", atomically: true, encoding: .utf8)
        try await git.run(.addAll)
        try await git.run(.commit(message: "Feature commit", allowEmpty: false))
        
        // Test: Get branch info - all branches should be local-only since no remotes exist
        let branchInfo = try await getBranchInfo(repoPath: repoPath)
        
        XCTAssertEqual(branchInfo.branchesWithUnpushedCommits.count, 0, "Should have no unpushed branches when no upstreams exist")
        XCTAssertGreaterThan(branchInfo.localOnlyBranches.count, 0, "Should have local-only branches")
        XCTAssertTrue(branchInfo.localOnlyBranches.contains { $0.name == "main" }, "main should be local-only")
        XCTAssertTrue(branchInfo.localOnlyBranches.contains { $0.name == "local-feature" }, "local-feature should be local-only")
        
        // A repository can only have P OR L, never both, since they represent different branch states
        let summary = try await summarizeStatus(repoPath: repoPath, pushWIPChanges: false)
        if summary.status.contains(.localOnlyBranches) {
            XCTAssertEqual(summary.repositoryBranchInfo.branchesWithUnpushedCommits.count, 0, "If repo has local-only branches, it should have no unpushed branches")
        }
        if !summary.repositoryBranchInfo.branchesWithUnpushedCommits.isEmpty {
            XCTAssertFalse(summary.status.contains(.localOnlyBranches), "If repo has unpushed branches, it should not have local-only flag")
        }
    }
    
    func testDetailedBranchReporting() async throws {
        // Setup: Create repo with multiple branches in different states
        let repoPath = "\(tempDirectory!)/detailed-branch-test"
        try fileManager.createDirectory(atPath: repoPath, withIntermediateDirectories: true, attributes: nil)
        
        let git = Git(path: repoPath)
        try await git.run(.raw("init"))
        try await git.run(.raw("config user.name 'Test User'"))
        try await git.run(.raw("config user.email 'test@example.com'"))
        
        // Create initial commit on main
        try "initial".write(toFile: "\(repoPath)/initial.txt", atomically: true, encoding: .utf8)
        try await git.run(.addAll)
        try await git.run(.commit(message: "Initial commit", allowEmpty: false))
        
        // Create multiple local-only branches
        try await git.run(.checkout(branch: "feature-1", create: true))
        try "feature1".write(toFile: "\(repoPath)/feature1.txt", atomically: true, encoding: .utf8)
        try await git.run(.addAll)
        try await git.run(.commit(message: "Feature 1 commit", allowEmpty: false))
        
        try await git.run(.checkout(branch: "feature-2", create: true))
        try "feature2".write(toFile: "\(repoPath)/feature2.txt", atomically: true, encoding: .utf8)
        try await git.run(.addAll)
        try await git.run(.commit(message: "Feature 2 commit", allowEmpty: false))
        
        // Switch back to main for testing
        try await git.run(.checkout(branch: "main"))
        
        // Test: Get detailed branch info
        let repositoryBranchInfo = try await getBranchInfo(repoPath: repoPath)
        
        XCTAssertEqual(repositoryBranchInfo.branches.count, 3, "Should find all 3 branches")
        
        // Verify all branches are detected as local-only (no remotes configured)
        let branchNames = Set(repositoryBranchInfo.branches.map { $0.name })
        XCTAssertTrue(branchNames.contains("main"), "Should find main branch")
        XCTAssertTrue(branchNames.contains("feature-1"), "Should find feature-1 branch")
        XCTAssertTrue(branchNames.contains("feature-2"), "Should find feature-2 branch")
        
        // Verify current branch is correctly identified
        let currentBranch = repositoryBranchInfo.branches.first { $0.isCurrentBranch }
        XCTAssertNotNil(currentBranch, "Should identify current branch")
        XCTAssertEqual(currentBranch?.name, "main", "main should be current branch")
        
        // All branches should be local-only since no remotes exist
        for branch in repositoryBranchInfo.branches {
            XCTAssertTrue(branch.status.isLocalOnly, "Branch \(branch.name) should be local-only")
        }
        
        XCTAssertTrue(repositoryBranchInfo.hasLocalOnlyBranches, "Repository should have local-only branches")
        XCTAssertFalse(repositoryBranchInfo.hasUnpushedCommits, "Repository should not have unpushed commits (no upstreams)")
        XCTAssertEqual(repositoryBranchInfo.localOnlyBranches.count, 3, "All 3 branches should be local-only")
        
        // Test: Repository summary should reflect branch status
        let summary = try await summarizeStatus(repoPath: repoPath, pushWIPChanges: false)
        XCTAssertTrue(summary.status.contains(.localOnlyBranches), "Summary should indicate local-only branches")
        XCTAssertEqual(summary.description, "L", "Status should show L for local-only branches")
        XCTAssertEqual(summary.localOnlyBranches.count, 3, "Should have 3 local-only branches")
    }
    
    func testUncommittedChangesDetection() async throws {
        // Setup: Create repo with uncommitted changes
        let repoPath = "\(tempDirectory!)/test-repo"
        try await createGitRepoWithChanges(at: repoPath, hasUncommittedChanges: true)
        
        // Test: Check the working index status
        let status = try await checkWorkingIndex(repoPath: repoPath, pushWIPChanges: false)
        
        XCTAssertTrue(status.contains(.dirtyIndex), "Repository with uncommitted changes should have dirty index status")
        XCTAssertFalse(status.contains(.clean), "Repository with uncommitted changes should not be clean")
    }
    
    func testCleanRepoDetection() async throws {
        // Setup: Create clean repo
        let repoPath = "\(tempDirectory!)/clean-repo"
        try await createGitRepoWithChanges(at: repoPath, hasUncommittedChanges: false)
        
        // Test: Check the working index status
        let status = try await checkWorkingIndex(repoPath: repoPath, pushWIPChanges: false)
        
        XCTAssertTrue(status.contains(.clean), "Clean repository should have clean status")
        XCTAssertFalse(status.contains(.dirtyIndex), "Clean repository should not have dirty index")
    }
    
    func testRepoSummarization() async throws {
        // Setup: Create repo with uncommitted changes (but no upstream to avoid git errors)
        let repoPath = "\(tempDirectory!)/summary-test-repo"
        try fileManager.createDirectory(atPath: repoPath, withIntermediateDirectories: true, attributes: nil)
        
        let git = Git(path: repoPath)
        try await git.run(.raw("init"))
        try await git.run(.raw("config user.name 'Test User'"))
        try await git.run(.raw("config user.email 'test@example.com'"))
        
        // Create initial commit
        let initialFilePath = "\(repoPath)/initial.txt"
        try "initial content".write(toFile: initialFilePath, atomically: true, encoding: .utf8)
        try await git.run(.addAll)
        try await git.run(.commit(message: "Initial commit", allowEmpty: false))
        
        // Create uncommitted changes
        let modifiedFilePath = "\(repoPath)/modified.txt"
        try "modified content".write(toFile: modifiedFilePath, atomically: true, encoding: .utf8)
        
        // Test: Create repository summary
        let summary = try await summarizeStatus(repoPath: repoPath, pushWIPChanges: false)
        
        XCTAssertEqual(summary.path, repoPath, "Summary should contain the correct repo path")
        XCTAssertTrue(summary.status.contains(.dirtyIndex), "Summary should indicate dirty index")
        XCTAssertTrue(summary.needsReport, "Repository with changes should need reporting")
    }
    
    // MARK: - Integration Tests
    
    func testCompleteStatusFlow() async throws {
        // This test simulates what the Status command would do:
        // 1. Get valid paths for a user
        // 2. Check each path for repositories
        // 3. Handle both regular and owner/repo structures
        // 4. Summarize status for each repo found
        
        // Setup: Create complete directory structure
        try await createTestDirectoryStructure()
        
        // Get paths like Status command would
        let allReposOptions = allReposOptions()
        
        let userPaths = try UserPaths(
            basePath: tempDirectory,
            username: "testuser",
            repoTypes: allReposOptions,
            createOnDisk: false
        )
        
        var foundRepos: [String] = []
        
        // Simulate Status command's checkRepos logic
        for path in userPaths.validPaths {
            guard fileManager.fileExists(atPath: path) else { continue }
            
            // Check if this needs owner-level handling (starred/forked)
            let needsOwnerLevel = path.contains("/starred") || path.contains("/forked")
            
            let contents = try fileManager.contentsOfDirectory(atPath: path)
            
            for item in contents {
                let itemPath = "\(path)/\(item)"
                
                if needsOwnerLevel {
                    // Check owner directories for actual repos
                    let ownerContents = try fileManager.contentsOfDirectory(atPath: itemPath)
                    for repo in ownerContents {
                        let repoPath = "\(itemPath)/\(repo)"
                        if fileManager.fileExists(atPath: "\(repoPath)/.git") {
                            foundRepos.append(repoPath)
                        }
                    }
                } else {
                    // Check for direct repos
                    if fileManager.fileExists(atPath: "\(itemPath)/.git") {
                        foundRepos.append(itemPath)
                    }
                }
            }
        }
        
        // Verify we found all expected repositories
        let expectedRepoCount = 9 // 3 regular + 3 starred + 3 forked
        XCTAssertEqual(foundRepos.count, expectedRepoCount, "Should find all \(expectedRepoCount) repositories")
        
        // Verify we found repos from different structures
        let starredRepos = foundRepos.filter { $0.contains("/starred/") }
        let forkedRepos = foundRepos.filter { $0.contains("/forked/") }
        let regularRepos = foundRepos.filter { !$0.contains("/starred/") && !$0.contains("/forked/") }
        
        XCTAssertEqual(starredRepos.count, 3, "Should find 3 starred repositories")
        XCTAssertEqual(forkedRepos.count, 3, "Should find 3 forked repositories") 
        XCTAssertEqual(regularRepos.count, 3, "Should find 3 regular repositories")
    }
}

private extension StatusCommandTests {
    /// Creates a RepoTypeOptions.Resolved with all repos enabled
    func allReposOptions() -> RepoTypeOptions.Resolved {
        return RepoTypeOptions.Resolved(
            noRepos: false, noForkedRepos: false, noStarredRepos: false, noPublicRepos: false, noPrivateRepos: false,
            onlyStarredRepos: false, onlyForkedRepos: false, onlyPublicRepos: false, onlyPrivateRepos: false,
            noWikis: false, noGists: false, noForkedGists: false, noStarredGists: false, noPublicGists: false, noPrivateGists: false,
            onlyStarredGists: false, onlyForkedGists: false, onlyPublicGists: false, onlyPrivateGists: false
        )
    }

    /// Creates a git repository with modifications to test status reporting
    func createGitRepoWithChanges(at path: String, hasUncommittedChanges: Bool = false, hasUnpushedCommits: Bool = false) async throws {
        try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)

        let git = Git(path: path)
        try await git.run(.raw("init"))
        try await git.run(.raw("config user.name 'Test User'"))
        try await git.run(.raw("config user.email 'test@example.com'"))

        // Create initial commit
        let initialFilePath = "\(path)/initial.txt"
        try "initial content".write(toFile: initialFilePath, atomically: true, encoding: .utf8)
        try await git.run(.addAll)
        try await git.run(.commit(message: "Initial commit", allowEmpty: false))

        if hasUnpushedCommits {
            // Create additional commits that haven't been pushed
            let unpushedFilePath = "\(path)/unpushed.txt"
            try "unpushed content".write(toFile: unpushedFilePath, atomically: true, encoding: .utf8)
            try await git.run(.addAll)
            try await git.run(.commit(message: "Unpushed commit", allowEmpty: false))
        }

        if hasUncommittedChanges {
            // Create uncommitted changes
            let modifiedFilePath = "\(path)/modified.txt"
            try "modified content".write(toFile: modifiedFilePath, atomically: true, encoding: .utf8)
        }
    }

    /// Creates a complete directory structure for testing
    func createTestDirectoryStructure() async throws {
        // Create regular repos (direct structure)
        try await createGitRepoWithChanges(at: "\(tempDirectory!)/user/testuser/repos/public/clean-repo")
        try await createGitRepoWithChanges(at: "\(tempDirectory!)/user/testuser/repos/public/dirty-repo", hasUncommittedChanges: true)
        try await createGitRepoWithChanges(at: "\(tempDirectory!)/user/testuser/repos/private/unpushed-repo", hasUnpushedCommits: true)

        // Create starred repos (owner/repo structure)
        try await createGitRepoWithChanges(at: "\(tempDirectory!)/user/testuser/repos/starred/owner1/starred-clean")
        try await createGitRepoWithChanges(at: "\(tempDirectory!)/user/testuser/repos/starred/owner1/starred-dirty", hasUncommittedChanges: true)
        try await createGitRepoWithChanges(at: "\(tempDirectory!)/user/testuser/repos/starred/owner2/starred-unpushed", hasUnpushedCommits: true)

        // Create forked repos (owner/repo structure)
        try await createGitRepoWithChanges(at: "\(tempDirectory!)/user/testuser/repos/forked/upstream1/forked-clean")
        try await createGitRepoWithChanges(at: "\(tempDirectory!)/user/testuser/repos/forked/upstream1/forked-dirty", hasUncommittedChanges: true)
        try await createGitRepoWithChanges(at: "\(tempDirectory!)/user/testuser/repos/forked/upstream2/forked-both", hasUncommittedChanges: true, hasUnpushedCommits: true)
    }
}

import Foundation
import ArgumentParser

public struct RepoTypeOptions: ParsableArguments {
    public init() {}
    
    // MARK: Repo exclusions
    
    @Flag(help: "Do not clone the authenticated user's or organization's public repos.")
    var noPublicRepos: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's or organization's private repos.")
    var noPrivateRepos: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's starred repos (does not apply to organizations as they cannot star repos).")
    var noStarredRepos: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's or organization's forked repos.")
    var noForkedRepos: Bool = false
    
    @Flag(help: "Do not clone wikis associated with any repos owned by user or org.")
    var noWikis: Bool = false
    
    @Flag(help: "Do not clone any repos (includes wikis).")
    var noRepos: Bool = false
    
    // MARK: Repo selections
    
    @Flag(help: "Only clone the authenticated user's or organization's public repos. Has no effect on gist selection.")
    var onlyPublicRepos: Bool = false
    
    @Flag(help: "Only clone the authenticated user's or organization's private repos. Has no effect on gist selection.")
    var onlyPrivateRepos: Bool = false
    
    @Flag(help: "Only clone the authenticated user's starred repos (does not apply to organizations as they cannot star repos). Has no effect on gist selection.")
    var onlyStarredRepos: Bool = false
    
    @Flag(help: "Only clone the authenticated user's or organization's forked repos. Has no effect on gist selection.")
    var onlyForkedRepos: Bool = false
    
    // MARK: Gist exclusions
    
    @Flag(help: "Do not clone the authenticated user's or organization's public gists.")
    var noPublicGists: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's or organization's private gists.")
    var noPrivateGists: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's starred gists (does not apply to organizations).")
    var noStarredGists: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's forked gists (does not apply to organizations).")
    var noForkedGists: Bool = false
    
    @Flag(help: "Do not clone any gists, no repos/wikis.")
    var noGists: Bool = false
    
    // MARK: Gist selections
    
    @Flag(help: "Only clone the authenticated user's or organization's public gists. Has no effect on repo selection.")
    var onlyPublicGists: Bool = false
    
    @Flag(help: "Only clone the authenticated user's or organization's private gists. Has no effect on repo selection.")
    var onlyPrivateGists: Bool = false
    
    @Flag(help: "Only clone the authenticated user's starred gists (does not apply to organizations as they cannot star gists). Has no effect on repo selection.")
    var onlyStarredGists: Bool = false
    
    @Flag(help: "Only clone the authenticated user's forked gists (does not apply to organizations as they cannot fork gists). Has no effect on repo selection.")
    var onlyForkedGists: Bool = false
    
    // MARK: Computed accessors
    
    public struct Resolved {
        public let noRepos: Bool
        public let noForkedRepos: Bool
        public let noPrivateRepos: Bool
        public let noPublicRepos: Bool
        public let noStarredRepos: Bool
        
        public let noWikis: Bool
        
        public let noGists: Bool
        public let noForkedGists: Bool
        public let noPrivateGists: Bool
        public let noPublicGists: Bool
        public let noStarredGists: Bool
        
        public let noNonstarredRepos: Bool
        public let noNonstarredGists: Bool
        
        public init(
            noRepos: Bool,
            
            noForkedRepos: Bool,
            noStarredRepos: Bool,
            noPublicRepos: Bool,
            noPrivateRepos: Bool,
            
            onlyStarredRepos: Bool,
            onlyForkedRepos: Bool,
            onlyPublicRepos: Bool,
            onlyPrivateRepos: Bool,
            
            noWikis: Bool,
            
            noGists: Bool,
            
            noForkedGists: Bool,
            noStarredGists: Bool,
            noPublicGists: Bool,
            noPrivateGists: Bool,
            
            onlyStarredGists: Bool,
            onlyForkedGists: Bool,
            onlyPublicGists: Bool,
            onlyPrivateGists: Bool
        ) {
            self.noRepos = noRepos
            self.noForkedRepos = noRepos || noForkedRepos || onlyStarredRepos || onlyPublicRepos || onlyPrivateRepos
            self.noPublicRepos = noRepos || noPublicRepos || onlyStarredRepos || onlyForkedRepos || onlyPrivateRepos
            self.noPrivateRepos = noRepos || noPrivateRepos || onlyStarredRepos || onlyPublicRepos || onlyForkedRepos
            self.noStarredRepos = noRepos || noStarredRepos || onlyPublicRepos || onlyPrivateRepos || onlyForkedRepos
            self.noWikis = noRepos || noWikis
            
            self.noGists = noGists
            self.noForkedGists = noGists || noForkedGists || onlyPrivateGists || onlyPublicGists || onlyStarredGists
            self.noPrivateGists = noGists || noPrivateGists || onlyPublicGists || onlyStarredGists || onlyForkedGists
            self.noPublicGists = noGists || noPublicGists || onlyPrivateGists || onlyForkedGists || onlyStarredGists
            self.noStarredGists = noGists || noStarredGists || onlyPublicGists || onlyPrivateGists || onlyForkedGists
            
            self.noNonstarredRepos = !noRepos && noForkedRepos && noPublicRepos && noPrivateRepos
            self.noNonstarredGists = noForkedGists && noPublicGists && noPrivateGists
        }
    }
    
    public var resolved: Resolved {
        Resolved(noRepos: noRepos, noForkedRepos: noForkedRepos, noStarredRepos: noStarredRepos, noPublicRepos: noPublicRepos, noPrivateRepos: noPrivateRepos, onlyStarredRepos: onlyStarredRepos, onlyForkedRepos: onlyForkedRepos, onlyPublicRepos: onlyPublicRepos, onlyPrivateRepos: onlyPrivateRepos, noWikis: noWikis, noGists: noGists, noForkedGists: noForkedGists, noStarredGists: noStarredGists, noPublicGists: noPublicGists, noPrivateGists: noPrivateGists, onlyStarredGists: onlyStarredGists, onlyForkedGists: onlyForkedGists, onlyPublicGists: onlyPublicGists, onlyPrivateGists: onlyPrivateGists)
    }
}

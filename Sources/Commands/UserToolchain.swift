/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import POSIX

import Basic
import PackageLoading
import protocol Build.Toolchain
import Utility

#if os(macOS)
    private let whichClangArgs = ["xcrun", "--find", "clang"]
#else
    private let whichClangArgs = ["which", "clang"]
#endif

public struct UserToolchain: Toolchain, ManifestResourceProvider {
    /// Path of the `swiftc` compiler.
    public let swiftCompiler: AbsolutePath
    
    /// Path of the `clang` compiler.
    public let clangCompiler: AbsolutePath

    /// Path to llbuild.
    let llbuild: AbsolutePath

    /// Path to SwiftPM library directory containing runtime libraries.
    public let libDir: AbsolutePath
    
    /// Path of the default SDK (a.k.a. "sysroot"), if any.
    public let defaultSDK: AbsolutePath?

  #if os(macOS)
    /// Path to the sdk platform framework path.
    public let sdkPlatformFrameworksPath: AbsolutePath

    public var clangPlatformArgs: [String] {
        return ["-arch", "x86_64", "-mmacosx-version-min=10.10", "-isysroot", defaultSDK!.asString, "-F", sdkPlatformFrameworksPath.asString]
    }
    public var swiftPlatformArgs: [String] {
        return ["-target", "x86_64-apple-macosx10.10", "-sdk", defaultSDK!.asString, "-F", sdkPlatformFrameworksPath.asString]
    }
  #else
    public let clangPlatformArgs: [String] = ["-fPIC"]
    public let swiftPlatformArgs: [String] = []
  #endif

    public init(_ binDir: AbsolutePath) throws {
        // Get the search paths from PATH.
        let envSearchPaths = Utility.getEnvSearchPaths(
            pathString: getenv("PATH"), currentWorkingDirectory: currentWorkingDirectory)

        func lookup(env: String) -> AbsolutePath? {
            return Utility.lookupExecutablePath(
                inEnvValue: getenv(env),
                searchPaths: envSearchPaths)
        }

        libDir = binDir.parentDirectory.appending(components: "lib", "swift", "pm")

        // First look in env and then in bin dir.
        swiftCompiler = lookup(env: "SWIFT_EXEC") ?? binDir.appending(component: "swiftc")
        
        // Check that it's valid in the file system.
        // FIXME: We should also check that it resolves to an executable file
        //        (it could be a symlink to such as file).
        guard localFileSystem.exists(swiftCompiler) else {
            throw Error.invalidToolchain(problem: "could not find `swiftc` at expected path \(swiftCompiler.asString)")
        }

        // Look for llbuild in bin dir.
        llbuild = binDir.appending(component: "swift-build-tool")
        guard localFileSystem.exists(llbuild) else {
            throw Error.invalidToolchain(problem: "could not find `llbuild` at expected path \(llbuild.asString)")
        }

        // Find the Clang compiler, looking first in the environment.
        if let value = lookup(env: "CC") {
            clangCompiler = value
        } else {
            // No value in env, so search for `clang`.
            let foundPath = try Process.checkNonZeroExit(arguments: whichClangArgs).chomp()
            guard !foundPath.isEmpty else {
                throw Error.invalidToolchain(problem: "could not find `clang`")
            }
            clangCompiler = AbsolutePath(foundPath)
        }
        
        // Check that it's valid in the file system.
        // FIXME: We should also check that it resolves to an executable file
        //        (it could be a symlink to such as file).
        guard localFileSystem.exists(clangCompiler) else {
            throw Error.invalidToolchain(problem: "could not find `clang` at expected path \(clangCompiler.asString)")
        }
        
        // Find the default SDK (on macOS only).
      #if os(macOS)
        let sdk: AbsolutePath

        if let value = Utility.lookupExecutablePath(inEnvValue: getenv("SYSROOT")) {
            sdk = value
        } else {
            // No value in env, so search for it.
            let foundPath = try Process.checkNonZeroExit(
                args: "xcrun", "--sdk", "macosx", "--show-sdk-path").chomp()
            guard !foundPath.isEmpty else {
                throw Error.invalidToolchain(problem: "could not find default SDK")
            }
            sdk = AbsolutePath(foundPath)
        }
        
        // FIXME: We should probably also check that it is a directory, etc.
        guard localFileSystem.exists(sdk) else {
            throw Error.invalidToolchain(problem: "could not find default SDK at expected path \(sdk.asString)")
        }
        defaultSDK = sdk

        let platformPath = try Process.checkNonZeroExit(
            args: "xcrun", "--sdk", "macosx", "--show-sdk-platform-path").chomp()
        guard !platformPath.isEmpty else {
                throw Error.invalidToolchain(problem: "could not get sdk platform path")
        }
        sdkPlatformFrameworksPath = AbsolutePath(platformPath).appending(components: "Developer", "Library", "Frameworks")
      #else
        defaultSDK = nil
      #endif
    }

}

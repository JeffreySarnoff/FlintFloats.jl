# Install the bundled native artifact without inventing a remote release URL.
# Build scripts run separately from the runtime package and may use Pkg.
using Pkg.Artifacts
using Pkg.PlatformEngines: unpack
using SHA
using TOML
using Base.BinaryPlatforms

function install_bundled_artifact()
    root = dirname(@__DIR__)
    artifacts_toml = joinpath(root, "Artifacts.toml")
    platform = HostPlatform()
    expected = artifact_hash("FLINT", artifacts_toml; platform)
    isnothing(expected) && error("No built FLINT artifact for $(triplet(platform)). See README.md.")
    artifact_exists(expected) && return artifact_path(expected)

    bundles = TOML.parsefile(joinpath(root, "bundles", "Checksums.toml"))
    entry = get(bundles, bytes2hex(expected.bytes), nothing)
    isnothing(entry) && error("No bundled archive for FLINT artifact $expected")
    archive = joinpath(root, "bundles", entry["file"])
    digest = open(sha256, archive)
    bytes2hex(digest) == entry["sha256"] || error("FLINT archive checksum mismatch: $archive")
    actual = create_artifact() do directory
        unpack(archive, directory)
    end
    actual == expected || error("FLINT artifact tree mismatch: expected $expected, got $actual")
    return artifact_path(actual)
end

println("Installed FLINT artifact: ", install_bundled_artifact())

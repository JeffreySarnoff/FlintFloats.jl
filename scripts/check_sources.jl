# Host-independent provenance checks; deliberately does not import or execute native FLINT code.
using TOML, SHA
root=dirname(@__DIR__)
wrapper=joinpath(root,"FlintFloat.jl","FLINT_jll")
source=TOML.parsefile(joinpath(wrapper,"Source.toml"))
inventory=TOML.parsefile(joinpath(root,"gen","inventory.toml"))
@assert inventory["meta"]["source_revision"]==source["revision"]
@assert inventory["meta"]["flint_version"]==source["upstream_version"]
@assert inventory["meta"]["abi"]==source["soname_major"]
project=TOML.parsefile(joinpath(wrapper,"Project.toml"))
@assert project["version"]==source["wrapper_version"] "Wrapper version/provenance mismatch"
if get(source,"active_build","native")=="portable"
    artifact=TOML.parsefile(joinpath(wrapper,"Artifacts.toml"))["FLINT"][1]
    @assert artifact["git-tree-sha1"]==source["portable_build"]["artifact_tree"]
    checksums=TOML.parsefile(joinpath(wrapper,"bundles","Checksums.toml"))
    @assert checksums[artifact["git-tree-sha1"]]["sha256"]==source["portable_build"]["archive_sha256"]
end
archive=joinpath(wrapper,source["source_archive"])
@assert bytes2hex(open(sha256,archive))==source["source_sha256"] "Pinned source archive checksum mismatch"
for (_,entry) in TOML.parsefile(joinpath(wrapper,"bundles","Checksums.toml"))
    @assert bytes2hex(open(sha256,joinpath(wrapper,"bundles",entry["file"])))==entry["sha256"] "Bundled artifact checksum mismatch"
end
println("Pinned source, inventory identity, and bundled archives verified without loading FLINT")

using FlintFloats, Test

struct WorkspaceCallbackInput{T,F} <: AbstractVector{T}
    data::Vector{T}
    onread::F
end
Base.size(x::WorkspaceCallbackInput) = size(x.data)
Base.dataids(x::WorkspaceCallbackInput) = Base.dataids(x.data)
Base.getindex(x::WorkspaceCallbackInput, i::Int) = (x.onread(i); x.data[i])

function workspace_allocations(f!, z, x, y, work)
    f!(z, x, y, work)
    f!(z, x, y, work)
    return @allocated f!(z, x, y, work)
end

@testset "reusable nfloat workspace" begin
    @test_throws ArgumentError NFloatWorkspace(NFloat{0})
    @test_throws ArgumentError NFloatWorkspace(NFloat{67})
    @test_throws ArgumentError NFloatWorkspace(NFloat{2}, -1)
    for L in (1, 2, 4, 16, 66)
        T = NFloat{L}
        work = @inferred NFloatWorkspace(T, 65)
        original_buffer = work._buffer
        for (f!, op) in ((FF.add!, +), (FF.mul!, *))
            for len in (0, 1, 17, 65, 3, 0, 70, 4)
                x, y = T.(1:len), fill(T(2), len)
                z = Vector{T}(undef, len)
                @test @inferred(f!(z, x, y, work)) === z
                @test isequal(z, op.(x, y))
                @test work._buffer === original_buffer
                @test length(work._buffer) >= len
                a = copy(x)
                f!(a, a, y, work)
                @test isequal(a, z)
                b = copy(y)
                f!(b, x, b, work)
                @test isequal(b, z)
            end
            x, y, z = fill(T(1.25), 17), fill(T(2), 17), Vector{T}(undef, 17)
            @test workspace_allocations(f!, z, x, y, work) == 0
            # Copy only the active prefix, even when using a larger reserved workspace.
            parent_z = fill(T(-1), 25)
            zv = view(parent_z, 3:19)
            f!(zv, x, y, work)
            @test isequal(zv, op.(x, y))
            @test all(isequal(T(-1)), parent_z[[1, 2, 20, 25]])
            for ix in (2:2:24, 24:-2:2)
                xp, yp, zp = T.(1:26), fill(T(2), 26), fill(T(-1), 26)
                xv, yv, zv = view(xp, ix), view(yp, ix), view(zp, ix)
                f!(zv, xv, yv, work)
                @test isequal(zv, op.(xv, yv))
                f!(xv, xv, yv, work)
                @test isequal(xv, zv)
            end
            # Type/shape and overlap failures must not grow or mutate scratch or destinations.
            snapshot = copy(work._buffer)
            @test_throws ArgumentError f!(z, x, y, NFloatWorkspace(NFloat{L == 1 ? 2 : 1}, 17))
            @test_throws DimensionMismatch f!(z, T[], y, work)
            @test isequal(work._buffer, snapshot)
            for (dest, a, b) in ((view(work._buffer, 1:17), x, y),
                                 (z, view(work._buffer, 1:17), y),
                                 (z, x, view(work._buffer, 1:17)))
                before = copy(dest)
                @test_throws ArgumentError f!(dest, a, b, work)
                @test isequal(dest, before)
                @test isequal(work._buffer, snapshot)
            end
            before = copy(x)
            @test_throws ArgumentError f!(view(x, 2:17), view(x, 1:16), view(y, 1:16), work)
            @test isequal(x, before)

            # Arithmetic failure releases the workspace and preserves independent/aliased destinations.
            emax = parse(Int, read_layout()["NFLOAT_MAX_EXP"])
            bad = T(emax, UInt(0), ntuple(_ -> typemax(UInt), L))
            a, b = [one(T), bad, one(T)], [T(2), bad, T(2)]
            for dest in (fill(T(-7), 3), a, b)
                before = copy(dest)
                @test_throws ErrorException f!(dest, a, b, work)
                @test isequal(dest, before)
                # Reuse after a partly written failed result; no stale lane may escape.
                good = fill(T(-7), 3)
                f!(good, fill(one(T), 3), fill(T(2), 3), work)
                @test all(isequal(op(one(T), T(2))), good)
            end
            # Input-read exceptions on the scalar path also release the workspace without committing.
            throwing = WorkspaceCallbackInput(copy(x), i -> (i == 2 && error("input failed")))
            before = copy(z)
            @test_throws ErrorException f!(z, throwing, y, work)
            @test isequal(z, before)
            f!(z, x, y, work)
            @test isequal(z, op.(x, y))
        end
        before = copy(work._buffer)
        @test sizehint!(work, 100) === work
        @test isequal(work._buffer[1:length(before)], before)
        @test all(iszero, work._buffer[length(before)+1:100])
        @test sizehint!(work, 0) === work
        @test length(work._buffer) == 100
        @test_throws ArgumentError sizehint!(work, -1)
    end

    @testset "exclusive access and reentrancy" begin
        T = NFloat{2}
        work = NFloatWorkspace(T, 4)
        x, y, z = fill(T(1), 4), fill(T(2), 4), fill(T(-1), 4)
        reentrant = WorkspaceCallbackInput(x, i -> begin
            if i == 1
                @test_throws ArgumentError FF.add!(z, x, y, work)
                @test_throws ArgumentError sizehint!(work, 100)
            end
        end)
        FF.mul!(z, reentrant, y, work)
        @test all(isequal(T(2)), z)

        entered, release = Channel{Nothing}(1), Channel{Nothing}(1)
        blocked = WorkspaceCallbackInput(x, i -> begin
            if i == 1
                put!(entered, nothing)
                take!(release)
            end
        end)
        task = Threads.@spawn FF.add!(z, blocked, y, work)
        take!(entered)
        try
            before = copy(z)
            @test_throws ArgumentError FF.mul!(z, x, y, work)
            @test_throws ArgumentError sizehint!(work, 100)
            @test isequal(z, before)
        finally
            put!(release, nothing)
        end
        @test fetch(task) === z
        @test all(isequal(T(3)), z)
        FF.mul!(z, x, y, work)
        @test all(isequal(T(2)), z)
        tasks = [Threads.@spawn begin
            own = NFloatWorkspace(T, 4)
            dest = similar(x)
            FF.add!(dest, x, y, own)
            all(isequal(T(3)), dest)
        end for _ in 1:8]
        @test all(fetch, tasks)
    end
end

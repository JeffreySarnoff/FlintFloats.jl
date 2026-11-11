using FlintFloats, Test

function _eachborrow_scale!(v, scale)
    for r in eachborrow(v)
        FlintFloats.mul!(r,r,scale)
    end
    v
end
function _eachborrow_allocated(v, scale)
    # Scale=one in allocation checks so repeated warmup leaves the numerical workload unchanged.
    _eachborrow_scale!(v,scale)
    _eachborrow_scale!(v,scale)
    @allocated _eachborrow_scale!(v,scale)
end

@testset "packed value reads and explicit borrowed iteration" begin
    for family in (ArbBall,AcbBall), P in (64,256,2048)
        T=family{P}
        # Copied reads/iteration, convenient write-back, and explicit references have distinct effects.
        v=PackedBallVector(T,[1,2,3,4,5])
        x=v[1]
        FlintFloats.add!(x,x,T(10))
        @test v[1] == T(1)
        FlintFloats.add!(v[1],v[1],T(10))
        @test v[1] == T(1)
        v[1]=x
        @test v[1] == T(11)
        v[1]+=T(1)
        @test v[1] == T(12)
        for x in v
            FlintFloats.add!(x,x,T(100))
        end
        @test v[1] == T(12) && v[2] == T(2)
        mapped=view(v,5:-2:1)
        x=mapped[1]
        FlintFloats.add!(x,x,T(10))
        @test v[5] == T(5)
        mapped[1]=x
        @test v[5] == T(15)
        r=borrow(v,2)
        x=r[]
        FlintFloats.add!(x,x,T(20))
        @test v[2] == T(2)
        r[]=x
        @test v[2] == T(22)

        for indices in (nothing,1:5,2:2:5,5:-2:1,[5,2,5,1],Int[],3:2)
            parentvec=PackedBallVector(T,T.(1:5))
            span=indices === nothing ? parentvec : view(parentvec,indices)
            it=@inferred eachborrow(span)
            @test length(it) == length(span)
            @test eltype(typeof(it)) === BorrowedBall{T}
            @test eltype(span) === T
            @test Base.IteratorSize(typeof(it)) isa Base.HasLength
            @test Base.IteratorEltype(typeof(it)) isa Base.HasEltype
            @test !(it isa AbstractVector)
            refs=collect(it)
            @test eltype(refs) === BorrowedBall{T}
            @test length(refs) == length(span)
            @test all(i -> isequal(refs[i][],span[i]),eachindex(refs))
            if isempty(span)
                @test iterate(it) === nothing
            else
                firststep=@inferred Union{Nothing} iterate(it)
                @test firststep[1] isa BorrowedBall{T} && firststep[2] == 2
                @test (@inferred first(it)) isa BorrowedBall{T}
                # Iterate past saved references; none may change which slot it denotes.
                lastref=last(refs)
                firstindex_parent=refs[1].index
                firstref=refs[1]
                @test collect(it)[1].index == firstindex_parent
                firstref[]=T(99)
                @test parentvec[firstindex_parent] == T(99)
                @test lastref.index == refs[end].index
                if firstref.index != lastref.index
                    @test lastref[] != T(99)
                end
                @test _eachborrow_allocated(span,one(T)) == 0
            end
        end

        # Gather duplicates reference the same slot independently; every occurrence is visited.
        v=PackedBallVector(T,[1,2,3])
        refs=collect(eachborrow(view(v,[3,1,3])))
        @test refs[1].index == 3 && refs[2].index == 1 && refs[3].index == 3
        refs[1][]=T(9)
        @test refs[3][] == T(9) && refs[2][] == T(1)
        _eachborrow_scale!(view(v,[3,1,3]),T(2))
        @test v[1] == T(2) && v[3] == T(36)

        # Iterator alone retains the owner, including native heap-backed mantissas.
        function retained_iterator(T)
            owner=PackedBallVector(T,[T(1)/T(7),T(2)/T(9)])
            eachborrow(view(owner,2:-1:1)),WeakRef(owner)
        end
        it,weak=retained_iterator(T)
        GC.gc(true)
        @test weak.value !== nothing
        firststep=iterate(it)
        GC.gc(true)
        @test isequal(firststep[1][],T(2)/T(9))
        secondstep=iterate(it,firststep[2])
        @test isequal(secondstep[1][],T(1)/T(7))
        @test iterate(it,secondstep[2]) === nothing
        saved=collect(it)
        it=nothing
        GC.gc(true)
        @test all(r -> r.parent === weak.value,saved)
        saved[1][]=T(8)
        @test saved[2][] != T(8)
        # A copied scalar is independent even after explicit parent finalization.
        snapshot=saved[1][]
        finalize(saved[1].parent)
        @test snapshot == T(8)
        @test_throws ArgumentError saved[1][]

        for n in (0,3)
            owner=PackedBallVector(T,n)
            it=eachborrow(owner)
            empty_view=view(owner,1:0)
            empty_it=eachborrow(empty_view)
            step=n == 0 ? nothing : iterate(it)
            finalize(owner)
            @test_throws ArgumentError eachborrow(owner)
            @test_throws ArgumentError eachborrow(empty_view)
            @test_throws ArgumentError iterate(it)
            @test_throws ArgumentError iterate(empty_it)
            n == 0 || @test_throws ArgumentError iterate(it,step[2])
        end
    end

    @testset "independent concurrent slots" begin
        T=AcbBall{256}
        owner=PackedBallVector(T,fill(T(3),8*17))
        scale=T(2)
        tasks=[Threads.@spawn begin
            span=view(owner,(k-1)*17+1:k*17)
            GC.gc()
            _eachborrow_scale!(span,scale)
        end for k in 1:8]
        fetch.(tasks)
        @test all(x -> x == T(6),owner)
    end
end

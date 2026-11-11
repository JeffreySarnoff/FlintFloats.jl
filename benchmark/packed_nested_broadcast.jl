using FlintFloats, BenchmarkTools, FLINT_jll
bc(f,args...)=Base.Broadcast.broadcasted(f,args...)
function generic_tree!(z,tree)
    tree=Base.Broadcast.instantiate(Base.Broadcast.Broadcasted(tree.style,tree.f,tree.args,axes(z)))
    invoke(Base.copyto!,Tuple{AbstractArray,Base.Broadcast.Broadcasted{Nothing}},z,
           convert(Base.Broadcast.Broadcasted{Nothing},tree))
end
optimized_tree!(z,tree)=Base.Broadcast.materialize!(z,tree)
function make_tree(x,y,nodes)
    nodes==2 && return bc(+,bc(*,x,y),x)
    tree=x
    for _ in 1:nodes
        tree=bc(+,tree,y)
    end
    tree
end
println("Bounded nested packed broadcast; minimum warmed times, 100 samples, 0.05 s per case")
println("Julia=",VERSION," CPU=",Sys.cpu_info()[1].model," threads=",Threads.nthreads()," FLINT_jll=",pkgversion(FLINT_jll))
println("lib=",FLINT_jll.libflint_path," source=82c40b299084b92299c2d8dac464e39d6743fce4 ABI=25")
println("Loaded x86_64 Linux artifact; no global thread changes. Julia bytes exclude native allocations.")
println("Independent 1/7 and 2/9 inputs; output reused. Trees preserve scalar precision and association.")
println("family P n nodes generic_ns generic_allocs generic_bytes optimized_ns optimized_allocs optimized_bytes")
for family in (ArbBall,AcbBall), P in (128,512), n in (1,32,512), nodes in (2,8)
    T=family{P}; x=PackedBallVector(T,fill(T(1)/T(7),n)); y=PackedBallVector(T,fill(T(2)/T(9),n)); z=similar(x)
    tree=make_tree(x,y,nodes)
    bg=@benchmark generic_tree!($z,$tree) samples=100 seconds=0.05
    bo=@benchmark optimized_tree!($z,$tree) samples=100 seconds=0.05
    println(family," ",P," ",n," ",nodes," ",round(minimum(bg).time;digits=1)," ",bg.allocs," ",bg.memory," ",
            round(minimum(bo).time;digits=1)," ",bo.allocs," ",bo.memory)
end
println("First timed materialization at fresh precision; inputs prepared, elapsed includes compilation:")
for P in (997,998)
    T=ArbBall{P}; x=PackedBallVector(T,fill(T(1)/T(7),32)); y=copy(x); z=similar(x)
    tree=make_tree(x,y,8)
    elapsed=@elapsed optimized_tree!(z,tree)
    println("P=",P," eight-node first_ms=",round(1000elapsed;digits=2))
end

using FlintFloats, LinearAlgebra, BenchmarkTools, FLINT_jll
const FF=FlintFloats
base_dot(x,y)=invoke(dot,Tuple{AbstractArray,AbstractArray},x,y)
borrowed_dot(x::AbstractVector{T},y) where {T}=FF._packed_dot_borrowed(x,y,T)
parts_dot(x::AbstractVector{T},y,sx,sy) where {T}=FF._packed_dot_parts(x,y,T,sx,sy)
copy_dot(x::AbstractVector{T},y,sy) where {T}=FF._packed_dot_conjugated_copy(x,y,T,sy)
rad(x::ArbBall)=Float64(radius(x))
rad(x::AcbBall)=max(Float64(radius(real(x))),Float64(radius(imag(x))))
println("Packed conjugating dot; minimum warmed times, 100 samples, 0.05 s per case")
println("Julia=",VERSION," CPU=",Sys.cpu_info()[1].model," threads=",Threads.nthreads()," FLINT_jll=",pkgversion(FLINT_jll))
println("lib=",FLINT_jll.libflint_path," source=82c40b299084b92299c2d8dac464e39d6743fce4 ABI=25")
println("Loaded x86_64 Linux artifact; no global thread changes; Julia counts exclude native memory.")
println("Generic/public are complete checked calls. Private candidates exclude public descriptor/finite validation;")
println("conjugated-copy timing includes allocation, conjugation, native dot, and explicit cleanup.")
println("Inputs: real 1/7 and 2/9; complex (1/7,-2/9) and (3/5,4/11), uncertain at working precision.")
println("family P n span generic_ns public_ns borrowed_ns parts_ns conjugated_copy_ns public_allocs public_bytes generic_radius public_radius parts_radius copy_radius")
for family in (ArbBall,AcbBall),P in (128,512),n in (1,4,32,512),kind in (:full,:reversed,:gather)
    T=family{P}; R=ArbBall{P}
    a=family===ArbBall ? T(1)/T(7) : T(R(1)/R(7),R(-2)/R(9))
    b=family===ArbBall ? T(2)/T(9) : T(R(3)/R(5),R(4)/R(11))
    xo,yo=PackedBallVector(T,fill(a,n)),PackedBallVector(T,fill(b,n))
    inds=kind===:gather ? collect(n:-1:1) : n:-1:1
    x,y=kind===:full ? (xo,yo) : (view(xo,inds),view(yo,inds))
    sx,sy=FF._packed_dot_span(x),FF._packed_dot_span(y)
    bg=@benchmark base_dot($x,$y) samples=100 seconds=0.05
    bp=@benchmark dot($x,$y) samples=100 seconds=0.05
    bb=@benchmark borrowed_dot($x,$y) samples=100 seconds=0.05
    parts,copytime,partrad,copyrad="-","-","-","-"
    if family===AcbBall && sx!==nothing && sy!==nothing
        bn=@benchmark parts_dot($x,$y,$sx,$sy) samples=100 seconds=0.05
        bc=@benchmark copy_dot($x,$y,$sy) samples=100 seconds=0.05
        parts=string(round(minimum(bn).time;digits=1)); copytime=string(round(minimum(bc).time;digits=1))
        partrad=string(rad(FF._packed_dot_parts(x,y,T,sx,sy))); copyrad=string(rad(FF._packed_dot_conjugated_copy(x,y,T,sy)))
    end
    println(family," ",P," ",n," ",kind," ",round(minimum(bg).time;digits=1)," ",round(minimum(bp).time;digits=1)," ",
            round(minimum(bb).time;digits=1)," ",parts," ",copytime," ",bp.allocs," ",bp.memory," ",
            rad(base_dot(x,y))," ",rad(dot(x,y))," ",partrad," ",copyrad)
end

println("Cross-component cancellation: exact target 1+0im; compare enclosure radii, not scalar representation equality")
for P in (128,512)
    T=AcbBall{P}; R=ArbBall{P}; m=R((big(1)<<P)-1)
    x=PackedBallVector(T,[T(m,m),T(m,-m),T(1),T(0)])
    y=PackedBallVector(T,[T(m,-m),T(m,m),T(1),T(0)])
    sy=FF._packed_dot_span(y)
    println("P=",P," generic_radius=",rad(base_dot(x,y))," public_radius=",rad(dot(x,y)),
            " copy_radius=",rad(copy_dot(x,y,sy)))
end

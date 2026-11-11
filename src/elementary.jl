# Selected elementary functions. Each family retains its own rounding/domain contract; no fallback
# through machine floating point or hidden precision increase. See gen/inventory.toml for audits.
for (T,prefix) in ((ArbBall,:arb),(AcbBall,:acb)), name in (:exp,:log,:sin,:cos,:atan)
    c=Symbol(prefix,:_,name)
    bang=Symbol(name,:!)
    @eval begin
        @doc "Set `z` to the rigorous `$($name)(x)` enclosure at destination precision; allows `z === x`. Uses pinned FLINT domain/branch conventions." function $bang(z::$T{P},x::$T{P}) where {P}
            LibFlint.$c(z,x,P)
            z
        end
        @doc "Rigorous `$($name)` enclosure at element precision. Real-domain failures yield indeterminate balls; complex values use FLINT's principal branches. See `docs/elementary.md`." Base.$name(x::$T{P}) where {P} = $bang($T{P}(),x)
    end
end

# Strict point modes are passed explicitly, never through process-global rounding state.
for (T,prefix) in ((ArbFloat,:arf),(AcbFloat,:acf)), name in (:exp,:log,:sin,:cos,:atan)
    c=Symbol(prefix,:_,name)
    bang=Symbol(name,:!)
    inexact=Symbol(name,:_inexact!)
    @eval begin
        function $inexact(z::$T{P},x::$T{P},r::RoundingMode=RoundNearest) where {P}
            mode=_rnd(r) # Reject unsupported modes before mutation.
            if $(T===ArbFloat && name===:log) && signbit(x)
                throw(DomainError(x,"log of a negative real point; select a complex type explicitly"))
            end
            flag=LibFlint.$c(z,x,P,mode)
            z,flag!=0
        end
        @doc "Compute `$($name)(x)` with strict explicit rounding into initialized storage. Allows exact aliasing; returns the destination. See `docs/elementary.md`." $bang(z::$T{P},x::$T{P},r::RoundingMode=RoundNearest) where {P} = first($inexact(z,x,r))
        @doc "Compute `$($name)(x)` correctly rounded in the requested strict mode (each part for complex points). The default is RoundNearest. See `docs/elementary.md` for domain and range limits." Base.$name(x::$T{P},r::RoundingMode=RoundNearest) where {P} = $bang($T{P}(),x,r)
    end
end

# Inline values return by value. Ref buffers are read only after checked status success.
for N in 1:4, name in (:exp,:log,:sin,:cos,:atan)
    c=Symbol(:d,N,:_,name)
    cb=Symbol(:d,N,:b_,name)
    @eval begin
        function Base.$name(x::DFloat{$N})
            $(name===:log) && signbit(x) && throw(DomainError(x,"log of a negative DFloat"))
            result=Ref{DFloat{$N}}()
            LibFlint.$c(result,Ref(x))
            result[]
        end
        function Base.$name(x::DFloatBall{$N})
            result=Ref{DFloatBall{$N}}()
            if $(name===:log)
                status=LibFlint.$cb(result,Ref(x))
                status & GR_DOMAIN != 0 && throw(DomainError(x,"log of an entirely nonpositive DFloatBall"))
                status & GR_UNABLE != 0 && return _indeterminate(DFloatBall{$N})
                status==GR_SUCCESS || _status_error(status,$(QuoteNode(name)),DFloatBall{$N})
            else
                LibFlint.$cb(result,Ref(x))
            end
            result[]
        end
    end
end
for name in (:exp,:log,:sin,:cos,:atan)
    c=Symbol(:nfloat_,name)
    @eval function Base.$name(x::NFloat{L}) where {L}
        $(name===:log) && (iszero(x) || signbit(x)) &&
            throw(DomainError(x,"log requires a positive NFloat (finite-only format)"))
        result=Ref{NFloat{L}}()
        status=LibFlint.$c(result,Ref(x),_ctx(NFloat{L}))
        status==GR_SUCCESS || _status_error(status,$(QuoteNode(name)),NFloat{L})
        result[]
    end
end

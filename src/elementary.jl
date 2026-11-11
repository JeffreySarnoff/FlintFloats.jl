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

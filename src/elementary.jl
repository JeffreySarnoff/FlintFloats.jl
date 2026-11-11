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

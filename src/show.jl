# Display. `show` prints a constructor expression that rebuilds the value:
#   point types: exactly the same value (decimal with enough digits, or the exact expansion)
#   ball types:  a ball containing the original (FLINT rounds the printed radius up)

# Decimal digits that identify any P-bit value: ceil(P*log10(2)) + 2.
_digits(P) = ceil(Int, P * 0.30102999566398120) + 2

function _decimal(x::ArbFloat{P}) where {P}
    isnan(x) && return "NaN"
    isfinite(x) || return signbit(x) ? "-Inf" : "Inf"
    return string(BigFloat(x))
end

Base.show(io::IO, x::ArbFloat{P}) where {P} = print(io, "ArbFloat{", P, "}(\"", _decimal(x), "\")")
Base.show(io::IO, x::NFloat{L}) where {L} = print(io, "NFloat{", L, "}(\"", _decimal(ArbFloat{64L}(x)), "\")")
Base.show(io::IO, z::AcbFloat{P}) where {P} =
    print(io, "AcbFloat{", P, "}(\"", _decimal(real(z)), "\", \"", _decimal(imag(z)), "\")")

# FLINT's formatter returns a malloc'd string; free it even if string construction throws.
function _ball_string(x::ArbBall{P}) where {P}
    p = LibFlint.arb_get_str(x, _digits(P), 0)
    p == C_NULL && throw(OutOfMemoryError())
    try
        return unsafe_string(p)
    finally
        LibFlint.flint_free(p)
    end
end

Base.show(io::IO, x::ArbBall{P}) where {P} = print(io, "ArbBall{", P, "}(\"", _ball_string(x), "\")")
Base.show(io::IO, z::AcbBall{P}) where {P} =
    print(io, "AcbBall{", P, "}(\"", _ball_string(real(z)), "\", \"", _ball_string(imag(z)), "\")")

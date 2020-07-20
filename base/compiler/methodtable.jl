abstract type MethodTableView; end

struct MethodLookupResult
    # Really Vector{Core.MethodMatch}, but it's easier to represent this as
    # and work with Vector{Any} on the C side.
    matches::Vector{Any}
    valid_worlds::WorldRange
    ambig::Bool
end
length(result::MethodLookupResult) = length(result.matches)
function iterate(result::MethodLookupResult, args...)
    r = iterate(result.matches, args...)
    r === nothing && return nothing
    match, state = r
    return (match::MethodMatch, state)
end
getindex(result::MethodLookupResult, idx::Int) = getindex(result.matches, idx)::MethodMatch

"""
    struct InternalMethodTable <: MethodTableView

A singleton struct representing the state of the internal method table at a
particular world age.
"""
struct InternalMethodTable <: MethodTableView
    world::UInt
end

"""
    struct InternalMethodTable <: MethodTableView

Overlays another method table view with an additional local fast path cache that
can respond to repeated, identical queries faster than the original method table.
"""
struct CachedMethodTable{T} <: MethodTableView
    cache::IdDict{Any, Union{Missing, MethodLookupResult}}
    table::T
end
CachedMethodTable(table::T) where T =
    CachedMethodTable{T}(IdDict{Any, Union{Missing, MethodLookupResult}}(),
        table)

"""
    findall(sig::Type{<:Tuple}, view::MethodTableView; limit=typemax(Int))

Find all methods in the given method table `view` that are applicable to the
given signature `sig`. If no applicable methods are found, an empty result is
returned. If the number of applicable methods exeeded the specified limit,
`missing` is returned.
"""
function findall(@nospecialize(sig::Type{<:Tuple}), table::InternalMethodTable; limit::Int=typemax(Int))
    _min_val = RefValue{UInt}(typemin(UInt))
    _max_val = RefValue{UInt}(typemax(UInt))
    _ambig = RefValue{Int32}(0)
    ms = _methods_by_ftype(sig, limit, table.world, false, _min_val, _max_val, _ambig)
    if ms === false
        return missing
    end
    return MethodLookupResult(ms::Vector{Any}, WorldRange(_min_val[], _max_val[]), _ambig[] != 0)
end

function findall(@nospecialize(sig::Type{<:Tuple}), table::CachedMethodTable; limit::Int=typemax(Int))
    box = Core.Box(sig)
    return get!(table.cache, sig) do
        findall(box.contents, table.table; limit=limit)
    end
end

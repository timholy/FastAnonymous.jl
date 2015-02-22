module FastAnonymous
# using Base.Cartesian

import Base: call, map, map!, show

export @anon

abstract AbstractClosure{ext,argnames,V}  # V is the number of environment variables

#### Functions that only depend on values that are supplied as arguments

# Having this type reduces the number of types we have to generate

immutable Fun{ext,argnames} <: AbstractClosure{ext,argnames,0} end  # ext is an "expression tuple"

Fun(ex, argnames::(Symbol...)) = Fun{expr2tuple(ex), argnames}()

stagedfunction call{ext,argnames}(f::Fun{ext,argnames}, __X__...)
    n = length(__X__)
    if length(argnames) != n
        return :(error(f, " called with ", $n, " arguments"))
    end
    ex = tuple2expr(ext)
    Expr(:block, Expr(:meta, :inline), [:($(argnames[i]) = __X__[$i]) for i = 1:n]..., ex)
end

show{ext,argnames}(io::IO, f::Fun{ext,argnames}) = showanon(io, ext, argnames)

function showanon(io, ext, argnames)
    ex = tuple2expr(ext)
    print(io, '(')
    first = true
    for a in argnames
        if !first
            print(io, ',')
        end
        first=false
        print(io, a)
    end
    print(io, ") -> ")
    show(io, ex)
end

#### @anon

anon_usage() = error("Usage: f = @anon x -> x+a")

macro anon(ex)
    (isa(ex,Expr) && ex.head in (:function, :->)) || anon_usage()
    arglist = tupleargs(ex.args[1])
    body = ex.args[2]
    syms = nonarg_symbols(body, arglist)
    scopedbody = scopecalls(symbol(current_module()), body)
    qbody = Expr(:quote, scopedbody)
    if isempty(syms)
        return :(Fun($(esc(qbody)), $arglist))
    end
    symst = tuple(syms...)
    fields = map(x->Val{x}, symst)
    values = Expr(:tuple, [esc(v) for v in symst]...)
    :(closure($(esc(qbody)), $arglist, $fields, $values))
end

#### closure generates types as needed
# Note that these are "value" closures: they store the values at time of construction
# (Usual statements about reference objects, like arrays, apply)
stagedfunction closure{fieldnames,TT}(ex, argnames::(Symbol...), ::Type{fieldnames}, values::TT)
    N = length(fieldnames)
    length(values) == N || error("Number of values must match number of fields")
    typename = getclosure(fieldnames, values)
    :($typename(ex, argnames, values...))
end

function show{ext,argnames,N}(io::IO, c::AbstractClosure{ext,argnames,N})
    showanon(io, ext, argnames)
    print(io, "\nwith:")
    fieldnames = names(typeof(c))
    for i = 1:N
        print(io, "\n  ", fieldnames[i], ": ", getfield(c, i))
    end
end

getclosure(fieldnames, fieldtypes) = getclosure(map(popval, fieldnames), fieldtypes)
popval{T}(::Type{Val{T}}) = T

function getclosure(fieldnames::(Symbol...), fieldtypes)
    # Build the type
    typename = gensym("Closure")
    extype = :($typename{ext,argnames})
    M = length(fieldnames)
    fields = [Expr(:(::), fieldnames[i], fieldtypes[i]) for i = 1:M]
    extypedef = Expr(:type, true, Expr(:(<:), extype, :(AbstractClosure{ext,argnames,$M})), Expr(:block, fields...))
    eval(extypedef)
    # Build the constructor
    exconstr = :($typename(ex,argnames,values...) = $typename{expr2tuple(ex),argnames}(values...))
    eval(exconstr)
    # Overload call
    fieldassign = [:($(fieldnames[i]) = f.$(fieldnames[i])) for i = 1:M]
    excall = quote
        stagedfunction call{ext,argnames}(f::$extype, __X__...)
            n = length(__X__)
            N = length(argnames)
            if n != N
                return :(error(f, " called with ", $n, " arguments"))
            end
            ex = tuple2expr(ext)
            Expr(:block,
                 Expr(:meta, :inline),
                 [:($(argnames[i]) = __X__[$i]) for i = 1:N]...,
                 $fieldassign...,
                 ex)
        end
    end
    eval(excall)
    typename
end

#### Utilities

nonarg_symbols(body, arglist) = nonarg_symbols!(Set{Symbol}(), body, arglist)

function nonarg_symbols!(s, ex::Expr, arglist)
    ex.head == :line && return s
    startarg = ex.head == :call ? 2 : 1
    for i = startarg:length(ex.args)
        nonarg_symbols!(s, ex.args[i], arglist)
    end
    s
end
function nonarg_symbols!(s, sym::Symbol, arglist)
    if !(sym in arglist)
        push!(s, sym)
    end
    s
end
nonarg_symbols!(s, a, arglist) = s

tupleargs(funcargs::Symbol) = (funcargs,)
function tupleargs(funcargs::Expr)
    funcargs.head == :tuple || anon_usage()
    for i = 1:length(funcargs.args)
        if !isa(funcargs.args[i], Symbol)
            anon_usage()
        end
    end
    tuple(funcargs.args...)
end
tupleargs(funcargs) = anon_usage()


function expr2tuple(ex::Expr)
    args = [expr2tuple(a) for a in ex.args]
    tuple(ex.head, args...)
end
expr2tuple(q::QuoteNode) = q.value
expr2tuple(s) = s

function tuple2expr(t::Tuple)
    args = [tuple2expr(t[i]) for i = 2:length(t)]
    if t[1] == :.
        args[2] = QuoteNode(args[2])
    end
    Expr(t[1], args...)
end
tuple2expr(s) = s


scopecalls(mod, body) = scopecalls!(mod, deepcopy(body))

function scopecalls!(mod, ex::Expr)
    if ex.head == :call
        ex.args[1] = Expr(:., mod, QuoteNode(ex.args[1]))
        startarg = 2
    else
        startarg = 1
    end
    for i = startarg:length(ex.args)
        scopecalls!(mod, ex.args[i])
    end
    ex
end

scopecalls!(mod, arg) = arg


#### Methods using @anon-created "functions"

function map(f::AbstractClosure, A::AbstractArray)
    if isempty(A); return similar(A); end
    first = f(A[1])
    dest = similar(A, typeof(first))
    dest[1] = first
    return map_to!(f, 2, dest, A)
end

# To resolve some ambiguities
map!(f::AbstractClosure, dest::AbstractVector, r::Range) = _map!(f, dest, r)
map!(f::AbstractClosure, dest::AbstractArray, r::Range)  = _map!(f, dest, r)
function _map!{ext,argnames,V}(f::AbstractClosure{ext,argnames,V}, dest::AbstractArray, r::Range)
    length(dest) == length(r) || throw(DimensionMismatch("length of dest and r must match"))
    i = 1
    for ri in r
        @inbounds dest[i] = f(ri)
        i += 1
    end
    dest
end

function map!{T,S,N,ext,argnames,V}(f::AbstractClosure{ext,argnames,V}, dest::AbstractArray{S,N}, A::AbstractArray{T,N})
    for d = 1:N
        size(dest,d) == size(A,d) || throw(DimensionMismatch("size of dest and A must match"))
    end
    for I in eachindex(A)
        @inbounds dest[I] = f(A[I])
    end
    dest
end

function map!{T,N,ext,argnames,V}(f::AbstractClosure{ext,argnames,V}, dest::AbstractArray, A::AbstractArray{T,N})
    length(dest) == length(A) || throw(DimensionMismatch("length of dest and A must match"))
    k = 0
    for a in A
        @inbounds dest[k+1] = f(a)
    end
    dest
end

function map_to!{T,ext,argnames,V}(f::AbstractClosure{ext,argnames,V}, offs, dest::AbstractArray{T}, A::AbstractArray)
    # map to dest array, checking the type of each result. if a result does not
    # match, widen the result type and re-dispatch.
    @inbounds for i = offs:length(A)
        el = f(A[i])
        S = typeof(el)
        if S === T || S <: T
            dest[i] = el::T
        else
            R = typejoin(T, S)
            new = similar(dest, R)
            copy!(new,1, dest,1, i-1)
            new[i] = el
            return map_to!(f, i+1, new, A)
        end
    end
    return dest
end


end # module

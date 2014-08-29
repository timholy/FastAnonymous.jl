module FastAnonymous
using Base.Cartesian

import Base: map, map!

export @anon

#### @anon

anon_usage() = error("Usage: @anon f = x -> x+a")

macro anon(ex)
    isa(ex, Expr) && ex.head == :(=) || anon_usage()
    typename = ex.args[1]
    isa(typename, Symbol) || anon_usage()
    fanon = ex.args[2]
    exnew = anon2gen(typename, fanon)
    quote
        immutable $typename end
        @eval $(esc(exnew))
    end
end

function anon2gen(genfuncname, anon::Expr)
    anon.head in (:function, :->) || error("Must pass an anonymous function")
    argex = anon.args[1]
    if isa(argex, Symbol)
        arglist = (argex,)
    elseif isa(argex, Expr) && (argex::Expr).head == :tuple
        arglist = tuple(argex.args...)
        for a in arglist
            if !isa(a, Symbol)
                anon_usage()
            end
        end
    else
        anon_usage()
    end
    body = anon.args[2]
    if isa(body, Expr)
        # For any variables s other than arg, replace s with $s
        body = replace_except!(body, arglist)
    end
    ex = quote
        $genfuncname($(arglist...)) = $body
    end
end

function replace_except!(body::Expr, arglist)
    body.head == :line && return body
    startarg = body.head == :call ? 2 : 1
    for i = startarg:length(body.args)
        if isa(body.args[i], Symbol)
            s = body.args[i]::Symbol
            if !in(s, arglist)
                body.args[i] = Expr(:$, s)
            end
        elseif isa(body.args[i], Expr)
            replace_except!(body.args[i]::Expr, arglist)
        end
    end
    body
end


#### Methods using @anon-created "functions"

function map{f}(::Type{f}, A::AbstractArray)
    if isempty(A); return similar(A); end
    first = f(A[1])
    dest = similar(A, typeof(first))
    dest[1] = first
    return map_to!(f, 2, dest, A)
end

# To resolve some ambiguities
map!{f}(::Type{f}, dest::AbstractVector, r::Range) = _map!(f, dest, r)
map!{f}(::Type{f}, dest::AbstractArray, r::Range)  = _map!(f, dest, r)
function _map!{f}(::Type{f}, dest::AbstractArray, r::Range)
    length(dest) == length(r) || throw(DimensionMismatch("length of dest and r must match"))    
    i = 1
    for ri in r
        @inbounds dest[i] = f(ri)
        i += 1
    end
    dest
end

@ngenerate N typeof(dest) function map!{f,T,S,N}(::Type{f}, dest::AbstractArray{S,N}, A::AbstractArray{T,N})
    for d = 1:N
        size(dest,d) == size(A,d) || throw(DimensionMismatch("size of dest and A must match"))
    end
    @nloops N i A begin
        @inbounds @nref(N, dest, i) = f(@nref(N, A, i))
    end
    dest
end

@ngenerate N typeof(dest) function map!{f,T,N}(::Type{f}, dest::AbstractArray, A::AbstractArray{T,N})
    length(dest) == length(A) || throw(DimensionMismatch("length of dest and A must match"))
    k = 0
    @nloops N i A begin
        @inbounds dest[k+1] = f(@nref(N, A, i))
    end
    dest
end

function map_to!{T,f}(::Type{f}, offs, dest::AbstractArray{T}, A::AbstractArray)
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

module FastAnonymous
using Base.Cartesian

import Base: map, map!

export @anon

#### @anon

anon_usage() = error("Usage: f = @anon x -> x+a")

getargs(funcargs::Symbol) = (funcargs,)
getargs(funcargs::Expr) = tuple(funcargs.args...)

macro anon(ex)
    arglist, body = anonsplice(ex)
    qargs = map(x->Expr(:quote, x), arglist)
    qbody = QuoteNode(body)
    ex = quote
        typename = gensym()
        eval(quote
            immutable $typename end
            $typename($($(qargs...))) = $($qbody)
            $typename
        end)
    end
    :($(esc(ex)))
end

# For variables s other than those in the arglist, replace s with $s
# This will cause local variables to have their values spliced in.
function anonsplice(anon::Expr)
    anon.head in (:function, :->) || anon_usage()
    arglist = tupleargs(anon.args[1])
    body = anon.args[2]
    if isa(body, Expr)
        body = replace_except!(body, arglist)
    end
    arglist, body
end

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

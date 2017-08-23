# FastAnonymous

Creating efficient "anonymous functions" in [Julia](http://julialang.org/).

[![Build Status](https://travis-ci.org/timholy/FastAnonymous.jl.svg?branch=master)](https://travis-ci.org/timholy/FastAnonymous.jl)

# Note: this package is deprecated

FastAnonymous provoked/inspired the creation of fast anonymous
functions as a native feature for Julia 0.5. Hence this package is not
necessary (and not supported) for Julia 0.5 and higher. Starting with
Julia 0.7, this package will not be installable by the package manager.

## FastAnonymous versions

There are two implementations, one that runs on julia 0.3 and the other for julia 0.4.
If you're running julia 0.3, see the relevant [README](doc/README_0.3.md).

## Installation

Install this package within Julia using
```julia
Pkg.add("FastAnonymous")
```

## Usage

In Julia, you can create an anonymous function this way:
```julia
offset = 1.2
f = x->(x+offset)^2
```

At present, this function is not very efficient, as will be shown below.
You can make it more performant by adding the `@anon` macro:

```julia
using FastAnonymous

offset = 1.2
f = @anon x->(x+offset)^2
```
You can use `f` like an ordinary function.

Here's a concrete example and speed comparison:
```julia
using FastAnonymous

function testn(f, n)
    s = 0.0
    for i = 1:n
        s += f(i/n)
    end
    s
end

function test_inlined(n)
    s = 0.0
    for i = 1:n
        s += (i/n+1.2)^2
    end
    s
end

# Conventional anonymous function
offset = 1.2
f = x->(x+offset)^2
@time testn(f, 1)
julia> @time testn(f, 10^7)
elapsed time: 1.344960759 seconds (610 MB allocated, 4.13% gc time in 28 pauses with 0 full sweep)
2.973333503333424e7

# Hard-wired generic function
sqroffset(x) = (x+1.2)^2
@time testn(sqroffset, 1)
julia> @time testn(sqroffset, 10^7)
elapsed time: 0.627085369 seconds (457 MB allocated, 5.99% gc time in 21 pauses with 0 full sweep)
2.973333503333424e7

# @anon-ized function
g = @anon x->(x+offset)^2
@time testn(g, 1)
julia> @time testn(g, 10^7)
elapsed time: 0.07966527 seconds (112 bytes allocated)
2.973333503333424e7

# Full manual inlining
@time test_inlined(1)
julia> @time test_inlined(10^7)
elapsed time: 0.078703981 seconds (112 bytes allocated)
2.973333503333424e7
```

You can see that it's more than 20-fold faster than the anonymous-function version,
and more than tenfold faster than the generic function version.
Indeed, it's as fast as if we had manually inlined this function.
Relatedly, it also exhibits no unnecessary memory allocation.

## Changing parameter values

With the previous definition of `f`, the display at the REPL is informative:
```julia
julia> f = @anon x->(x+offset)^2
(x) -> quote  # none, line 1:
    Main.^(Main.+(x,offset),2)
end
with:
  offset: 1.2
```

`Main.` is a necessary addition for specifying the module scope; without them,
you can see the function definition as `^(+(x,offset),2)` which is equivalent to `(x+offset)^2`.
At the end, you see the "environment," which consists of stored values, in this case `offset: 1.2`.
After creating `f`, you can change environmental variables:
```julia
julia> f.offset = -7
-7.0

julia> f(7)
0.0

julia> f(9)
4.0
```

Any symbols that are not arguments end up in environmental variables. As a second example:

```julia
julia> x = linspace(0,pi);

julia> f = @anon (A,θ) -> A*sin(x+θ)
(A,θ) -> quote  # none, line 1:
    Main.*(A,Main.sin(Main.+(x,θ)))
end
with:
  x: [0.0,0.0317333,0.0634665,0.0951998,0.126933,0.158666,0.1904,0.222133,0.253866,0.285599  …  2.85599,2.88773,2.91946,2.95119,2.98293,3.01466,3.04639,3.07813,3.10986,3.14159]

julia> f(10,pi/4)
100-element Array{Float64,1}:
  7.07107
  7.29186
  7.50531
  ⋮
 -6.60836
 -6.84316
 -7.07107

julia> f.x[2] = 15
15

julia> f
(A,θ) -> quote  # none, line 1:
    Main.*(A,Main.sin(Main.+(x,θ)))
end
with:
  x: [0.0,15.0,0.0634665,0.0951998,0.126933,0.158666,0.1904,0.222133,0.253866,0.285599  …  2.85599,2.88773,2.91946,2.95119,2.98293,3.01466,3.04639,3.07813,3.10986,3.14159]
```

## Inner workings

This package uses shameless hacks to implement closures that behave much like
[a likely native solution](https://github.com/JuliaLang/julia/pull/10269#issuecomment-75389370).
One major difference is that the native closure environment is likely to be immutable, but here it is mutable.

## Acknowledgments

This package can be viewed in part as an alternative syntax to the excellent
[NumericFuns](https://github.com/lindahua/NumericFuns.jl),
which was split out from [NumericExtensions](https://github.com/lindahua/NumericExtensions.jl).

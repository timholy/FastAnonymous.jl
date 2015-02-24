# FastAnonymous

Creating efficient "anonymous functions" in [Julia](http://julialang.org/).

[![Build Status](https://travis-ci.org/timholy/FastAnonymous.jl.svg?branch=master)](https://travis-ci.org/timholy/FastAnonymous.jl)

There are two implementations, one that runs on julia 0.3 and the other for julia 0.4.
If you're running julia 0.4, see the relevant [README](doc/README_0.4.md).

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
You can use `f` like an ordinary function. If you want to pass this as an argument to another function,
it's best to declare that function in the following way:
```julia
function myfunction{f}(::Type{f}, args...)
    # Do stuff using f just like an ordinary function
end
```

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

function testn{f}(::Type{f}, n)
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
elapsed time: 1.984763506 seconds (640006424 bytes allocated, 22.73% gc time)
2.973333503333424e7

# Hard-wired generic function
sqroffset(x) = (x+1.2)^2
@time testn(sqroffset, 1)
julia> @time testn(sqroffset, 10^7)
elapsed time: 1.091590794 seconds (480006280 bytes allocated, 33.37% gc time)
2.973333503333424e7

# @anon-ized function
g = @anon x->(x+offset)^2
@time testn(g, 1)
julia> @time testn(g, 10^7)
elapsed time: 0.076382824 seconds (112 bytes allocated)
2.973333503333424e7

# Full manual inlining
@time test_inlined(1)
julia> @time test_inlined(10^7)
elapsed time: 0.077248689 seconds (112 bytes allocated)
2.973333503333424e7

```

You can see that it's more than 20-fold faster than the anonymous-function version,
and more than tenfold faster than the generic function version.
Indeed, it's as fast as if we had manually inlined this function.
Relatedly, it also exhibits no unnecessary memory allocation.

It even works inside of functions. Here's a demonstration:
```julia
function testwrap(dest, A, offset)
    ff = @anon x->(x+offset)^2
    map!(ff, dest, A)
end
```
It will generate a new version of the function each time you call `testwrap`,
so that passing in a different value for `offset` works as you'd expect.
In addition to building a new `ff`, this of course forces compilation of
a new version of `map!` that inlines the new version of `ff`.
Obviously, this is worthwhile only in cases where
compilation time is dwarfed by execution time.

## `@anon` does not make closures: differences from regular anonymous functions

Updating any parameters does not get reflected
in the output of the anonymous function. For instance:
```
offset = 1.2
f = x->(x+offset)^2
julia> f(2.8)
16.0

offset = 2.2
julia> f(2.8)
25.0
```
but
```
using FastAnonymous
offset = 1.2
f = @anon x->(x+offset)^2
julia> f(2.8)
16.0

offset = 2.2
julia> f(2.8)
16.0
```
The value of any parameters gets "frozen in" at the time of construction.

## Extensions of core Julia functions

This package contains versions of `map` and `map!` that are enabled for types.

## Inner workings

The statement `g = @anon x->(x+offset)^2` results in evaluation of something similar to
the following expression:
```julia
typename = gensym()
eval(quote
    immutable $typename end
    $typename(x) = (x+$offset)^2
    $typename
end)
```
`g` will be assigned the value of `typename`. Since `g` is a type, `g(x)` results
in the constructor being called. We've defined the constructor
in terms of the body of our anonymous function, taking care to splice in the value of the local
variable `offset`. One can see that the generated code is well-optimized:
```
julia> code_llvm(g, (Float64,))

define double @"julia_g;19968"(double) {
top:
  %1 = fadd double %0, 1.200000e+00, !dbg !1281
  %pow2 = fmul double %1, %1, !dbg !1281
  ret double %pow2, !dbg !1281
}
```
One small downside is the fact that `eval` ends up being called twice, once to evaluate the macro's
return value, and a second time to create the type and constructor in the caller's module.

Note that any local variables used in `@anon` persist
for the duration of your session and cannot be garbage-collected.

## Acknowledgments

This package is based on ideas suggested on the Julia mailing lists by [Mike Innes](https://groups.google.com/d/msg/julia-users/NZGMP-oa4T0/3q-sZwS9PyEJ)
and [Rafael Fourquet](https://groups.google.com/d/msg/julia-users/qscRyNqRrB4/_b6ERCCoh88J).
The final ingredients are splicing of local variables, getting it working inside functions,
and the proper quoting to support cross-module evaluation in functions.

This package can be viewed in part as an alternative syntax to the excellent
[NumericFuns](https://github.com/lindahua/NumericFuns.jl),
which was split out from [NumericExtensions](https://github.com/lindahua/NumericExtensions.jl).

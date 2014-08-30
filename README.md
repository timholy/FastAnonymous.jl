# FastAnonymous

Creating efficient "anonymous functions" in [Julia](http://julialang.org/).

[![Build Status](https://travis-ci.org/timholy/FastAnonymous.jl.svg?branch=master)](https://travis-ci.org/timholy/FastAnonymous.jl)

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
@anon f = x->(x+offset)^2
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

offset = 1.2
f = x->(x+offset)^2
@time testn(f, 1)
julia> @time testn(f, 10^7)
elapsed time: 1.984763506 seconds (640006424 bytes allocated, 22.73% gc time)
2.973333503333424e7

@anon g = x->(x+offset)^2
@time testn(g, 1)
julia> @time testn(g, 10^7)
elapsed time: 0.076382824 seconds (112 bytes allocated)
2.973333503333424e7

@time test_inlined(1)
julia> @time test_inlined(10^7)
elapsed time: 0.077248689 seconds (112 bytes allocated)
2.973333503333424e7

```

You can see that it's more than 20-fold faster and exhibits no unnecessary memory allocation,
and that it's as fast as if we had manually inlined this function.

## Extensions of core Julia functions

This package contains versions of `map` and `map!` that are enabled for types.

## Inner workings

The statement `@anon g = x->(x+offset)^2` results in evaluation of the following expression:
```julia
@eval begin
  immutable g end
  @eval g(x) = (x + $offset)^2
end
```
Since `g` is a type, `g(x)` results in the constructor being called. We've defined the constructor
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

## Acknowledgments

This package is based on ideas suggested on the Julia mailing lists by [Mike Innes](https://groups.google.com/d/msg/julia-users/NZGMP-oa4T0/3q-sZwS9PyEJ)
and [Rafael Fourquet](https://groups.google.com/d/msg/julia-users/qscRyNqRrB4/_b6ERCCoh88J).
The final ingredients are splicing of local variables and the proper quoting to support cross-module evaluation in functions.

This package can be viewed in part as an alternative syntax to the excellent
[NumericFuns](https://github.com/lindahua/NumericFuns.jl),
which was split out from [NumericExtensions](https://github.com/lindahua/NumericExtensions.jl).

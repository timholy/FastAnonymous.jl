using FastAnonymous
using Base.Test

immutable RGB
    r::Float64
    g::Float64
    b::Float64
end

offset = 1.2
@anon f = x->sqrt(x+offset)
@test_approx_eq f(7.8) 3.0

to_gray(x::Real) = x
to_gray(x::RGB) = 0.299*x.r + 0.587*x.g + 0.114*x.b
@anon gray = x->to_gray(x)
@test gray(0.8) == 0.8
@test gray(RGB(1,0,0)) == 0.299

@anon h = x->sin(x^2)
@test h(2.1) == sin((2.1)^2)

# Check that we are well optimized
x = rand(10)
y = similar(x)
map!(f, y, x)
@test (@allocated map!(f, y, x)) == 0

c = reinterpret(RGB, rand(30))
map!(gray, y, c)
@test (@allocated map!(gray, y, c)) == 0
map!(gray, y, x)
@test (@allocated map!(gray, y, x)) == 0

# Does it work in a function?
function testwrap(dest, A, offset)
    @anon ff = x->(x+offset)^2
    map!(ff, dest, A)
    @allocated map!(ff, dest, A)
end

@test testwrap(y, x, 1.2) == 0

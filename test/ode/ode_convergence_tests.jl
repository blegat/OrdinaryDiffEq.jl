# This definitely needs cleaning
using OrdinaryDiffEq, DiffEqDevTools, DiffEqBase,
      DiffEqProblemLibrary, Base.Test
probArr = Vector{ODEProblem}(2)
probArr[1] = prob_ode_linear

probArr[2] = prob_ode_2Dlinear
srand(100)
## Convergence Testing
dts = 1.//2.^(8:-1:4)
testTol = 0.2

for i = 1:2
  prob = probArr[i]
  sim = test_convergence(dts,prob,Euler())
  @test abs(sim.𝒪est[:final]-1) < testTol
  sim2 = test_convergence(dts,prob,Midpoint())
  @test abs(sim2.𝒪est[:l∞]-2) < testTol
  sim3 = test_convergence(dts,prob,RK4())
  @test abs(sim3.𝒪est[:l∞]-4) < testTol
  sim4 = test_convergence(dts,prob,BS3())
  @test abs(sim4.𝒪est[:l2]-3) < testTol

  ### Stiff Solvers

  dts = 1.//2.^(8:-1:4)

  sim11 = test_convergence(dts,prob,ImplicitEuler(extrapolant = :linear))
  @test abs(sim11.𝒪est[:final]-1) < testTol

  sim12 = test_convergence(dts,prob,
          GenericImplicitEuler(nlsolve=NLSOLVEJL_SETUP(autodiff=true)))
  @test abs(sim12.𝒪est[:final]-1) < testTol
  sim122 = test_convergence(dts,prob,
           GenericImplicitEuler(nlsolve=NLSOLVEJL_SETUP(autodiff=false)))

  sim13 = test_convergence(dts,prob,Trapezoid())
  @test abs(sim13.𝒪est[:final]-2) < testTol

  sim14 = test_convergence(dts,prob,
          GenericTrapezoid(nlsolve=NLSOLVEJL_SETUP(autodiff=true)))
  @test abs(sim14.𝒪est[:final]-2) < testTol
  sim142 = test_convergence(dts,prob,
           GenericTrapezoid(nlsolve=NLSOLVEJL_SETUP(autodiff=false)))
  @test abs(sim142.𝒪est[:final]-2) < testTol

  sim14 = test_convergence(dts,prob,TRBDF2())
  @test abs(sim14.𝒪est[:final]-2) < testTol
end

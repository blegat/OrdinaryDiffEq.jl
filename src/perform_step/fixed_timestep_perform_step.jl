function initialize!(integrator,cache::FunctionMapConstantCache)
  integrator.kshortsize = 0
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
end

function perform_step!(integrator,cache::FunctionMapConstantCache,repeat_step=false)
  if integrator.f != DiffEqBase.DISCRETE_OUTOFPLACE_DEFAULT
    if FunctionMap_scale_by_time(integrator.alg)
      @muladd integrator.u = integrator.uprev + integrator.dt*integrator.f(integrator.uprev,integrator.p,integrator.t+integrator.dt)
    else
      integrator.u = integrator.f(integrator.uprev,integrator.p,integrator.t+integrator.dt)
    end
  end
end

function initialize!(integrator,cache::FunctionMapCache)
  integrator.kshortsize = 0
  resize!(integrator.k, integrator.kshortsize)
end

function perform_step!(integrator,cache::FunctionMapCache,repeat_step=false)
  @unpack u,uprev,dt,t,f,p = integrator
  @unpack du = cache
  if integrator.f != DiffEqBase.DISCRETE_INPLACE_DEFAULT
    if FunctionMap_scale_by_time(integrator.alg)
      f(du, uprev, p, t+dt)
      @muladd @. u = uprev + dt*du
    else
      f(u,uprev,p,t)
    end
    if typeof(u) <: DEDataArray # Needs to get the fields, since updated uprev
      DiffEqBase.copy_fields!(u,uprev)
    end
  end
end

function initialize!(integrator,cache::EulerConstantCache)
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator,cache::EulerConstantCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @muladd u = uprev + dt*integrator.fsalfirst
  k = f(u, p, t+dt) # For the interpolation, needs k at the updated point
  integrator.fsallast = k
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
end

function initialize!(integrator,cache::EulerCache)
  integrator.kshortsize = 2
  @unpack k,fsalfirst = cache
  integrator.fsalfirst = fsalfirst
  integrator.fsallast = k
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst,integrator.uprev,integrator.p,integrator.t) # For the interpolation, needs k at the updated point
end

function perform_step!(integrator,cache::EulerCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @muladd @. u = uprev + dt*integrator.fsalfirst
  f(integrator.fsallast,u,p,t+dt) # For the interpolation, needs k at the updated point
end

function initialize!(integrator,cache::Union{HeunConstantCache,RalstonConstantCache})
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator,cache::Union{HeunConstantCache,RalstonConstantCache},repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  fsalfirst = integrator.fsalfirst

  if typeof(cache) <: HeunConstantCache
      a = dt
  else # Ralston
      a = 3dt/4
  end

  @muladd tmp = uprev + a*fsalfirst

  k2 = f(tmp,p,t+a)

  if typeof(cache) <: HeunConstantCache
      @muladd u = uprev + (dt/2)*(fsalfirst + k2)
  else
      @muladd u = uprev + (dt/3)*fsalfirst + (2dt/3)*k2
  end

  if integrator.opts.adaptive
      if typeof(cache) <: HeunConstantCache
          @muladd utilde = (dt/2)*(k2 - fsalfirst)
      else
          @muladd utilde = (2dt/3)*(k2 - fsalfirst)
      end

      atmp = calculate_residuals(utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
      integrator.EEst = integrator.opts.internalnorm(atmp)
  end
  k = f(u, p, t+dt)
  integrator.fsallast = k
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
end

function initialize!(integrator,cache::Union{HeunCache,RalstonCache})
  integrator.kshortsize = 2
  @unpack k,fsalfirst = cache
  integrator.fsalfirst = fsalfirst
  integrator.fsallast = k
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst,integrator.uprev,integrator.p,integrator.t) # For the interpolation, needs k at the updated point
end

function perform_step!(integrator,cache::Union{HeunCache,RalstonCache},repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack fsalfirst,k,utilde = cache

  if typeof(cache) <: HeunCache
      a = dt
  else # Ralston
      a = 3dt/4
  end

  @muladd @. utilde = uprev + a*fsalfirst

  f(k,utilde,p,t+a)

  if typeof(cache) <: HeunCache
      @muladd @. u = uprev + (dt/2)*(fsalfirst + k)
  else
      @muladd @. u = uprev + (dt/3)*fsalfirst + (2dt/3)*k
  end

  if integrator.opts.adaptive
      if typeof(cache) <: HeunCache
          @muladd @. utilde = (dt/2)*(k - fsalfirst)
      else
          @muladd @. utilde = (2dt/3)*(k - fsalfirst)
      end

      calculate_residuals!(utilde, utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
      integrator.EEst = integrator.opts.internalnorm(utilde)
  end
  f(integrator.fsallast,u,p,t+dt) # For the interpolation, needs k at the updated point
end

function initialize!(integrator,cache::MidpointConstantCache)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

@muladd function perform_step!(integrator,cache::MidpointConstantCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  halfdt = dt/2
  k = f(uprev + halfdt*integrator.fsalfirst, p, t+halfdt)
  u = uprev + dt*k
  integrator.fsallast = f(u, p, t+dt) # For interpolation, then FSAL'd
  if integrator.opts.adaptive
      utilde = dt*(integrator.fsalfirst - k)
      integrator.EEst = integrator.opts.internalnorm(
          calculate_residuals(utilde, uprev, u, integrator.opts.abstol,
                              integrator.opts.reltol,integrator.opts.internalnorm))
  end
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
end

function initialize!(integrator,cache::MidpointCache)
  @unpack k,fsalfirst = cache
  integrator.fsalfirst = fsalfirst
  integrator.fsallast = k
  integrator.kshortsize = 2
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst,integrator.uprev,integrator.p,integrator.t) # FSAL for interpolation
end

@muladd function perform_step!(integrator,cache::MidpointCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack tmp,k,fsalfirst,atmp = cache
  halfdt = dt/2
  @. tmp = uprev + halfdt*fsalfirst
  f(k, tmp, p, t+halfdt)
  @. u = uprev + dt*k
  if integrator.opts.adaptive
      @. tmp = dt*(fsalfirst - k)
      calculate_residuals!(atmp, tmp, uprev, u, integrator.opts.abstol,
                           integrator.opts.reltol,integrator.opts.internalnorm)
      integrator.EEst = integrator.opts.internalnorm(atmp)
  end
  f(k, u, p, t+dt)
end

function initialize!(integrator,cache::RK4ConstantCache)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

@muladd function perform_step!(integrator,cache::RK4ConstantCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  halfdt = dt/2
  k₁ =integrator.fsalfirst
  ttmp = t+halfdt
  k₂ = f(uprev + halfdt*k₁, p, ttmp)
  k₃ = f(uprev + halfdt*k₂, p, ttmp)
  k₄ = f(uprev + dt*k₃, p, t+dt)
  u = uprev + (dt/6)*(2*(k₂ + k₃) + (k₁+k₄))
  integrator.fsallast = f(u, p, t+dt)
  if integrator.opts.adaptive
      # Shampine Solving ODEs and DDEs with Residual Control Estimate
      k₅ = integrator.fsallast
      σ₁ = 1/2 - sqrt(3)/6
      σ₂ = 1/2 + sqrt(3)/6
      p1 = (1-σ₁)*uprev+σ₁*u+σ₁*(σ₁-1)*((1-2σ₁)*(u-uprev)+(σ₁-1)*dt*k₁ + σ₁*dt*k₅)
      p2 = (1-σ₂)*uprev+σ₂*u+σ₂*(σ₂-1)*((1-2σ₂)*(u-uprev)+(σ₂-1)*dt*k₁ + σ₂*dt*k₅)
      pprime1 = k₁ + σ₁*(-4*dt*k₁ - 2*dt*k₅ - 6*uprev +
                σ₁*(3*dt*k₁ + 3*dt*k₅ + 6*uprev - 6*u) + 6*u)/dt
      pprime2 = k₁ + σ₂*(-4*dt*k₁ - 2*dt*k₅ - 6*uprev +
                σ₂*(3*dt*k₁ + 3*dt*k₅ + 6*uprev - 6*u) + 6*u)/dt
      e1 = integrator.opts.internalnorm(calculate_residuals(dt*(f(p1,p,t+σ₁*dt) - pprime1), uprev, u, integrator.opts.abstol,
      integrator.opts.reltol,integrator.opts.internalnorm))
      e2 = integrator.opts.internalnorm(calculate_residuals(dt*(f(p2,p,t+σ₂*dt) - pprime2), uprev, u, integrator.opts.abstol, integrator.opts.reltol,
      integrator.opts.internalnorm))
      integrator.EEst = 2.1342*max(e1,e2)
  end
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
end

function initialize!(integrator,cache::RK4Cache)
  @unpack tmp,fsalfirst,k₂,k₃,k₄,k = cache
  integrator.fsalfirst = fsalfirst
  integrator.fsallast = k
  integrator.kshortsize = 2
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst,integrator.uprev,integrator.p,integrator.t) # pre-start FSAL
end

@muladd function perform_step!(integrator,cache::RK4Cache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack tmp,fsalfirst,k₂,k₃,k₄,k,atmp = cache
  k₁ = fsalfirst
  halfdt = dt/2
  ttmp = t+halfdt
  @. tmp = uprev + halfdt*k₁
  f(k₂,tmp,p,ttmp)
  @. tmp = uprev + halfdt*k₂
  f(k₃,tmp,p,ttmp)
  @. tmp = uprev + dt*k₃
  f(k₄,tmp,p,t+dt)
  @. u = uprev + (dt/6)*(2*(k₂ + k₃) + (k₁ + k₄))
  f(k, u, p, t+dt)
  if integrator.opts.adaptive
      # Shampine Solving ODEs and DDEs with Residual Control Estimate
      k₅ = k; _p = k₂; pprime = k₃ # Alias some cache arrays
      σ₁ = 1/2 - sqrt(3)/6
      σ₂ = 1/2 + sqrt(3)/6
      @tight_loop_macros for i in eachindex(u)
          @inbounds tmp[i] = (1-σ₁)*uprev[i]+σ₁*u[i]+σ₁*(σ₁-1)*((1-2σ₁)*(u[i]-uprev[i])+(σ₁-1)*dt*k₁[i] + σ₁*dt*k₅[i])
          @inbounds pprime[i] = k₁[i] + σ₁*(-4*dt*k₁[i] - 2*dt*k₅[i] - 6*uprev[i] +
                    σ₁*(3*dt*k₁[i] + 3*dt*k₅[i] + 6*uprev[i] - 6*u[i]) + 6*u[i])/dt
      end
      f(_p,tmp,p,t+σ₁*dt)
      calculate_residuals!(atmp, dt*(_p - pprime), uprev, u, integrator.opts.abstol,
                           integrator.opts.reltol,integrator.opts.internalnorm)
      e1 = integrator.opts.internalnorm(atmp)
      @tight_loop_macros for i in eachindex(u)
        @inbounds tmp[i] = (1-σ₂)*uprev[i]+σ₂*u[i]+σ₂*(σ₂-1)*((1-2σ₂)*(u[i]-uprev[i])+(σ₂-1)*dt*k₁[i] + σ₂*dt*k₅[i])
        @inbounds pprime[i] = k₁[i] + σ₂*(-4*dt*k₁[i] - 2*dt*k₅[i] - 6*uprev[i] +
                  σ₂*(3*dt*k₁[i] + 3*dt*k₅[i] + 6*uprev[i] - 6*u[i]) + 6*u[i])/dt
      end
      f(_p,tmp,p,t+σ₂*dt)
      calculate_residuals!(atmp, dt*(_p - pprime), uprev, u, integrator.opts.abstol,
                           integrator.opts.reltol,integrator.opts.internalnorm)
      e2 = integrator.opts.internalnorm(atmp)
      integrator.EEst = 2.1342*max(e1,e2)
  end
end


function initialize!(integrator,cache::CarpenterKennedy2N54ConstantCache)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
  integrator.kshortsize = 1
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
end

@muladd function perform_step!(integrator,cache::CarpenterKennedy2N54ConstantCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack A2,A3,A4,A5,B1,B2,B3,B4,B5,c2,c3,c4,c5 = cache

  # u1
  tmp = dt*integrator.fsalfirst
  u   = uprev + B1*tmp
  # u2
  k = f(u, p, t+c2*dt)
  tmp = A2*tmp + dt*k
  u   = u + B2*tmp
  # u3
  k = f(u, p, t+c3*dt)
  tmp = A3*tmp + dt*k
  u   = u + B3*tmp
  # u4
  k = f(u, p, t+c4*dt)
  tmp = A4*tmp + dt*k
  u   = u + B4*tmp
  # u5 = u
  k = f(u, p, t+c5*dt)
  tmp = A5*tmp + dt*k
  u   = u + B5*tmp

  integrator.fsallast = f(u, p, t+dt) # For interpolation, then FSAL'd
  integrator.k[1] = integrator.fsalfirst
  integrator.u = u
end

function initialize!(integrator,cache::CarpenterKennedy2N54Cache)
  @unpack k,fsalfirst = cache
  integrator.fsalfirst = fsalfirst
  integrator.fsallast = k
  integrator.kshortsize = 1
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.f(integrator.fsalfirst,integrator.uprev,integrator.p,integrator.t) # FSAL for interpolation
end

@muladd function perform_step!(integrator,cache::CarpenterKennedy2N54Cache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack k,fsalfirst,tmp = cache
  @unpack A2,A3,A4,A5,B1,B2,B3,B4,B5,c2,c3,c4,c5 = cache.tab

  # u1
  @. tmp = dt*fsalfirst
  @. u   = uprev + B1*tmp
  # u2
  f( k,  u, p, t+c2*dt)
  @. tmp = A2*tmp + dt*k
  @. u   = u + B2*tmp
  # u3
  f( k,  u, p, t+c3*dt)
  @. tmp = A3*tmp + dt*k
  @. u   = u + B3*tmp
  # u4
  f( k,  u, p, t+c4*dt)
  @. tmp = A4*tmp + dt*k
  @. u   = u + B4*tmp
  # u5 = u
  f( k,  u, p, t+c5*dt)
  @. tmp = A5*tmp + dt*k
  @. u   = u + B5*tmp

  f( k,  u, p, t+dt)
end

function initialize!(integrator, cache::Anas5ConstantCache)
  integrator.kshortsize = 7
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  @inbounds for i in 2:integrator.kshortsize-1
    integrator.k[i] = zero(integrator.fsalfirst)
  end
  integrator.k[integrator.kshortsize] = integrator.fsallast
end

@muladd function perform_step!(integrator, cache::Anas5ConstantCache, repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack a21,a31,a32,a41,a42,a43,a51,a52,a53,a54,a61,a62,a63,a64,c2,c3,c4,c5,c6,b1,b3,b4,b5,b6 = cache
  ## Note that c1 and b2 were 0.
  w = integrator.alg.w
  v = w*dt
  ## Formula by Z.A. Anastassi, see the Anas5 caches in tableaus/low_order_rk_tableaus.jl for the full citation.
  a65 = (-8000//1071)*(-a43*(v^5) + 6*tan(v)*(v^4) + 24*(v^3) - 72*tan(v)*(v^2) - 144*v + 144*tan(v))/((v^5)*(a43*tan(v)*v + 12 - 10*a43))
  a61 += (-119//200)*a65
  a63 += (189//100)*a65
  a64 += (-459//200)*a65
  k1 = integrator.fsalfirst
  k2 = f(uprev+dt*a21*k1, p, t+c2*dt)
  k3 = f(uprev+dt*(a31*k1+a32*k2), p, t+c3*dt)
  k4 = f(uprev+dt*(a41*k1+a42*k2+2*k3), p, t+c4*dt)
  k5 = f(uprev+dt*(a51*k1+a52*k2+a53*k3+a54*k4), p, t+c5*dt)
  k6 = f(uprev+dt*(a61*k1+a62*k2+a63*k3+a64*k4+a65*k5), p, t+c6*dt)
  u = uprev+dt*(b1*k1+b3*k3+b4*k4+b5*k5+b6*k6)
  k7 = f(u, p, t+dt); integrator.fsallast = k7
  integrator.k[1]=k1; integrator.k[2]=k2; integrator.k[3]=k3; integrator.k[4]=k4
  integrator.k[5]=k5; integrator.k[6]=k6; integrator.k[7]=k7;
  integrator.u = u
end

function initialize!(integrator, cache::Anas5Cache)
  integrator.kshortsize = 7
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1]=cache.k1; integrator.k[2]=cache.k2;
  integrator.k[3]=cache.k3; integrator.k[4]=cache.k4;
  integrator.k[5]=cache.k5; integrator.k[6]=cache.k6;
  integrator.k[7]=cache.k7;
  integrator.fsalfirst = cache.k1; integrator.fsallast = cache.k7  # setup pointers
  integrator.f(integrator.fsalfirst, integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
end

@muladd function perform_step!(integrator, cache::Anas5Cache, repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  uidx = eachindex(integrator.uprev)
  @unpack k1,k2,k3,k4,k5,k6,k7,utilde,tmp,atmp = cache
  @unpack a21,a31,a32,a41,a42,a43,a51,a52,a53,a54,a61,a62,a63,a64,c2,c3,c4,c5,c6,b1,b3,b4,b5,b6 = cache.tab
  w = integrator.alg.w
  v = w*dt
  ## Formula by Z.A. Anastassi, see the Anas5 caches in tableaus/low_order_rk_tableaus.jl for the full citation.
  a65 = (-8000//1071)*(-a43*(v^5) + 6*tan(v)*(v^4) + 24*(v^3) - 72*tan(v)*(v^2) - 144*v + 144*tan(v))/((v^5)*(a43*tan(v)*v + 12 - 10*a43))
  a61 += (-119//200)*a65
  a63 += (189//100)*a65
  a64 += (-459//200)*a65
  @tight_loop_macros for i in uidx
    @inbounds tmp[i] = uprev[i]+a21*k1[i]
  end
  f(k2, tmp, p, t+c2*dt)
  @tight_loop_macros for i in uidx
    @inbounds tmp[i] = uprev[i]+dt*(a31*k1[i]+a32*k2[i])
  end
  f(k3, tmp, p, t+c3*dt)
  @tight_loop_macros for i in uidx
    @inbounds tmp[i] = uprev[i]+dt*(a41*k1[i]+a42*k2[i]+2*k3[i])
  end
  f(k4, tmp, p, t+c4*dt)
  @tight_loop_macros for i in uidx
    @inbounds tmp[i] = uprev[i]+dt*(a51*k1[i]+a52*k2[i]+a53*k3[i]+a54*k4[i])
  end
  f(k5, tmp, p, t+c5*dt)
  @tight_loop_macros for i in uidx
    @inbounds tmp[i] = uprev[i]+dt*(a61*k1[i]+a62*k2[i]+a63*k3[i]+a64*k4[i]+a65*k5[i])
  end
  f(k6, tmp, p, t+c6*dt)
  @tight_loop_macros for i in uidx
    @inbounds u[i] = uprev[i]+dt*(b1*k1[i]+b3*k3[i]+b4*k4[i]+b5*k5[i]+b6*k6[i])
  end
  f(k7, u, p, t+dt)
end

"""
    volumerhs!(::Val{dim}, ::Val{N}, ::Val{nstate}, ::Val{nviscfluxstate},
               ::Val{nauxstate}, flux!, source!, rhs::Array, Q, Qvisc, auxstate,
               vgeo, t, D, elems) where {dim, N, nstate, nviscfluxstate,

Computational kernel: Evaluate the volume integrals on right-hand side of a
`DGBalanceLaw` semi-discretization.

See [`odefun!`](@ref) for usage.
"""
function volumerhs!(::Val{dim}, ::Val{N},
                    ::Val{nstate}, ::Val{nviscfluxstate},
                    ::Val{nauxstate},
                    flux!, source!,
                    rhs::Array,
                    Q, Qvisc, auxstate, vgeo, t,
                    D, elems) where {dim, N, nstate, nviscfluxstate,
                                     nauxstate}
  DFloat = eltype(Q)

  Nq = N + 1

  Nqk = dim == 2 ? 1 : Nq

  nelem = size(Q)[end]

  Q = reshape(Q, Nq, Nq, Nqk, nstate, nelem)
  Qvisc = reshape(Qvisc, Nq, Nq, Nqk, nviscfluxstate, nelem)
  rhs = reshape(rhs, Nq, Nq, Nqk, nstate, nelem)
  vgeo = reshape(vgeo, Nq, Nq, Nqk, _nvgeo, nelem)
  auxstate = reshape(auxstate, Nq, Nq, Nqk, nauxstate, nelem)

  s_F = MArray{Tuple{3, Nq, Nq, Nqk, nstate}, DFloat}(undef)

  source! !== nothing && (l_S = MArray{Tuple{nstate}, DFloat}(undef))
  l_Q = MArray{Tuple{nstate}, DFloat}(undef)
  l_Qvisc = MArray{Tuple{nviscfluxstate}, DFloat}(undef)
  l_aux = MArray{Tuple{nauxstate}, DFloat}(undef)

  l_F = MArray{Tuple{3, nstate}, DFloat}(undef)

  @inbounds for e in elems
    for k = 1:Nqk, j = 1:Nq, i = 1:Nq
      MJ = vgeo[i, j, k, _MJ, e]
      # MJI = vgeo[i, j, k, _MJI, e]
      ξx, ξy, ξz = vgeo[i,j,k,_ξx,e], vgeo[i,j,k,_ξy,e], vgeo[i,j,k,_ξz,e]
      ηx, ηy, ηz = vgeo[i,j,k,_ηx,e], vgeo[i,j,k,_ηy,e], vgeo[i,j,k,_ηz,e]
      ζx, ζy, ζz = vgeo[i,j,k,_ζx,e], vgeo[i,j,k,_ζy,e], vgeo[i,j,k,_ζz,e]

      for s = 1:nstate
        l_Q[s] = Q[i, j, k, s, e]
      end

      for s = 1:nviscfluxstate
        l_Qvisc[s] = Qvisc[i, j, k, s, e]
      end

      for s = 1:nauxstate
        l_aux[s] = auxstate[i, j, k, s, e]
      end

      flux!(l_F, l_Q, l_Qvisc, l_aux, t)

      for s = 1:nstate
        s_F[1,i,j,k,s] = MJ * (ξx * l_F[1, s] + ξy * l_F[2, s] + ξz * l_F[3, s])
        s_F[2,i,j,k,s] = MJ * (ηx * l_F[1, s] + ηy * l_F[2, s] + ηz * l_F[3, s])
        s_F[3,i,j,k,s] = MJ * (ζx * l_F[1, s] + ζy * l_F[2, s] + ζz * l_F[3, s])
      end

      if source! !== nothing
        source!(l_S, l_Q, l_aux, t)

        for s = 1:nstate
          rhs[i, j, k, s, e] += l_S[s]
        end
      end
    end

    # loop of ξ-grid lines
    for s = 1:nstate, k = 1:Nqk, j = 1:Nq, i = 1:Nq
      MJI = vgeo[i, j, k, _MJI, e]
      for n = 1:Nq
        rhs[i, j, k, s, e] += MJI * D[n, i] * s_F[1, n, j, k, s]
      end
    end
    # loop of η-grid lines
    for s = 1:nstate, k = 1:Nqk, j = 1:Nq, i = 1:Nq
      MJI = vgeo[i, j, k, _MJI, e]
      for n = 1:Nq
        rhs[i, j, k, s, e] += MJI * D[n, j] * s_F[2, i, n, k, s]
      end
    end
    # loop of ζ-grid lines
    if Nqk > 1
      for s = 1:nstate, k = 1:Nqk, j = 1:Nq, i = 1:Nq
        MJI = vgeo[i, j, k, _MJI, e]
        for n = 1:Nqk
          rhs[i, j, k, s, e] += MJI * D[n, k] * s_F[3, i, j, n, s]
        end
      end
    end
  end
end

"""
    facerhs!(::Val{dim}, ::Val{N}, ::Val{nstate}, ::Val{nviscfluxstate},
             ::Val{nauxstate}, numerical_flux!,
             numerical_boundary_flux!, rhs::Array, Q, Qvisc, auxstate,
             vgeo, sgeo, t, vmapM, vmapP, elemtobndy,
             elems) where {dim, N, nstate, nviscfluxstate, nauxstate}

Computational kernel: Evaluate the surface integrals on right-hand side of a
`DGBalanceLaw` semi-discretization.

See [`odefun!`](@ref) for usage.
"""
function facerhs!(::Val{dim}, ::Val{N},
                  ::Val{nstate}, ::Val{nviscfluxstate},
                  ::Val{nauxstate},
                  numerical_flux!,
                  numerical_boundary_flux!,
                  rhs::Array, Q, Qvisc, auxstate,
                  vgeo, sgeo,
                  t, vmapM, vmapP, elemtobndy,
                  elems) where {dim, N, nstate, nviscfluxstate, nauxstate}
  DFloat = eltype(Q)

  if dim == 1
    Np = (N+1)
    Nfp = 1
    nface = 2
  elseif dim == 2
    Np = (N+1) * (N+1)
    Nfp = (N+1)
    nface = 4
  elseif dim == 3
    Np = (N+1) * (N+1) * (N+1)
    Nfp = (N+1) * (N+1)
    nface = 6
  end

  l_QM = MArray{Tuple{nstate}, DFloat}(undef)
  l_QviscM = MArray{Tuple{nviscfluxstate}, DFloat}(undef)
  l_auxM = MArray{Tuple{nauxstate}, DFloat}(undef)

  l_QP = MArray{Tuple{nstate}, DFloat}(undef)
  l_QviscP = MArray{Tuple{nviscfluxstate}, DFloat}(undef)
  l_auxP = MArray{Tuple{nauxstate}, DFloat}(undef)

  l_F = MArray{Tuple{nstate}, DFloat}(undef)

  @inbounds for e in elems
    for f = 1:nface
      for n = 1:Nfp
        nM = (sgeo[_nx, n, f, e], sgeo[_ny, n, f, e], sgeo[_nz, n, f, e])
        sMJ, vMJI = sgeo[_sMJ, n, f, e], sgeo[_vMJI, n, f, e]
        idM, idP = vmapM[n, f, e], vmapP[n, f, e]

        eM, eP = e, ((idP - 1) ÷ Np) + 1
        vidM, vidP = ((idM - 1) % Np) + 1,  ((idP - 1) % Np) + 1

        # Load minus side data
        for s = 1:nstate
          l_QM[s] = Q[vidM, s, eM]
        end

        for s = 1:nviscfluxstate
          l_QviscM[s] = Qvisc[vidM, s, eM]
        end

        for s = 1:nauxstate
          l_auxM[s] = auxstate[vidM, s, eM]
        end

        # Load plus side data
        for s = 1:nstate
          l_QP[s] = Q[vidP, s, eP]
        end

        for s = 1:nviscfluxstate
          l_QviscP[s] = Qvisc[vidP, s, eP]
        end

        for s = 1:nauxstate
          l_auxP[s] = auxstate[vidP, s, eP]
        end


        bctype =
            numerical_boundary_flux! === nothing ? 0 : elemtobndy[f, e]
        if bctype == 0
          numerical_flux!(l_F, nM, l_QM, l_QviscM, l_auxM, l_QP, l_QviscP,
                          l_auxP, t)
        else numerical_boundary_flux!(l_F, nM, l_QM, l_QviscM, l_auxM, l_QP,
                                      l_QviscP, l_auxP, bctype, t)
        end

        #Update RHS
        for s = 1:nstate
          rhs[vidM, s, eM] -= vMJI * sMJ * l_F[s]
        end
      end
    end
  end
end

function volumeviscterms!(::Val{dim}, ::Val{N}, ::Val{nstate},
                          ::Val{states_grad}, ::Val{nviscstate},
                          ::Val{nviscfluxstate}, ::Val{nauxstate},
                          viscous_transform!, gradient_transform!, Q::Array,
                          Qvisc, auxstate, vgeo, t, D,
                          elems) where {dim, N, states_grad, nviscstate,
                                        nviscfluxstate, nstate, nauxstate}
  DFloat = eltype(Q)

  Nq = N + 1

  Nqk = dim == 2 ? 1 : Nq

  nelem = size(Q)[end]
  ngradstate = length(states_grad)

  Q = reshape(Q, Nq, Nq, Nqk, nstate, nelem)
  Qvisc = reshape(Qvisc, Nq, Nq, Nqk, nviscfluxstate, nelem)
  auxstate = reshape(auxstate, Nq, Nq, Nqk, nauxstate, nelem)
  vgeo = reshape(vgeo, Nq, Nq, Nqk, _nvgeo, nelem)

  s_H = MArray{Tuple{Nq, Nq, Nqk, nviscstate}, DFloat}(undef)

  l_Q = MArray{Tuple{ngradstate}, DFloat}(undef)
  l_aux = MArray{Tuple{nauxstate}, DFloat}(undef)
  l_H = MArray{Tuple{nviscstate}, DFloat}(undef)
  l_Qvisc = MArray{Tuple{nviscfluxstate}, DFloat}(undef)
  l_gradH = MArray{Tuple{3, nviscstate}, DFloat}(undef)

  @inbounds for e in elems
    for k = 1:Nqk, j = 1:Nq, i = 1:Nq
      for s = 1:ngradstate
        l_Q[s] = Q[i, j, k, states_grad[s], e]
      end

      for s = 1:nauxstate
        l_aux[s] = auxstate[i, j, k, s, e]
      end

      gradient_transform!(l_H, l_Q, l_aux, t)
      for s = 1:nviscstate
        s_H[i, j, k, s] = l_H[s]
      end
    end

    # Compute gradient of each state
    for k = 1:Nqk, j = 1:Nq, i = 1:Nq
      ξx, ξy, ξz = vgeo[i,j,k,_ξx,e], vgeo[i,j,k,_ξy,e], vgeo[i,j,k,_ξz,e]
      ηx, ηy, ηz = vgeo[i,j,k,_ηx,e], vgeo[i,j,k,_ηy,e], vgeo[i,j,k,_ηz,e]
      ζx, ζy, ζz = vgeo[i,j,k,_ζx,e], vgeo[i,j,k,_ζy,e], vgeo[i,j,k,_ζz,e]

      for s = 1:ngradstate
        l_Q[s] = Q[i, j, k, states_grad[s], e]
      end

      for s = 1:nviscstate
        Hξ = Hη = Hζ = zero(DFloat)
        for n = 1:Nq
          Hξ += D[i, n] * s_H[n, j, k, s]
          Hη += D[j, n] * s_H[i, n, k, s]
          dim == 3 && (Hζ += D[k, n] * s_H[i, j, n, s])
        end
        l_gradH[1, s] = ξx * Hξ + ηx * Hη + ζx * Hζ
        l_gradH[2, s] = ξy * Hξ + ηy * Hη + ζy * Hζ
        l_gradH[3, s] = ξz * Hξ + ηz * Hη + ζz * Hζ
      end

      viscous_transform!(l_Qvisc, l_gradH, l_Q, l_aux, t)

      for s = 1:nviscfluxstate
        Qvisc[i, j, k, s, e] = l_Qvisc[s]
      end
    end
  end
end

function faceviscterms!(::Val{dim}, ::Val{N}, ::Val{nstate}, ::Val{states_grad},
                        ::Val{nviscstate}, ::Val{nviscfluxstate},
                        ::Val{nauxstate}, viscous_penalty!,
                        viscous_boundary_penalty!, gradient_transform!,
                        Q::Array, Qvisc, auxstate, vgeo, sgeo, t, vmapM, vmapP,
                        elemtobndy, elems) where {dim, N, states_grad,
                                                  nviscstate, nviscfluxstate,
                                                  nstate, nauxstate}
  DFloat = eltype(Q)

  if dim == 1
    Np = (N+1)
    Nfp = 1
    nface = 2
  elseif dim == 2
    Np = (N+1) * (N+1)
    Nfp = (N+1)
    nface = 4
  elseif dim == 3
    Np = (N+1) * (N+1) * (N+1)
    Nfp = (N+1) * (N+1)
    nface = 6
  end

  ngradstate = length(states_grad)

  l_QM = MArray{Tuple{ngradstate}, DFloat}(undef)
  l_auxM = MArray{Tuple{nauxstate}, DFloat}(undef)
  l_HM = MArray{Tuple{nviscstate}, DFloat}(undef)

  l_QP = MArray{Tuple{ngradstate}, DFloat}(undef)
  l_auxP = MArray{Tuple{nauxstate}, DFloat}(undef)
  l_HP = MArray{Tuple{nviscstate}, DFloat}(undef)

  l_Qvisc = MArray{Tuple{nviscfluxstate}, DFloat}(undef)

  @inbounds for e in elems
    for f = 1:nface
      for n = 1:Nfp
        nM = (sgeo[_nx, n, f, e], sgeo[_ny, n, f, e], sgeo[_nz, n, f, e])
        sMJ, vMJI = sgeo[_sMJ, n, f, e], sgeo[_vMJI, n, f, e]
        idM, idP = vmapM[n, f, e], vmapP[n, f, e]

        eM, eP = e, ((idP - 1) ÷ Np) + 1
        vidM, vidP = ((idM - 1) % Np) + 1,  ((idP - 1) % Np) + 1

        # Load minus side data
        for s = 1:ngradstate
          l_QM[s] = Q[vidM, states_grad[s], eM]
        end

        for s = 1:nauxstate
          l_auxM[s] = auxstate[vidM, s, eM]
        end

        gradient_transform!(l_HM, l_QM, l_auxM, t)

        # Load plus side data
        for s = 1:ngradstate
          l_QP[s] = Q[vidP, states_grad[s], eP]
        end

        for s = 1:nauxstate
          l_auxP[s] = auxstate[vidP, s, eP]
        end

        gradient_transform!(l_HP, l_QP, l_auxP, t)

        bctype =
            viscous_boundary_penalty! === nothing ? 0 : elemtobndy[f, e]
        if bctype == 0
          viscous_penalty!(l_Qvisc, nM, l_HM, l_QM, l_auxM, l_HP,
                                  l_QP, l_auxP, t)
        else
          viscous_boundary_penalty!(l_Qvisc, nM, l_HM, l_QM, l_auxM,
                                           l_HP, l_QP, l_auxP, bctype, t)
        end

        for s = 1:nviscfluxstate
          Qvisc[vidM, s, eM] += vMJI * sMJ * l_Qvisc[s]
        end

      end
    end
  end

end


"""
    initauxstate!(::Val{dim}, ::Val{N}, ::Val{nauxstate}, auxstatefun!,
                  auxstate, vgeo, elems) where {dim, N, nauxstate}

Computational kernel: Initialize the auxiliary state

See [`DGBalanceLaw`](@ref) for usage.
"""
function initauxstate!(::Val{dim}, ::Val{N}, ::Val{nauxstate}, auxstatefun!,
                       auxstate, vgeo, elems) where {dim, N, nauxstate}

  # Should only be called in this case I think?
  @assert nauxstate > 0

  DFloat = eltype(auxstate)

  Nq = N + 1

  Nqk = dim == 2 ? 1 : Nq

  nelem = size(auxstate)[end]

  vgeo = reshape(vgeo, Nq, Nq, Nqk, _nvgeo, nelem)
  auxstate = reshape(auxstate, Nq, Nq, Nqk, nauxstate, nelem)

  l_aux = MArray{Tuple{nauxstate}, DFloat}(undef)

  @inbounds for e in elems
    for k = 1:Nqk, j = 1:Nq, i = 1:Nq
      x, y, z = vgeo[i,j,k,_x,e], vgeo[i,j,k,_y,e], vgeo[i,j,k,_z,e]
      for s = 1:nauxstate
        l_aux[s] = auxstate[i, j, k, s, e]
      end

      auxstatefun!(l_aux, x, y, z)

      for s = 1:nauxstate
        auxstate[i, j, k, s, e] = l_aux[s]
      end
    end
  end
end

"""
    elem_grad_field!(::Val{dim}, ::Val{N}, ::Val{nstate}, Q, vgeo, D, elems, s,
                     sx, sy, sz) where {dim, N, nstate}

Computational kernel: Compute the element gradient of state `s` of `Q` and store
it in `sx`, `sy`, and `sz` of `Q`.

!!! warning

    This does not compute a DG gradient, but only over the element. If ``Q_s``
    is discontinuous you may want to consider another approach.

"""
function elem_grad_field!(::Val{dim}, ::Val{N}, ::Val{nstate}, Q, vgeo,
                          D, elems, s, sx, sy, sz) where {dim, N, nstate}

  DFloat = eltype(vgeo)

  Nq = N + 1

  Nqk = dim == 2 ? 1 : Nq

  nelem = size(vgeo)[end]

  vgeo = reshape(vgeo, Nq, Nq, Nqk, _nvgeo, nelem)
  Q = reshape(Q, Nq, Nq, Nqk, nstate, nelem)

  s_f = MArray{Tuple{Nq, Nq, Nqk}, DFloat}(undef)
  l_fξ = MArray{Tuple{Nq, Nq, Nqk}, DFloat}(undef)
  l_fη = MArray{Tuple{Nq, Nq, Nqk}, DFloat}(undef)
  l_fζ = MArray{Tuple{Nq, Nq, Nqk}, DFloat}(undef)

  @inbounds for e in elems
    for k = 1:Nqk, j = 1:Nq, i = 1:Nq
      s_f[i,j,k] = Q[i,j,k,s,e]
    end

    # loop of ξ-grid lines
    l_fξ .= 0
    for k = 1:Nqk, j = 1:Nq, i = 1:Nq
      for n = 1:Nq
        l_fξ[i, j, k] += D[i, n] * s_f[n, j, k]
      end
    end
    # loop of η-grid lines
    l_fη .= 0
    for k = 1:Nqk, j = 1:Nq, i = 1:Nq
      for n = 1:Nq
        l_fη[i, j, k] += D[j, n] * s_f[i, n, k]
      end
    end
    # loop of ζ-grid lines
    l_fζ .= 0
    if Nqk > 1
      for k = 1:Nqk, j = 1:Nq, i = 1:Nq
        for n = 1:Nq
          l_fζ[i, j, k] += D[k, n] * s_f[i, j, n]
        end
      end
    end

    for k = 1:Nqk, j = 1:Nq, i = 1:Nq
      ξx, ξy, ξz = vgeo[i,j,k,_ξx,e], vgeo[i,j,k,_ξy,e], vgeo[i,j,k,_ξz,e]
      ηx, ηy, ηz = vgeo[i,j,k,_ηx,e], vgeo[i,j,k,_ηy,e], vgeo[i,j,k,_ηz,e]
      ζx, ζy, ζz = vgeo[i,j,k,_ζx,e], vgeo[i,j,k,_ζy,e], vgeo[i,j,k,_ζz,e]

      Q[i,j,k,sx,e] = ξx * l_fξ[i,j,k] + ηx * l_fη[i,j,k] + ζx * l_fζ[i,j,k]
      Q[i,j,k,sy,e] = ξy * l_fξ[i,j,k] + ηy * l_fη[i,j,k] + ζy * l_fζ[i,j,k]
      Q[i,j,k,sz,e] = ξz * l_fξ[i,j,k] + ηz * l_fη[i,j,k] + ζz * l_fζ[i,j,k]
    end
  end
end

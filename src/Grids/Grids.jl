abstract type AbstractGrid{T, N} <: AbstractArray{T, N} end

"""
    T: tick type
    N: N dimensional
    S: System (Cartesian, Cylindrical...)
"""
struct Grid{T, N, S} <: AbstractGrid{T, N}
    axes::NTuple{N, DiscreteAxis{T}} 
end

const CartesianGrid{T, N} = Grid{T, N, :Cartesian} 
const CartesianGrid1D{T} = CartesianGrid{T, 1}
const CartesianGrid2D{T} = CartesianGrid{T, 2}
const CartesianGrid3D{T} = CartesianGrid{T, 3}
const RadialGrid{T} = Grid{T, 1, :Radial} 
const PolarGrid{T} = Grid{T, 2, :Polar} 
const CylindricalGrid{T} = Grid{T, 3, :Cylindrical} 
const SphericalGrid{T} = Grid{T, 3, :Spherical} 

@inline size(g::Grid{T, N, S}) where {T, N, S} = size.(g.axes, 1)
@inline length(g::Grid{T, N, S}) where {T, N, S} = prod(size(g))
@inline getindex(g::Grid{T, N, S}, I::Vararg{Int, N}) where {T, N, S} = broadcast(getindex, g.axes, I)
@inline getindex(g::Grid{T, N, S}, i::Int) where {T, N, S} = g.axes[i]
@inline getindex(g::Grid{T, N, S}, s::Symbol) where {T, N, S} = getindex(g, Val{s}())

@inline getindex(g::CylindricalGrid{T}, ::Val{:r}) where {T} = g.axes[1]
@inline getindex(g::CylindricalGrid{T}, ::Val{:θ}) where {T} = g.axes[2]
@inline getindex(g::CylindricalGrid{T}, ::Val{:z}) where {T} = g.axes[3]
@inline getindex(g::CartesianGrid{T}, ::Val{:x}) where {T} = g.axes[1]
@inline getindex(g::CartesianGrid{T}, ::Val{:y}) where {T} = g.axes[2]
@inline getindex(g::CartesianGrid{T}, ::Val{:z}) where {T} = g.axes[3]

function sizeof(g::Grid{T, N, S}) where {T, N, S}
    return sum( sizeof.(g.axes) )
end

function print(io::IO, g::Grid{T, N, S}) where {T, N, S}
    for ax in g.axes
        print(io, ax, " | ")
    end
end
function println(io::IO, g::Grid{T, N, S}) where {T, N, S}
    for (i, ax) in enumerate(g.axes)
        println(io, "Axis $(i): ", ax)
    end
end
show(io::IO, g::Grid{T, N, S}) where {T, N, S} = println(io, g)
show(io::IO, ::MIME"text/plain", g::Grid{T, N, S}) where {T, N, S} = show(io, g)


function check_grid(grid::CylindricalGrid{T})::Nothing where {T}
    nr::Int, nθ::Int, nz::Int = size(grid)
    @assert iseven(nz) "GridError: Field simulation algorithm in cylindrical coordinates need an even number of grid points in z. This is not the case. #z-ticks = $(nz)."
    @assert (iseven(nθ) || (nθ == 1)) "GridError: Field simulation algorithm in cylindrical coordinates need an even number of grid points in θ or just one point (2D). This is not the case. #θ-ticks = $(nθ)."
    return nothing
end

include("RefineGrid.jl")

@recipe function f(grid::Grid{T, N, S}) where {T, N, S}
    layout --> N
    st --> :stephist
    legend --> false

    for iax in 1:N
        @series begin
            subplot := iax
            nbins --> div(length(grid[iax]), 2)
            xlabel --> "Grid point density - Axis $(iax)"
            grid[iax]
        end
    end
end


function get_coordinate_type(grid::Grid{T, N, S}) where {T, N, S}
    return S
end
function get_number_of_dimensions(grid::Grid{T, N, S}) where {T, N, S}
    return N
end
function eltype(grid::Grid{T, N, S})::DataType where {T, N, S}
    return T
end

function get_boundary_types(grid::Grid{T, N, S}) where {T, N, S}
   return get_boundary_types.(grid.axes) 
end


function Grid(nt::NamedTuple)
    if nt.coordtype == "Cylindrical"
        axr::DiscreteAxis = DiscreteAxis(nt.axes.r, unit=u"m")
        axθ::DiscreteAxis = DiscreteAxis(nt.axes.phi, unit=u"rad")
        axz::DiscreteAxis = DiscreteAxis(nt.axes.z, unit=u"m")
        T = typeof(axr.ticks[1])
        return Grid{T, 3, :Cylindrical}( (axr, axθ, axz) )
    else
        error("`coordtype` = $(nt.coordtype) is not valid.")
    end
end

Base.convert(T::Type{Grid}, x::NamedTuple) = T(x)

function NamedTuple(grid::Grid{T, 3, :Cylindrical}) where {T}
    axr::DiscreteAxis{T} = grid[:r]
    axθ::DiscreteAxis{T} = grid[:θ]
    axz::DiscreteAxis{T} = grid[:z]
    return (
        coordtype = "Cylindrical",
        ndims = 3,
        axes = (
            r = NamedTuple(axr, unit=u"m"),
            phi = NamedTuple(axθ, unit=u"rad"),
            z = NamedTuple(axz, unit=u"m"),
        )
    )
end

Base.convert(T::Type{NamedTuple}, x::Grid) = T(x)


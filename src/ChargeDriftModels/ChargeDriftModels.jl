abstract type AbstractChargeDriftModels end
abstract type TemperatureModels{T <: AbstractFloat} end


"""
    VacuumChargeDriftModel <: AbstractChargeDriftModels
"""
struct VacuumChargeDriftModel <: AbstractChargeDriftModels end

function get_electron_drift_field(ef::Array{SVector{3,T},3}, ::VacuumChargeDriftModel)::Array{SVector{3,T},3} where {T<:AbstractFloat}
    return -ef
end
function get_hole_drift_field(ef::Array{SVector{3,T},3}, ::VacuumChargeDriftModel)::Array{SVector{3,T},3} where {T<:AbstractFloat}
    return ef
end



#################################
### Start: ADL Charge Drift Model

struct VelocityParameters{T}
    mu0::T
    beta::T
    E0::T
    mun::T
end

struct CarrierParameters{T}
    axis100::VelocityParameters{T}
    axis111::VelocityParameters{T}
end

include("LinearModel.jl")
include("BoltzmannModel.jl")
include("PowerLawModel.jl")
include("VacuumModel.jl")

# Electron model parametrization from [3]
@fastmath function γj(j::Integer, phi110::T, γ0::SArray{Tuple{3,3},T,2,9})::SArray{Tuple{3,3},T,2,9} where {T <: AbstractFloat}
    tmp::T = 2 / 3
    a::T = acos(sqrt(tmp))
    Rx::SArray{Tuple{3,3},T,2,9} = SMatrix{3,3,T}(1, 0, 0, 0, cos(a), sin(a), 0, -sin(a), cos(a))
    b::T = phi110 + (j - 1) * T(π) / 2
    Rzj::SArray{Tuple{3,3},T,2,9} = SMatrix{3,3,T}(cos(b), sin(b), 0, -sin(b), cos(b), 0, 0, 0, 1)
    Rj = Rx * Rzj
    transpose(Rj) * γ0 * Rj
end

@fastmath function setup_gamma_matrices(phi110::T)::SVector{4, SMatrix{3,3,T}} where {T <: AbstractFloat}
    ml::T = 1.64
    mt::T = 0.0819
    γ0 = SMatrix{3,3,T}(1 / mt, 0, 0, 0, 1 / ml, 0, 0, 0, 1 / mt)
    SVector{4, SArray{Tuple{3,3},T,2,9}}(γj(1, phi110, γ0), γj(2, phi110, γ0), γj(3, phi110, γ0), γj(4, phi110, γ0))
end

# Longitudinal drift velocity formula
@fastmath function Vl(Emag::T, params::VelocityParameters{T})::T where {T <: AbstractFloat}
    params.mu0 * Emag / (1 + (Emag / params.E0)^params.beta)^(1 / params.beta) - params.mun * Emag
end


"""
    ADLChargeDriftModel{T <: AbstractFloat} <: AbstractChargeDriftModels

# Fields
- `electrons::CarrierParameters{T}`
- `holes::CarrierParameters{T}`
- `phi110::T
- `gammas::SVector{4, SMatrix{3,3,T}}`
- `temperaturemodel::TemperatureModels{T}`
"""

struct ADLChargeDriftModel{T <: AbstractFloat} <: AbstractChargeDriftModels
    electrons::CarrierParameters{T}
    holes::CarrierParameters{T}
    phi110::T
    gammas::SVector{4, SMatrix{3,3,T}}
    temperaturemodel::TemperatureModels{T}
end


function ADLChargeDriftModel(configfilename::Union{Missing, AbstractString} = missing; T::Type=Float32,
                             temperature::Union{Missing, Real}= missing, phi110::Union{Missing, Real} = missing)::ADLChargeDriftModel{T}

    if ismissing(configfilename) configfilename = joinpath(@__DIR__, "drift_velocity_config.json") end
    if !ismissing(temperature) temperature = T(temperature) end  #if you give the temperature it will be used, otherwise read from config file


    config = JSON.parsefile(configfilename)

    #mu0 in m^2 / ( V * s )
    e100mu0::T  = config["drift"]["velocity"]["parameters"]["e100"]["mu0"]
    #beta dimensionless
    e100beta::T = config["drift"]["velocity"]["parameters"]["e100"]["beta"]
    #E0 in V / m
    e100E0::T   = config["drift"]["velocity"]["parameters"]["e100"]["E0"]
    #mun in m^2 / ( V * s )
    e100mun::T  = config["drift"]["velocity"]["parameters"]["e100"]["mun"]

    e111mu0::T  = config["drift"]["velocity"]["parameters"]["e111"]["mu0"]
    e111beta::T = config["drift"]["velocity"]["parameters"]["e111"]["beta"]
    e111E0::T   = config["drift"]["velocity"]["parameters"]["e111"]["E0"]
    e111mun::T  = config["drift"]["velocity"]["parameters"]["e111"]["mun"]
    h100mu0::T  = config["drift"]["velocity"]["parameters"]["h100"]["mu0"]
    h100beta::T = config["drift"]["velocity"]["parameters"]["h100"]["beta"]
    h100E0::T   = config["drift"]["velocity"]["parameters"]["h100"]["E0"]
    h111mu0::T  = config["drift"]["velocity"]["parameters"]["h111"]["mu0"]
    h111beta::T = config["drift"]["velocity"]["parameters"]["h111"]["beta"]
    h111E0::T   = config["drift"]["velocity"]["parameters"]["h111"]["E0"]

    e100 = VelocityParameters{T}(e100mu0, e100beta, e100E0, e100mun)
    e111 = VelocityParameters{T}(e111mu0, e111beta, e111E0, e111mun)
    h100 = VelocityParameters{T}(h100mu0, h100beta, h100E0, 0)
    h111 = VelocityParameters{T}(h111mu0, h111beta, h111E0, 0)
    electrons = CarrierParameters{T}(e100, e111)
    holes     = CarrierParameters{T}(h100, h111)

    ismissing(phi110) ? phi110 = config["phi110"] : phi110 = T(phi110)  #if you give the angle of the 110 axis it will be used, otherwise read from config file

    gammas = setup_gamma_matrices(phi110)

    if "temperature_dependence" in keys(config)
        if "model" in keys(config["temperature_dependence"])
            model::String = config["temperature_dependence"]["model"]
            if model == "Linear"
                temperaturemodel = LinearModel{T}(config, temperature = temperature)
            elseif model == "PowerLaw"
                temperaturemodel = PowerLawModel{T}(config, temperature = temperature)
            elseif model == "Boltzmann"
                temperaturemodel = BoltzmannModel{T}(config, temperature = temperature)
            else
                temperaturemodel = VacuumModel{T}(config)
                println("Config File does not suit any of the predefined temperature models. The drift velocity will not be rescaled.")
            end
        else
            temperaturemodel = VacuumModel{T}(config)
            println("No temperature model specified. The drift velocity will not be rescaled.")
        end
    else
        temperaturemodel = VacuumModel{T}(config)
        println("No temperature dependence found in Config File. The drift velocity will not be rescaled.")
    end

    return ADLChargeDriftModel{T}(electrons, holes, phi110, gammas, temperaturemodel)
end

function get_electron_drift_field(ef::Array{SVector{3, T},3}, chargedriftmodel::ADLChargeDriftModel)::Array{SVector{3,T},3} where {T<:AbstractFloat}
    df = Array{SVector{3,T}, 3}(undef, size(ef))

    cdm = begin
        cdmf64 = chargedriftmodel
        e100 = VelocityParameters{T}(cdmf64.electrons.axis100.mu0, cdmf64.electrons.axis100.beta, cdmf64.electrons.axis100.E0, cdmf64.electrons.axis100.mun)
        e111 = VelocityParameters{T}(cdmf64.electrons.axis111.mu0, cdmf64.electrons.axis111.beta, cdmf64.electrons.axis111.E0, cdmf64.electrons.axis111.mun)
        h100 = VelocityParameters{T}(cdmf64.holes.axis100.mu0, cdmf64.holes.axis100.beta, cdmf64.holes.axis100.E0, cdmf64.holes.axis100.mun)
        h111 = VelocityParameters{T}(cdmf64.holes.axis111.mu0, cdmf64.holes.axis111.beta, cdmf64.holes.axis111.E0, cdmf64.holes.axis111.mun)
        electrons = CarrierParameters{T}(e100, e111)
        holes     = CarrierParameters{T}(h100, h111)
        phi110::T = cdmf64.phi110
        gammas = SVector{4, SArray{Tuple{3,3},T,2,9}}( cdmf64.gammas )
        temperaturemodel::TemperatureModels{T} = cdmf64.temperaturemodel
        ADLChargeDriftModel{T}(electrons, holes, phi110, gammas, temperaturemodel)
    end

    @fastmath function getVe(fv::SVector{3, T}, gammas::SVector{4, SMatrix{3,3,T}})::SVector{3, T} where {T <: AbstractFloat}
        @inbounds begin
            Emag::T = norm(fv)
            Emag_inv::T = inv(Emag)

            Emag_threshold::T = 1e-5

            tmp0::T = 2.888470213
            tmp1::T = -1.182108256
            tmp2::T = 3.160660533
            tmp3::T = 0.25

            if Emag < Emag_threshold
                return SVector{3,T}(0, 0, 0)
            end

            f = scale_to_given_temperature(temperaturemodel)
            f100e::T = f[1]
            f111e::T = f[2]

            V100e::T = Vl(Emag, cdm.electrons.axis100) * f100e
            V111e::T = Vl(Emag, cdm.electrons.axis111) * f111e

            AE::T = V100e / tmp0
            RE::T = tmp1 * V111e / AE + tmp2

            e0 = SVector{3, T}(fv * Emag_inv)

            oneOverSqrtEgE::SVector{4, T} = [1 / sqrt( gammas[j] * e0 ⋅ e0 ) for j in eachindex(1:4)] # setup.gammas[j] * e0 ⋅ e0 -> causes allocations

            g0 = MVector{3, T}(0,0,0)
            for j in eachindex(1:4)
                NiOverNj::T = RE * (oneOverSqrtEgE[j] / sum(oneOverSqrtEgE) - tmp3) + tmp3
                g0 += gammas[j] * e0 * NiOverNj * oneOverSqrtEgE[j]
            end

            return g0 * -AE
        end
    end
    for i in eachindex(df)
        @inbounds df[i] = getVe(ef[i], cdm.gammas)
    end

    return df
end

# Hole model parametrization from [1] equations (22)-(26)
@fastmath function k0func(vrel::T)::T where {T <: AbstractFloat}
    p0::T = 9.2652
    p1::T = 26.3467
    p2::T = 29.6137
    p3::T = 12.3689
    return @fastmath p0 - p1 * vrel + p2 * vrel^2 - p3 * vrel^3
end

@fastmath function lambda(k0::T)::T where {T <: AbstractFloat}
    p0::T = -0.01322
    p1::T = 0.41145
    p2::T = 0.23657
    p3::T = 0.04077
    return @fastmath p0 * k0 + p1 * k0^2 - p2 * k0^3 + p3 * k0^4
end

@fastmath function omega(k0::T)::T where {T <: AbstractFloat}
    p0::T = 0.006550
    p1::T = 0.19946
    p2::T = 0.09859
    p3::T = 0.01559
    return @fastmath p0 * k0 - p1 * k0^2 + p2 * k0^3 - p3 * k0^4
end


function get_hole_drift_field(ef::Array{SVector{3,T},3}, chargedriftmodel::ADLChargeDriftModel)::Array{SVector{3,T},3} where {T<:AbstractFloat}
    df = Array{SVector{3,T}, 3}(undef, size(ef))

    cdm = begin
        cdmf64 = chargedriftmodel
        e100 = VelocityParameters{T}(cdmf64.electrons.axis100.mu0, cdmf64.electrons.axis100.beta, cdmf64.electrons.axis100.E0, cdmf64.electrons.axis100.mun)
        e111 = VelocityParameters{T}(cdmf64.electrons.axis111.mu0, cdmf64.electrons.axis111.beta, cdmf64.electrons.axis111.E0, cdmf64.electrons.axis111.mun)
        h100 = VelocityParameters{T}(cdmf64.holes.axis100.mu0, cdmf64.holes.axis100.beta, cdmf64.holes.axis100.E0, cdmf64.holes.axis100.mun)
        h111 = VelocityParameters{T}(cdmf64.holes.axis111.mu0, cdmf64.holes.axis111.beta, cdmf64.holes.axis111.E0, cdmf64.holes.axis111.mun)
        electrons = CarrierParameters{T}(e100, e111)
        holes     = CarrierParameters{T}(h100, h111)
        phi110::T = cdmf64.phi110
        gammas = SVector{4, SArray{Tuple{3,3},T,2,9}}( cdmf64.gammas )
        temperaturemodel::TemperatureModels{T} = cdmf64.temperaturemodel
        ADLChargeDriftModel{T}(electrons, holes, phi110, gammas, temperaturemodel)
    end

    Emag_threshold::T = 1e-5

    @fastmath function getVh(fv::SVector{3,T}, Emag_threshold::T)::SVector{3,T} where {T <: AbstractFloat}
        @inbounds begin
            Emag::T = norm(fv)
            Emag_inv::T = inv(Emag)

            if Emag < Emag_threshold
                return SVector{3,T}(0, 0, 0)
            end

            f = scale_to_given_temperature(temperaturemodel)
            f100h::T = f[3]
            f111h::T = f[4]

            V100h::T = Vl(Emag, cdm.holes.axis100) * f100h
            V111h::T = Vl(Emag, cdm.holes.axis111) * f111h

            b::T = -π / 4 - cdm.phi110
            Rz = SMatrix{3, 3, T}(cos(b), sin(b), 0, -sin(b), cos(b), 0, 0, 0, 1)
            a = Rz * fv

            theta0::T = acos(a[3] / Emag)
            phi0::T = atan(a[2], a[1])

            k0::T = k0func(V111h / V100h)

            vtmp = MVector{3, T}(0, 0, 0) ## from CITATION; The implementation here is correct, mistake in the CITATION
            vtmp[3] = V100h * ( 1 - lambda(k0) * (sin(theta0)^4 * sin(2 * phi0)^2 + sin(2 * theta0)^2) )
            vtmp[1] = V100h * omega(k0) * (2 * sin(theta0)^3 * cos(theta0) * sin(2 * phi0)^2 + sin(4 * theta0))
            vtmp[2] = V100h * omega(k0) * sin(theta0)^3 * sin(4 * phi0)

            Ry = SMatrix{3, 3, T}(cos(theta0),0,-sin(theta0), 0,1,0, sin(theta0),0,cos(theta0))
            b = phi0 + pi/4 + cdm.phi110
            Rz = SMatrix{3,3, T}(cos(b),sin(b),0, -sin(b),cos(b),0, 0,0,1)
            vtmp = Rz * (Ry * vtmp)

            return vtmp
        end
    end

    for i in eachindex(df)
        @inbounds df[i] = getVh(ef[i], Emag_threshold)
    end

    return df
end

function println(io::IO, tm::VacuumModel{T}) where {T <: AbstractFloat}
    print("No temperature model defined")
end

function println(io::IO, tm::BoltzmannModel{T}) where {T <: AbstractFloat}
    println("\n________BoltzmannModel________")
    println("Fit function: p1 + p2 exp(-p3/T)\n")
    println("---Temperature settings---")
    println("Crystal temperature:   \t $(tm.temperature)")
    println("Reference temperature: \t $(tm.reftemperature)\n")

    println("---Fitting parameters---")
    println("   \te100      \te111      \th100      \th111")
    println("p1 \t$(tm.p1e100)   \t$(tm.p1e111)   \t$(tm.p1h100)   \t$(tm.p1h111)")
    println("p2 \t$(tm.p2e100)   \t$(tm.p2e111)   \t$(tm.p2h100)   \t$(tm.p2h111)")
    println("p3 \t$(tm.p3e100)   \t$(tm.p3e111)   \t$(tm.p3h100)   \t$(tm.p3h111)")
end

function println(io::IO, tm::LinearModel{T}) where {T <: AbstractFloat}
    println("\n________LinearModel________")
    println("Fit function: p1 + p2 * T\n")
    println("---Temperature settings---")
    println("Crystal temperature:  \t$(tm.temperature)")
    println("Reference temperature:\t$(tm.reftemperature)\n")

    println("---Fitting parameters---")
    println("   \te100      \te111      \th100      \th111")
    println("p1 \t$(tm.p1e100)   \t$(tm.p1e111)   \t$(tm.p1h100)   \t$(tm.p1h111)")
    println("p2 \t$(tm.p2e100)   \t$(tm.p2e111)   \t$(tm.p2h100)   \t$(tm.p2h111)")
end

function println(io::IO, tm::PowerLawModel{T}) where {T <: AbstractFloat}
    println("\n________PowerLawModel________")
    println("Fit function: p1 * T^(3/2)\n")
    println("---Temperature settings---")
    println("Crystal temperature:   \t $(tm.temperature)")
    println("Reference temperature: \t $(tm.reftemperature)\n")

    println("---Fitting parameters---")
    println("   \te100      \te111      \th100      \th111")
    println("p1 \t$(tm.p1e100)   \t$(tm.p1e111)   \t$(tm.p1h100)   \t$(tm.p1h111)")
end


function show(io::IO, tm::SSD.TemperatureModels{T}) where {T <: AbstractFloat} println(tm) end
function print(io::IO, tm::SSD.TemperatureModels{T}) where {T <: AbstractFloat} println(tm) end
function display(io::IO, tm::SSD.TemperatureModels{T}) where {T <: AbstractFloat} println(tm) end
function show(io::IO,::MIME"text/plain", tm::SSD.TemperatureModels{T}) where {T <: AbstractFloat}
    show(io, tm)
end



### END: ADL Charge Drift Model
###############################

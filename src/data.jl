using CSV
using DataFrames

struct FarmData
    blocks::DataFrame
    crops::DataFrame
    yields::DataFrame
    calendar::DataFrame
    labour::DataFrame
    water::DataFrame
    markets::DataFrame
    parameters::Dict{String, Float64}
    initial_areas::DataFrame
end

function read_parameters(path::AbstractString)
    table = CSV.read(path, DataFrame)
    return Dict(row.parameter => Float64(row.value) for row in eachrow(table))
end

function load_data(data_dir::AbstractString = joinpath(@__DIR__, "..", "data"))
    return FarmData(
        CSV.read(joinpath(data_dir, "blocks.csv"), DataFrame),
        CSV.read(joinpath(data_dir, "crops.csv"), DataFrame),
        CSV.read(joinpath(data_dir, "yields.csv"), DataFrame),
        CSV.read(joinpath(data_dir, "calendar.csv"), DataFrame),
        CSV.read(joinpath(data_dir, "labour.csv"), DataFrame),
        CSV.read(joinpath(data_dir, "water.csv"), DataFrame),
        CSV.read(joinpath(data_dir, "markets.csv"), DataFrame),
        read_parameters(joinpath(data_dir, "parameters.csv")),
        CSV.read(joinpath(data_dir, "initial_areas.csv"), DataFrame),
    )
end
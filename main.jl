6+import MathOptInterface as MOI

include(joinpath(@__DIR__, "src", "data.jl"))
include(joinpath(@__DIR__, "src", "model.jl"))

function print_part_a_solution(data::FarmData, solution::PartAModel)
    blocks = String.(data.blocks.block)
    crops = String.(data.crops.crop)
    periods = String.(data.water.period)

    println("Status: ", termination_status(solution.model))
    println("Optimal gross margin: ", round(objective_value(solution.model), digits = 2), " EUR")

    println("\nCropping plan (ha):")
    for block in blocks
        allocations = ["$(crop)=$(round(value(solution.area[block, crop]), digits=3))" for crop in crops
                       if value(solution.area[block, crop]) > 1e-6]
        println("  ", block, ": ", join(allocations, ", "))
    end

    println("\nWater balance:")
    println("  period       pumping (m3)   reservoir end (m3)")
    for period in periods
        println("  ", rpad(period, 14), lpad(round(value(solution.pump[period]), digits=2), 12),
            lpad(round(value(solution.reservoir[period]), digits=2), 20))
    end
    println("  annual pumping: ", round(sum(value(solution.pump[period]) for period in periods), digits=2), " m3")

    println("\nHired labour:")
    for period in periods
        println("  ", period, ": ", round(value(solution.hired[period]), digits=2), " h")
    end

    println("\nPotentially exhausted resources (within tolerance):")
    for period in periods
        labour_limit = data.labour[data.labour.period .== period, :family_hours][1] +
            data.labour[data.labour.period .== period, :hired_hours_cap][1]
        println("  ", period, " pump cap: ", isapprox(value(solution.pump[period]),
            data.water[data.water.period .== period, :pumping_cap_m3][1]; atol=1e-5),
            ", labour capacity: ", isapprox(value(solution.hired[period]),
            data.labour[data.labour.period .== period, :hired_hours_cap][1]; atol=1e-5))
    end
    println("  annual pumping licence: ", isapprox(sum(value(solution.pump[period]) for period in periods),
        data.parameters["abstraction_licence"]; atol=1e-5))
end

data = load_data()
solution = build_part_a(data)
optimize!(solution.model)
if termination_status(solution.model) == MOI.OPTIMAL
    print_part_a_solution(data, solution)
else
    error("The Part A model did not solve to optimality: $(termination_status(solution.model))")
end
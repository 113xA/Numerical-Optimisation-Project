import MathOptInterface as MOI

include(joinpath(@__DIR__, "src", "data.jl"))
include(joinpath(@__DIR__, "src", "model.jl"))

function print_solution_header(solution::PartAModel)
    println("Status: ", termination_status(solution.model))
    println("Optimal gross margin: ", round(objective_value(solution.model), digits = 2), " EUR")
end

function print_cropping_plan(data::FarmData, solution::PartAModel)
    blocks = String.(data.blocks.block)
    crops = String.(data.crops.crop)

    println("\nCropping plan (ha):")
    for block in blocks
        allocations = ["$(crop)=$(round(value(solution.area[block, crop]), digits=3))" for crop in crops
                       if value(solution.area[block, crop]) > 1e-6]
        println("  ", block, ": ", join(allocations, ", "))
    end
end

function print_water_balance(data::FarmData, solution::PartAModel)
    periods = String.(data.water.period)

    println("\nWater balance:")
    println("  period       pumping (m3)   reservoir end (m3)")
    for period in periods
        println("  ", rpad(period, 14), lpad(round(value(solution.pump[period]), digits=2), 12),
            lpad(round(value(solution.reservoir[period]), digits=2), 20))
    end
    println("  annual pumping: ", round(sum(value(solution.pump[period]) for period in periods), digits=2), " m3")
end

function print_labour_summary(data::FarmData, solution::PartAModel)
    periods = String.(data.water.period)

    println("\nHired labour:")
    for period in periods
        println("  ", period, ": ", round(value(solution.hired[period]), digits=2), " h")
    end
end

function print_binding_checks(data::FarmData, solution::PartAModel)
    periods = String.(data.water.period)

    println("\nPotentially exhausted resources (within tolerance):")
    for period in periods
        family_hours = data.labour[data.labour.period .== period, :family_hours][1]
        hired_cap = data.labour[data.labour.period .== period, :hired_hours_cap][1]
        pump_cap = data.water[data.water.period .== period, :pumping_cap_m3][1]
        labour_usage_ok = isapprox(value(solution.hired[period]), hired_cap; atol=1e-5)

        println("  ", period,
            " pump cap: ", isapprox(value(solution.pump[period]), pump_cap; atol=1e-5),
            ", labour capacity: ", labour_usage_ok,
            ", family hours available: ", round(family_hours, digits = 2))
    end
    println("  annual pumping licence: ", isapprox(sum(value(solution.pump[period]) for period in periods),
        data.parameters["abstraction_licence"]; atol=1e-5))
end

function print_part_a_solution(data::FarmData, solution::PartAModel)
    print_solution_header(solution)
    print_cropping_plan(data, solution)
    print_water_balance(data, solution)
    print_labour_summary(data, solution)
    print_binding_checks(data, solution)
end

function run_part_a()
    # Input block: load data and build the model
    data = load_data()
    solution = build_part_a(data)

    # Solve block: optimize the JuMP model
    optimize!(solution.model)

    # Output block: print only if the solver reached optimality
    if termination_status(solution.model) == MOI.OPTIMAL
        print_part_a_solution(data, solution)
    else
        error("The Part A model did not solve to optimality: $(termination_status(solution.model))")
    end
end

run_part_a()
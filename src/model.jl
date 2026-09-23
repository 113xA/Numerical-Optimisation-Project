using JuMP
using Gurobi

struct PartAModel
    model::Model
    area
    pump
    reservoir
    spill
    hired
    contracted_sales
    spot_sales
end

function value_or_zero(value)
    return ismissing(value) ? 0.0 : Float64(value)
end

function prepare_part_a_inputs(data::FarmData)
    return (
        blocks = String.(data.blocks.block),
        crops = String.(data.crops.crop),
        periods = String.(data.water.period),
        block_area = Dict(String(row.block) => Float64(row.area_ha) for row in eachrow(data.blocks)),
        soil_class = Dict(String(row.block) => String(row.soil_class) for row in eachrow(data.blocks)),
        crop_rows = Dict(String(row.crop) => row for row in eachrow(data.crops)),
        market_rows = Dict(String(row.crop) => row for row in eachrow(data.markets)),
        water_rows = Dict(String(row.period) => row for row in eachrow(data.water)),
        labour_rows = Dict(String(row.period) => row for row in eachrow(data.labour)),
        yield_value = Dict(
            (String(row.crop), String(row.soil_class)) => Float64(row.yield_t_per_ha)
            for row in eachrow(data.yields)
        ),
        irrigation = Dict(
            (String(row.crop), String(row.period)) => Float64(row.irrigation_m3_per_ha)
            for row in eachrow(data.calendar)
        ),
        labour_need = Dict(
            (String(row.crop), String(row.period)) => Float64(row.labour_h_per_ha)
            for row in eachrow(data.calendar)
        ),
    )
end

function create_part_a_model(output::Bool)
    model = Model(Gurobi.Optimizer)
    set_silent(model)
    set_optimizer_attribute(model, "DualReductions", 0)
    if !output
        set_optimizer_attribute(model, "OutputFlag", 0)
    end
    return model
end

function add_land_constraints!(model, blocks, crops, block_area, total_area, crop_rows, area, data)
    @constraint(model, land_balance[block in blocks], sum(area[block, crop] for crop in crops) == block_area[block])
    @constraint(model, crop_share[crop in crops], sum(area[block, crop] for block in blocks) <=
        Float64(crop_rows[crop].max_farm_share) * total_area)
    @constraint(model, non_productive,
        sum(area[block, crop] for block in blocks for crop in crops
            if Bool(crop_rows[crop].is_non_productive)) >= data.parameters["non_productive_share"] * total_area)
end

function add_market_constraints!(model, crops, market_rows, production, contracted_sales, spot_sales)
    marketed_crops = [crop for crop in crops if haskey(market_rows, crop)]
    @constraint(model, sales_balance[crop in marketed_crops], contracted_sales[crop] + spot_sales[crop] == production[crop])

    for crop in crops
        if !haskey(market_rows, crop)
            @constraint(model, contracted_sales[crop] == 0)
            @constraint(model, spot_sales[crop] == 0)
            continue
        end

        market = market_rows[crop]
        contract_min = value_or_zero(market.contract_min_t)
        contract_max = market.contract_max_t
        @constraint(model, contracted_sales[crop] >= contract_min)

        if ismissing(contract_max)
            @constraint(model, spot_sales[crop] == 0)
        else
            @constraint(model, contracted_sales[crop] <= Float64(contract_max))
        end
    end
end

function add_resource_constraints!(model, periods, water_rows, labour_rows, irrigation_use, labour_use, initial_level, capacity, pump, reservoir, spill, hired, data)
    previous_level = initial_level
    for period in periods
        row = water_rows[period]
        @constraint(model, reservoir[period] == previous_level + Float64(row.reservoir_inflow_m3) +
            pump[period] - irrigation_use[period] - spill[period])
        @constraint(model, reservoir[period] <= capacity)
        @constraint(model, pump[period] <= Float64(row.pumping_cap_m3))
        @constraint(model, labour_use[period] <= labour_rows[period].family_hours + hired[period])
        @constraint(model, hired[period] <= labour_rows[period].hired_hours_cap)
        previous_level = reservoir[period]
    end

    @constraint(model, annual_pumping, sum(pump[period] for period in periods) <= data.parameters["abstraction_licence"])
    @constraint(model, terminal_reservoir, reservoir[last(periods)] >= data.parameters["reservoir_terminal"])
end

function add_objective!(model, blocks, crops, periods, market_rows, crop_rows, labour_rows, area, contracted_sales, spot_sales, pump, hired, data)
    revenue = sum(
        haskey(market_rows, crop) ?
        contracted_sales[crop] * Float64(market_rows[crop].price_EUR_per_t) +
        spot_sales[crop] * value_or_zero(market_rows[crop].spot_price_EUR_per_t) : 0
        for crop in crops
    )
    variable_cost = sum(area[block, crop] * Float64(crop_rows[crop].variable_cost_EUR_per_ha)
                        for block in blocks for crop in crops)
    hired_cost = sum(hired[period] * Float64(labour_rows[period].hired_cost_EUR_per_h) for period in periods)
    pumping_cost = sum(pump[period] for period in periods) * data.parameters["pumping_cost"]
    @objective(model, Max, revenue - variable_cost - hired_cost - pumping_cost)
end

function build_part_a(data::FarmData; output::Bool = true)
    inputs = prepare_part_a_inputs(data)
    blocks = inputs.blocks
    crops = inputs.crops
    periods = inputs.periods
    block_area = inputs.block_area
    soil_class = inputs.soil_class
    crop_rows = inputs.crop_rows
    market_rows = inputs.market_rows
    water_rows = inputs.water_rows
    labour_rows = inputs.labour_rows
    yield_value = inputs.yield_value
    irrigation = inputs.irrigation
    labour_need = inputs.labour_need

    model = create_part_a_model(output)

    # Decision variables
    @variable(model, area[blocks, crops] >= 0)
    @variable(model, pump[periods] >= 0)
    @variable(model, reservoir[periods] >= 0)
    @variable(model, spill[periods] >= 0)
    @variable(model, hired[periods] >= 0)
    @variable(model, contracted_sales[crops] >= 0)
    @variable(model, spot_sales[crops] >= 0)

    total_area = sum(block_area[block] for block in blocks)
    capacity = data.parameters["reservoir_capacity"]
    initial_level = data.parameters["reservoir_initial"]

    # Constraints: land use
    add_land_constraints!(model, blocks, crops, block_area, total_area, crop_rows, area, data)

    # Derived production and sales
    production = Dict(crop => sum(area[block, crop] * yield_value[(crop, soil_class[block])] for block in blocks)
                      for crop in crops)
    add_market_constraints!(model, crops, market_rows, production, contracted_sales, spot_sales)

    # Constraints: irrigation and labour use
    irrigation_use = Dict(period => sum(area[block, crop] * irrigation[(crop, period)]
        for block in blocks for crop in crops) for period in periods)
    labour_use = Dict(period => sum(area[block, crop] * labour_need[(crop, period)]
        for block in blocks for crop in crops) for period in periods)

    add_resource_constraints!(model, periods, water_rows, labour_rows, irrigation_use, labour_use, initial_level, capacity, pump, reservoir, spill, hired, data)

    # Objective
    add_objective!(model, blocks, crops, periods, market_rows, crop_rows, labour_rows, area, contracted_sales, spot_sales, pump, hired, data)

    return PartAModel(model, area, pump, reservoir, spill, hired, contracted_sales, spot_sales)
end
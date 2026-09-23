# Numerical Optimisation Project

This repository contains a farm-planning optimization model written in Julia. It uses [JuMP](https://jump.dev/JuMP.jl/stable/) with the Gurobi solver to choose crop allocations, irrigation pumping, hired labour, and crop sales in order to maximize annual gross margin while respecting land, water, labour, and market constraints.

## Project Structure

The code is intentionally split into three parts:

- `main.jl` is the executable entry point. It loads the data, builds the model, solves it, and prints the result.
- `src/data.jl` reads the CSV inputs and stores them in a single `FarmData` structure.
- `src/model.jl` defines the JuMP model, its variables, constraints, and objective.
- `data/` contains the input tables used by the model.

## What The Model Does

The optimization problem assigns each block of land to crops, then decides how much to pump, store, spill, hire, and sell. The goal is to maximize profit while satisfying the farm’s physical and economic limits.

At a high level, the model answers these questions:

- How much area of each crop should be planted on each block?
- How much water should be pumped in each period?
- How much water remains in the reservoir after each period?
- How much labour must be hired when family labour is not enough?
- How much of each crop should be sold under contract or on the spot market?

## Input Data

The model reads several CSV files from `data/`:

- `blocks.csv`: land blocks, their size, and soil class.
- `crops.csv`: crop-level parameters such as variable cost, farm share limits, and flags for special crop types.
- `yields.csv`: yield by crop and soil class.
- `calendar.csv`: crop requirements by period, including irrigation need and labour need.
- `labour.csv`: family labour availability, hired labour capacity, and hired labour cost by period.
- `water.csv`: inflows, pumping caps, and reservoir information by period.
- `markets.csv`: prices and contract information for marketable crops.
- `parameters.csv`: global constants such as reservoir capacity, reservoir initial level, and pumping cost.
- `initial_areas.csv`: initial crop areas, kept as an input file even though it is not used in the current Part A model.

## Data Layer

`src/data.jl` defines:

```julia
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
```

This structure groups all input tables into one object so the model builder can access them consistently.

Two helper functions are defined there:

- `read_parameters(path)`: reads `parameters.csv` and converts it into a `Dict{String, Float64}`.
- `load_data(data_dir)`: loads all CSV files and returns a populated `FarmData` object.

## Model Layer

`src/model.jl` contains the optimization model for Part A.

### `PartAModel`

The solver output is wrapped in:

```julia
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
```

This keeps the JuMP model together with the main decision variables so the solution can be printed later.

### Helper Function

`value_or_zero(value)` converts missing market values to `0.0`. This is used for optional CSV fields such as contract minima or spot prices.

## Decision Variables

The model creates these variables:

- `area[block, crop]`: hectares of each crop planted on each block.
- `pump[period]`: water pumped in each period.
- `reservoir[period]`: reservoir level at the end of each period.
- `spill[period]`: water spilled in each period.
- `hired[period]`: hired labour in each period.
- `contracted_sales[crop]`: crop volume sold under contract.
- `spot_sales[crop]`: crop volume sold on the spot market.

All of them are nonnegative.

## Objective Function

The model maximizes gross margin:

$$
\max \; \text{revenue} - \text{variable crop cost} - \text{hired labour cost} - \text{pumping cost}
$$

Revenue is built from:

- contracted sales at the contract price,
- spot sales at the spot price when a spot market exists.

Costs include:

- crop-specific variable costs per hectare,
- hired labour cost per hour,
- pumping cost per cubic metre.

## Constraints

### 1. Land balance

Each block must be fully assigned across crops:

$$
\sum_{c} \text{area}_{b,c} = \text{block area}_b
$$

### 2. Crop share limits

Each crop has a farm-wide maximum share of total land.

### 3. Non-productive share

The farm must keep at least a minimum share of land in non-productive use.

### 4. Sales balance

For crops that have a market row, production must be split between contract sales and spot sales:

$$
\text{contracted sales}_c + \text{spot sales}_c = \text{production}_c
$$

### 5. Contract rules

Depending on the crop, the model may impose:

- a minimum contracted volume,
- a maximum contracted volume,
- zero spot sales if no spot market exists.

### 6. Reservoir dynamics

For each period, reservoir levels follow the water balance:

$$
R_t = R_{t-1} + \text{inflow}_t + \text{pump}_t - \text{irrigation use}_t - \text{spill}_t
$$

The reservoir is also bounded by its capacity.

### 7. Pumping cap

Pump volume in each period cannot exceed the period-specific pumping capacity.

### 8. Labour balance

Crop labour requirements must be covered by family labour plus hired labour.

### 9. Hired labour cap

The hired labour decision is limited by the period-specific hiring cap.

### 10. Annual pumping licence

The total pumped volume over all periods cannot exceed the annual abstraction licence.

### 11. Terminal reservoir condition

The final reservoir level must be at least the required terminal level.

## Main Script

`main.jl` wires everything together:

1. It includes `src/data.jl` and `src/model.jl`.
2. It loads the input data with `load_data()`.
3. It builds the Part A model with `build_part_a(data)`.
4. It solves the model with `optimize!(solution.model)`.
5. If the solver finds an optimal solution, it prints a summary with `print_part_a_solution`.

The printed summary includes:

- solver status,
- optimal gross margin,
- crop allocation per block,
- water balance by period,
- hired labour by period,
- and a few binding or nearly binding resource limits.

## How To Run

From the project root:

```bash
julia --project=. main.jl
```

Gurobi must be installed and licensed on your machine for the model to solve successfully.

## Notes

- The current implementation focuses on Part A of the project.
- `initial_areas.csv` is loaded but not used yet in the Part A model.
- The code is written so that the data layer and model layer can be extended later without changing the overall workflow.
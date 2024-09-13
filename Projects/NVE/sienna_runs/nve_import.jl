using Pkg
using PowerSystems
using PowerSimulations
using PowerSystemCaseBuilder
using HydroPowerSimulations
using StorageSystemsSimulations
using PowerGraphics
using HiGHS # solver
using Gurobi # solver
using Dates
using Logging
using DataFrames
using Plots
using CSV

## Load and Save System From Parse R2X Data
logger = configure_logging(console_level=Logging.Warn)
data_dir = "Projects/NVE/output/"
base_power = 1.0
descriptors = "Projects/NVE/sienna_runs/user_descriptors.yaml"
generator_mapping = "Projects/NVE/sienna_runs/generator_mapping.yaml"
timeseries_metadata_file = "Projects/NVE/output/timeseries_pointers.json"
data = PowerSystemTableData(
    data_dir,
    base_power,
    descriptors;
    generator_mapping_file = generator_mapping,
    timeseries_metadata_file = timeseries_metadata_file,
)
sys = System(data, time_series_in_memory= true)

# Save the system
path = "Projects/NVE/sienna_runs/nve_system.json"
# to_json(sys, path, force=true)

###########
# Open System
##########
# sys = System(path)
get_units_base(sys)
# set_units_base_system!(sys, "NATURAL_UNITS")

buses = collect(get_components(ACBus, sys));
loads = collect(get_components(PowerLoad, sys));
lines = collect(get_components(Line, sys));
arcs = collect(get_components(Arc, sys));
gens_thermal = collect(get_components(ThermalStandard, sys));
gens_renew = collect(get_components(RenewableDispatch, sys));
reserves = collect(get_components(VariableReserve{ReserveUp}, sys));

# get_time_series_array( SingleTimeSeries, get_component(ThermalStandard,sys, "Tracy 4&5 CC"), "fuel_price")
get_time_series_array( SingleTimeSeries, get_component( RenewableDispatch ,sys, "Fish Springs Ranch Solar"), "max_active_power")
get_time_series_array( SingleTimeSeries, get_component( PowerLoad ,sys, "Sierra"), "max_active_power")

#####
# Modify System
#####
# active_power_sum = 0.0
# for g in get_components(RenewableDispatch, sys)
#     # set_active_power_limits!(g, (min=0.0, max=get_active_power(g)*20))
#     active_power_sum += get_active_power(g)
# end


# Set market purchases availability to false
set_available!(get_component(ThermalStandard, sys, "Southern Purchases (NVP)"), false)
set_available!(get_component(ThermalStandard, sys, "Northern Purchases (Sierra)"), false)

set_bustype!(get_component(ACBus, sys, "Sierra"), "REF")
transform_single_time_series!(sys, Hour(24), Hour(24))


#######
# Adding MarketBidCost to Generators
#######
# Loading fuel_price data
fuel_price_path = data_dir * "Data/ThermalStandard_fuel_price__2030.csv"
fuel_price = DataFrame(CSV.File(fuel_price_path))

# # datetime_col = fuel_price.DateTime
# for column in names(fuel_price)
#     if column != "DateTime"
#         gen = get_component(ThermalStandard, sys, column)
#         fp_data = fuel_price[!, gen_name]
#         oc = get_operation_cost(gen)
#         vc = get_value_curve(get_variable(oc))
#         function_data = get_function_data(vc)
#         constant_term = get_constant_term(function_data)
#         proportional_term = get_proportional_term(function_data)
        
#         power = get_active_power(gen) #need to check if max_active_power ts is set, use that instead if solve
#         powers = ones(length(fp_data)) * power
#         mc_data = proportional_term * fp_data
#         market_curve = make_market_bid_curve(powers, mc_data)
        
#         mbc =MarketBidCost(no_load_cost= 0, start_up=0, shut_down =0, incremental_offer_curves = market_curve)
#         set_operation_cost!(gen, mbc)
#     end
# end

# Test MarketBidCost Example
gen_name = "Nevada Cogen 2"
gen = get_component(ThermalStandard, sys, gen_name)

# First gather existing data on generator operation_cost
fp_data = fuel_price[!, gen_name]
oc = get_operation_cost(gen)
vc = get_value_curve(get_variable(oc))
function_data = get_function_data(vc)
constant_term = get_constant_term(function_data)
proportional_term = get_proportional_term(function_data)

# Set MarketBidCost Structure with empty variable_cost
mbc = MarketBidCost(
        no_load_cost= 0,
        start_up=0, 
        shut_down =0, 
    )
set_operation_cost!(gen, mbc)

# Pass Market Bid Data to MarketBidCost
# PiecewiseIncrementalCurve(0.0, [0.0, 100.0, 105.0, 120.0, 130.0], [25.0, 26.0, 28.0, 30.0])

# Create MarketBidCurve
mc_data = proportional_term * fp_data

min_active_power = get_active_power_limits(gen)[1]
max_active_power = get_active_power_limits(gen)[2]
powers = [min_active_power, max_active_power]
offer_values = ones(length(powers)) * mc_data[1]

# market_curve = make_market_bid_curve_new(powers, offer_values)
market_curve = PiecewiseIncrementalCurve(0.0, [0.0, max_active_power], [mc_data[1]])
cost_curve = CostCurve(market_curve)

# Testing ways of adding to generator
# set_variable_cost!(sys, gen, cost_curve)

mbc = MarketBidCost(
        no_load_cost= 0,
        start_up=0, 
        shut_down =0, 
        incremental_offer_curves = cost_curve
    )
set_operation_cost!(gen, mbc)

get_operation_cost(gen)

# # Time varying data to submit bids as generators in the network
# market_bid_data = 
#     Dict(Dates.DateTime("2030-01-01") => [
#         PiecewiseStepData([min_active_power, 2.0, 3.0], [4.0, 6.0]),
#         PiecewiseStepData([min_active_power, 2.0, 6.0], [2.0, 12.0]),]
#     )

# time_series_data = Deterministic(
#            name = "variable_cost",
#            data = data,
#            resolution = Dates.Hour(1)
#        )

# set_variable_cost!(sys, gen, time_series_data)

##########
## Copper Plate Network Simulation
##########
template_uc = ProblemTemplate()

set_device_model!(template_uc, ThermalStandard, ThermalStandardUnitCommitment)
set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_uc, HydroDispatch, HydroDispatchRunOfRiver)
set_device_model!(template_uc, PowerLoad, StaticPowerLoad)

# set_service_model!( template_uc, VariableReserve{ReserveUp}, NonSpinningReserve)
# set_service_model!( template_uc, VariableReserve{ReserveUp}, RegulationReserve)
# set_service_model!( template_uc, VariableReserve{ReserveUp}, NonSpinningReserve)

set_network_model!(template_uc, NetworkModel(CopperPlatePowerModel; use_slacks = true))

# Build Model and Simulaiton
mod_ = DecisionModel(
    template_uc,
    sys;
    name = "UC",
    optimizer = optimizer_with_attributes(Gurobi.Optimizer),
    system_to_file = false,
    initialize_model = true,
    optimizer_solve_log_print = true,
    direct_mode_optimizer = true,
    rebuild_model = false,
    store_variable_names = true,
    calculate_conflict = true,
    # horizon=Hour(24),
)

sim_model = SimulationModels(
    decision_models = [mod_],
    )

sim_sequence = SimulationSequence(
    models = sim_model,
    )

sim = Simulation(
    name = "test-sim",
    steps = 14,
    models = sim_model,
    sequence = sim_sequence,
    simulation_folder = mktempdir(".", cleanup = true),
)

build!(sim; console_level = Logging.Info,)
execute!(sim, enable_progress_bar = true)

##########
# Read and Export Results for Comparison Notebooks
# https://nrel-sienna.github.io/PowerSimulations.jl/latest/modeler_guide/read_results/
##########
sim_results = SimulationResults(sim)
results = get_decision_problem_results(sim_results, "UC"); # UC stage result metadata

# Input Parameters
load_parameter = read_realized_parameter(results, "ActivePowerTimeSeriesParameter__PowerLoad")
renewable_parameter = read_realized_parameter(results, "ActivePowerTimeSeriesParameter__RenewableDispatch")

# Output Expressions
power_balance = read_realized_expression(results, "ActivePowerBalance__System")
pc_thermal = read_realized_expression(results, "ProductionCostExpression__ThermalStandard")

# Output Variables
thermal_active_power = read_realized_variable(results, "ActivePowerVariable__ThermalStandard")
renewable_active_power = read_realized_variable(results, "ActivePowerVariable__RenewableDispatch")
# Concatenate thermal and renewable active power by DateTime
gen_active_power = hcat(thermal_active_power, select(renewable_active_power, Not(1)))

# Export Dataframes to csv
CSV.write("Projects/NVE/sienna_runs/run_output/results/load_active_power.csv", load_parameter)
CSV.write("Projects/NVE/sienna_runs/run_output/results/generator_active_power.csv", gen_active_power)

# ### Post Process and Analyze Network results
# plot_dataframe(load)
# plot_dataframe(thermal_active_power)

# Export generation by fuel type
using PowerAnalytics
all_gen_data = PowerAnalytics.get_generation_data(results)
cat = PowerAnalytics.make_fuel_dictionary(sys)
fuel = PowerAnalytics.categorize_data(all_gen_data.data, cat; curtailment = true, slacks = true)
fuel_agg = PowerAnalytics.combine_categories(fuel)
CSV.write("Projects/NVE/sienna_runs/run_output/results/generation_by_fuel.csv", fuel_agg)





using PowerGraphics
plotlyjs()
plot_fuel(results; stair = true)

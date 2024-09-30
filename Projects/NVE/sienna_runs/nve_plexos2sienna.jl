
using Revise
using Pkg
using PowerSystems
using PowerSimulations
using PowerSystemCaseBuilder
using HydroPowerSimulations
using StorageSystemsSimulations
using PowerAnalytics
using PowerGraphics
using HiGHS # solver
using Gurobi # solver
using Dates
using Logging
using DataFrames
using Plots
using CSV
using TimeSeries

## Load and Save System From Parse R2X Data
logger = configure_logging(console_level=Logging.Info)
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

#############################################
# Modify System
#############################################

#########
# Convert Lines to AreaInterchanges
#########
branch_path = data_dir * "branch.csv"
area_interchange_data = DataFrame(CSV.File(branch_path))

# Our Network does not have Areas in the System. First we create Areas then assign Buses their respective Area
for bus in get_components(ACBus, sys)
    add_component!(sys, Area(name = get_name(bus)))
    set_area!(bus, get_component(Area, sys, get_name(bus)))
end

# In an AreaBalancePowerModel, a given area needs to have an AreaInterchange Objects that defines the Branch constraint between areas.
# Create new AreaInterchange for each Arc defined in the system
for line in get_components(Line, sys)
    arc = get_arc(line) # An Arc defines the topology of the network. Each line is assigned an Arc.
    from_bus = get_from(arc)
    to_bus = get_to(arc)
    add_component!(
        sys, 
        AreaInterchange(
            name = get_name(line),
            active_power_flow = 0.0,
            available = true,
            from_area = get_area(from_bus),
            to_area = get_area(to_bus),
            flow_limits = (
                from_to=  abs(area_interchange_data[area_interchange_data.name .== get_name(line), :rating_down][1]),
                to_from= abs(area_interchange_data[area_interchange_data.name .== get_name(line), :rating_up][1]),
                )
        )
    )
end
remove_component!(Area, sys, "nothing")

######
# Attach Reserve Requirements Timeseries 
######
reserve_path = data_dir * "reserve_req.csv"
df_reserve_req = DataFrame(CSV.File(reserve_path))
timestamps = range(DateTime("2030-01-01T00:00:00"), step = Hour(1), length = 8760)

#Convert the VariableReserve{ReserveUp} to a VariableReserveNonSpinning if the name contains string "NonSpinning"
for reserve in get_components(VariableReserve{ReserveUp}, sys)
    reserve_name = get_name(reserve)
    # if occursin("Non-Spin", reserve_name)
    #     remove_component!(VariableReserve{ReserveUp}, sys, get_name(reserve))
    #     VarRes = VariableReserveNonSpinning(
    #         name = reserve_name,
    #         available = true,
    #         time_frame = 0,
    #         requirement = 1.0,
    #     )
    #     add_component!(sys, VarRes)

    #     reserve_array = df_reserve_req[!, reserve_name]
    #     ta = TimeArray(timestamps, reserve_array)
    #     ts = SingleTimeSeries(
    #         name = "requirement",
    #         data = ta,
    #     )
    #     add_time_series!(sys, VarRes, ts)

    # Case Freq Regulation
    # else
        reserve_array = df_reserve_req[!, reserve_name]
        ta = TimeArray(timestamps, reserve_array)
        ts = SingleTimeSeries(
            name = "requirement",
            data = ta,
        )
        add_time_series!(sys, reserve, ts)
        set_requirement!(reserve, 1)
    # end
end



###########################
# Save/Load the System
###########################
path = "Projects/NVE/sienna_runs/nve_system.json"
# to_json(sys, path, force=true)
# sys = System(path)
####
# Inspect Data
####
get_units_base(sys)
# set_units_base_system!(sys, "NATURAL_UNITS")

buses = collect(get_components(ACBus, sys));
loads = collect(get_components(PowerLoad, sys));
lines = collect(get_components(Line, sys));
arcs = collect(get_components(Arc, sys));
areas = collect(get_components(Area, sys));
area_interchanges = collect(get_components(AreaInterchange, sys));
gens_thermal = collect(get_components(ThermalStandard, sys));
gens_renew = collect(get_components(RenewableDispatch, sys));
batteries = collect(get_components(EnergyReservoirStorage, sys));
reserves_spinning = collect(get_components(VariableReserve{ReserveUp}, sys));
reserves_non_spinning = collect(get_components(VariableReserveNonSpinning, sys));

# get_time_series_array( SingleTimeSeries, get_component(ThermalStandard,sys, "Tracy 4&5 CC"), "fuel_price")

# Enable all storage devices to participate in reserves
for storage in get_components(EnergyReservoirStorage, sys)
    # #concat the two vectors of services 
    # eligible_services = vcat(
    #     collect(get_components(VariableReserve{ReserveUp}, sys)), 
    #     # collect(get_components(VariableReserveNonSpinning, sys))
    #     )
    # set_services!(storage, eligible_services)
    set_initial_storage_capacity_level!(storage, 0.33)
end

# Set generator services (ie assign memberships)
for gen in get_components(ThermalStandard, sys)
    if !occursin("Purchases", get_name(gen))
        #concat the two vectors of services 
        eligible_services = vcat(
            collect(get_components(VariableReserve{ReserveUp}, sys)), 
            # collect(get_components(VariableReserveNonSpinning, sys))
            )
        set_services!(gen, eligible_services)
    end
end

# # Set generator services (ie assign memberships)
# for gen in get_components(RenewableDispatch, sys)
#     #concat the two vectors of services 
#     eligible_services = vcat(
#         collect(get_components(VariableReserve{ReserveUp}, sys)), 
#         )
#     set_services!(gen, eligible_services)
# end

######
# Artificially Constraint Imports
######
plexos_imports = data_dir * "plexos_imports.csv"
df_plexos_imports = DataFrame(CSV.File(plexos_imports))
timestamps = range(DateTime("2030-01-01T00:00:00"), step = Hour(1), length = 8760)

southern = get_component(ThermalStandard, sys, "Southern Purchases (NVP)")
northern = get_component(ThermalStandard, sys, "Northern Purchases (Sierra)")

names = ["Southern Purchases (NVP)", "Northern Purchases (Sierra)"]
for name in names
    thermal_gen = get_component(ThermalStandard, sys, name)
    set_available!(thermal_gen, false)

    renew_dispatch = RenewableDispatch(
        name = name,
        bus = get_bus(thermal_gen),
        available = true,
        rating = get_max_active_power(thermal_gen),
        active_power = 0.0,
        reactive_power = 0.0,
        operation_cost = get_operation_cost(gens_renew[1]),
        prime_mover_type = PrimeMovers.PVe,
        reactive_power_limits = (0.0, 0.0),
        power_factor = 1.0,
        base_power= 1.0,
    )
    add_component!(sys, renew_dispatch)
    import_limits = df_plexos_imports[!, name]
    ta = TimeArray(timestamps, import_limits)
    ts = SingleTimeSeries(
        name = "max_active_power",
        data = ta,
        # scaling_factor_multiplier = get_max_active_power
    )
    add_time_series!(sys, renew_dispatch, ts)
end



##############
## Additional network edits
##############
# Set market purchases availability to false
# set_available!(get_component(ThermalStandard, sys, "Southern Purchases (NVP)"), false)
# set_available!(get_component(ThermalStandard, sys, "Northern Purchases (Sierra)"), false)
southern = get_component(ThermalStandard, sys, "Southern Purchases (NVP)")
southern_op_cost = get_operation_cost(southern)

harry = get_component(ThermalStandard, sys, "Harry Allen 3")
harry_op_cost = get_operation_cost(harry)

new_vc = PiecewisePointCurve(
    [
        (35 , 682.0648711),
        (44.8, 682.1),
        (54.6, 712.2643009),
        (64.4, 796.2433112),
        (74.2, 928.1068642),
        (84, 1107.85496),
    ]
)

fuel_curve = FuelCurve(
    value_curve = new_vc, 
    fuel_cost = harry_op_cost.variable.fuel_cost
    )    
set_operation_cost!(harry, ThermalGenerationCost(variable = fuel_curve, fixed = 0, start_up = harry_op_cost.start_up, shut_down = harry_op_cost.shut_down))

set_available!(reserves_spinning[1], false)
set_available!(reserves_spinning[2], false)
set_available!(reserves_spinning[3], false)
set_available!(reserves_spinning[4], false)
set_available!(reserves_spinning[5], false)
set_available!(reserves_spinning[6], false)

# No Slack bus was created, set our own.
set_bustype!(get_component(ACBus, sys, "Sierra"), "REF")

transform_single_time_series!(sys, Hour(48), Hour(24))

############################################################
##  Network Simulation
############################################################
template_uc = ProblemTemplate()
set_device_model!(template_uc, ThermalStandard, ThermalStandardUnitCommitment)
set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_uc, HydroDispatch, HydroDispatchRunOfRiver)
set_device_model!(template_uc, PowerLoad, StaticPowerLoad)

storage_model = DeviceModel(
    EnergyReservoirStorage,
    StorageDispatchWithReserves;
    attributes = Dict(
        "reservation" => true, # True prevents discharging and charging in the same period
        "cycling_limits" => false,
        "energy_target" => false,
        "complete_coverage" => false,
        "regularization" => false, # Regularizes storage dispatch to prevent large swings in dispatch.
    ),
)
set_device_model!(template_uc, storage_model)

# set_service_model!(template_uc, ServiceModel(VariableReserveNonSpinning, NonSpinningReserve; use_slacks = true))
# set_service_model!(template_uc, ServiceModel(VariableReserve{ReserveUp}, RangeReserve; use_slacks = true))


# copper_plate = NetworkModel(
#         CopperPlatePowerModel,
#         use_slacks=true,
#         PTDF_matrix=PTDF(sys),
#         duals=[CopperPlateBalanceConstraint],
#     )
# set_network_model!(template_uc, copper_plate)

area_interchange = NetworkModel(
        AreaBalancePowerModel,
        use_slacks=false,
        # PTDF_matrix=PTDF(sys),
        # duals=[CopperPlateBalanceConstraint],
    )
set_device_model!(template_uc, AreaInterchange, StaticBranch) 
set_network_model!(template_uc, area_interchange)

# Build Decision Model and Simulaiton
UC_decision = DecisionModel(
    template_uc,
    sys;
    name = "lookahead_UC",
    optimizer = optimizer_with_attributes(Gurobi.Optimizer, "MIPGap" => 2e-2),
    system_to_file = false,
    initialize_model = true,
    optimizer_solve_log_print = true,
    direct_mode_optimizer = true,
    rebuild_model = false,
    store_variable_names = true,
    calculate_conflict = true,
    export_optimization_model = true,
)

sim_model = SimulationModels(
    decision_models = [UC_decision],
    )

sim_sequence = SimulationSequence(
    models = sim_model,
    )

sim = Simulation(
    name = "test-sim",
    steps = 5,  # Step in your simulation
    models = sim_model,
    sequence = sim_sequence,
    simulation_folder = mktempdir("Projects/NVE/sienna_runs/run_output/simulation_files", cleanup = true),
)
#create this output simulation folder
build!(sim; console_level = Logging.Info,)
execute!(sim, enable_progress_bar = true)

################################################################################
# Read and Export Results for Comparison Notebooks
# https://nrel-sienna.github.io/PowerSimulations.jl/latest/modeler_guide/read_results/
################################################################################
sim_results = SimulationResults(sim)
results = get_decision_problem_results(sim_results, "lookahead_UC"); # UC stage result metadata

# Get Production Costs
pc_thermal = read_expression(results, "ProductionCostExpression__ThermalStandard")

pc_thermal = read_realized_expression(results, "ProductionCostExpression__ThermalStandard")
pc_renewable = read_realized_expression(results, "ProductionCostExpression__RenewableDispatch")
pc_hydro = read_realized_expression(results, "ProductionCostExpression__HydroDispatch")
all_pc = hcat(pc_thermal,select(pc_renewable, Not(1)), select(pc_hydro, Not(1)))

# Input Parameters
load_parameter = read_realized_parameter(results, "ActivePowerTimeSeriesParameter__PowerLoad")
renewable_parameter = read_realized_parameter(results, "ActivePowerTimeSeriesParameter__RenewableDispatch")

# Output Expressions
# power_balance = read_realized_expression(results, "ActivePowerBalance__System")
pc_thermal = read_realized_expression(results, "ProductionCostExpression__ThermalStandard")

# Output Variables
thermal_active_power = read_realized_variable(results, "ActivePowerVariable__ThermalStandard")
renewable_active_power = read_realized_variable(results, "ActivePowerVariable__RenewableDispatch")
gen_active_power = hcat(thermal_active_power, select(renewable_active_power, Not(1)))
tx_flow = read_realized_variable(results, "FlowActivePowerVariable__AreaInterchange")

storage_charge = read_realized_variable(results, "ActivePowerInVariable__EnergyReservoirStorage")
CSV.write("Projects/NVE/sienna_runs/run_output/results/storage_charge.csv", storage_charge)

# Export Dataframes to csv
CSV.write("Projects/NVE/sienna_runs/run_output/results/load_active_power.csv", load_parameter)
CSV.write("Projects/NVE/sienna_runs/run_output/results/renewable_parameters.csv", renewable_parameter)
CSV.write("Projects/NVE/sienna_runs/run_output/results/renewable_active_power.csv", renewable_active_power)
CSV.write("Projects/NVE/sienna_runs/run_output/results/generator_active_power.csv", gen_active_power)
CSV.write("Projects/NVE/sienna_runs/run_output/results/tx_flow.csv", tx_flow)
CSV.write("Projects/NVE/sienna_runs/run_output/results/production_costs.csv", all_pc)

# ### Post Process and Analyze Network results
# plot_dataframe(load)
# plot_dataframe(thermal_active_power)

# Export generation by fuel type
all_gen_data = PowerAnalytics.get_generation_data(results)
cat = PowerAnalytics.make_fuel_dictionary(sys)
fuel = PowerAnalytics.categorize_data(all_gen_data.data, cat; curtailment = true, slacks = true)
fuel_agg = PowerAnalytics.combine_categories(fuel)
CSV.write("Projects/NVE/sienna_runs/run_output/results/generation_by_fuel.csv", fuel_agg)

gen_active_power[!, southern.name]

# Interactive Plot
plotlyjs()
plot_fuel(results; stair = true)


### get LMPS
network_dual = read_realized_dual(results, "CopperPlateBalanceConstraint__System")



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

# Single Generator MarketBidCost Example
gen_name = "Clark 14" # quadratic value curve
gen_name = "Clark 7, 8, 9_B" # linear value curve
gen = get_component(ThermalStandard, sys, gen_name)

# First gather existing data on generator operation_cost
fp_data = fuel_price[!, gen_name]
oc = get_operation_cost(gen)
vc = get_value_curve(get_variable(oc))
function_data = get_function_data(vc)
constant_term = get_constant_term(function_data) # zero
proportional_term = get_proportional_term(function_data)

# Set MarketBidCost Structure with empty variable_cost to populate with market bid data
mbc = MarketBidCost(
        no_load_cost= 0,
        start_up=0, 
        shut_down =0, 
    )
set_operation_cost!(gen, mbc)

# Pass Market Bid Data to MarketBidCost
# PiecewiseIncrementalCurve(0.0, [0.0, 100.0, 105.0, 120.0, 130.0], [25.0, 26.0, 28.0, 30.0])

# Create MarketBidCurve
# Single timestep example
mc_data = proportional_term * fp_data
min_active_power = get_active_power_limits(gen)[1]
max_active_power = get_active_power_limits(gen)[2]

market_curve = PiecewiseIncrementalCurve(constant_term, [min_active_power, max_active_power], [mc_data[1]])
cost_curve = CostCurve(market_curve)

mbc = MarketBidCost(
        no_load_cost= 0,
        start_up=0, 
        shut_down =0, 
        incremental_offer_curves = cost_curve
    )
set_operation_cost!(gen, mbc)
get_operation_cost(gen)

# Multi timestep example
market_curve = []
for (i, fp) in enumerate(fp_data)
    mc_data = proportional_term * fp
    # market_curve_i = PiecewiseIncrementalCurve(constant_term, [min_active_power, max_active_power], [mc_data])
    market_curve_i = PiecewiseStepData([min_active_power, max_active_power], [mc_data])
    push!(market_curve, market_curve_i)
end
timestamps = range(DateTime("2030-01-01T00:00:00"), step = Hour(1), length = 8760)
market_bid_data = Dict(timestamps => market_curve)

market_bid_data = Dict(Dates.DateTime("2030-01-01") => market_curve)
time_series_data = Deterministic(
           name = "variable_cost",
           data = market_bid_data,
           resolution = Dates.Hour(1)
       )
set_variable_cost!(sys, gen, time_series_data)

get_operation_cost(gen)


# # Time varying data to submit bids as generators in the network
# market_bid_data = 
#     Dict(Dates.DateTime("2030-01-01") => [
#         PiecewiseStepData([0, 2.0, 3.0], [4.0, 6.0]),
#         PiecewiseStepData([0, 2.0, 6.0], [2.0, 12.0]),]
#     )

# time_series_data = Deterministic(
#            name = "variable_cost",
#            data = market_bid_data,
#            resolution = Dates.Hour(1)
#        )

# set_variable_cost!(sys, gen, time_series_data)

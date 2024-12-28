###########################
# Monte Carlo Version of NVE-Sienna Script
###########################

# call packages
using Pkg
using PowerSystems
using PowerSimulations
using PowerSystemCaseBuilder
using HydroPowerSimulations
using StorageSystemsSimulations
#using PowerAnalytics
#using PowerGraphics
using HiGHS # solver
using Gurobi # solver
using Dates
using Logging
using DataFrames
using Plots
using CSV
using TimeSeries
using Debugger



###########################
# Define Your Paths
###########################
# Specify the output name and scenario name dynamically
r2x_output_name = "output_stable_esig"
scenario_name = "output_stable_esig"  # Could also be another scenario like "test_scenario"

# Call the function
include(joinpath(@__DIR__, "NVE_deterministic.jl"))
paths = initialize_paths_and_inputs(r2x_output_name, scenario_name)

###########################
# Build The Initial System
###########################
sys, pw_data = build_system_from_r2x(paths, r2x_output_name);

# Configure logging
logger = configure_logging(console_level = Logging.Info);

###########################
# Modify The Initial System
###########################
# call _helpers.jl to load additional functions (modify_data, create_area_interchanges, attach_reserve_requirements, constrain_market_imports)
include("C:\\Users\\james\\Documents\\Sienna\\FPA_Sienna\\Projects\\NVE\\sienna_runs\\_helpers.jl")

# Modify the system
modify_system!(sys, pw_data, paths[:data_dir], r2x_output_name)

###########################
# Inspect Data
###########################
get_units_base(sys)
set_units_base_system!(sys, "NATURAL_UNITS")
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

###########################
# Define Probabilistic TimeSeries
###########################
# visually inspect initial timeseries 
show_time_series(sys)
# define LOLP-related functions
include("NVE_stochastic_v2.jl")

# Solar 
###########################
#define solar PowerSystems.jl time series 
solar_ts_container = define_solar_time_series(paths[:solar_dir], sys);

# let's review our work 
df_solar = DataFrame(generator = map(x -> x[1], solar_ts_container),
               time_series = map(x -> x[2].name, solar_ts_container));

# check to see if all objects are listed equal number of times
combine(groupby(df_solar, :generator), nrow => :count)

#now we will add our solar time series container to the system 
add_solar_time_series_to_system!(sys,solar_ts_container)


# now that we have the forecasts added let's, check your work
active_unit = get_component(RenewableDispatch, sys, "ACE Searchlight Solar")
show_time_series(active_unit)

# Wind
###########################
wind_ts_container = define_wind_ts_container(paths[:wind_dir], sys);

# let's review our work 
df_wind = DataFrame(generator = map(x -> x[1], wind_ts_container),
               time_series = map(x -> x[2].name, wind_ts_container));

# check to see if all objects are listed equal number of times
combine(groupby(df_wind, :generator), nrow => :count)

#now we will add our solar time series container to the system 
add_solar_time_series_to_system!(sys,wind_ts_container)

#spot check your work
active_unit = get_component(RenewableDispatch, sys, "Idaho Wind")
show_time_series(active_unit)
get_max_active_power(active_unit) 
get_time_series_keys(active_unit)
get_time_series_array(SingleTimeSeries, active_unit, "max_active_power")
get_time_series_array(SingleTimeSeries, active_unit, "max_active_power_Y1998")

#############
# Demand
#############
#show PowerLoad objects w/ timeseries 
show_components(sys, PowerLoad, Dict("has_time_series" => x -> has_time_series(x)))

#show time series for each PowerLoad object
show_time_series(loads[1]) #default name "max_active_power"
show_time_series(loads[2]) #default name "max_active_power"

#split the load between Nevada Power and Sierra
split_load_ts_dict = create_load_forecasts(paths[:load_dir], loads)

#check your work 
split_load_ts_dict["Nevada Power"]
split_load_ts_dict["Sierra"]

#define demand timeseries for each PowerLoad object 
# Debugger.@enter create_load_fx_timeseries(loads, split_load_ts_dict) - need to enter this directly in repl for some reason
load_ts_container = create_load_fx_timeseries(loads, split_load_ts_dict)

# Call the function to add time series to the system
add_load_time_series_to_system!(sys, load_ts_container)

#spot check your work
active_object = get_component(PowerLoad, sys, "Sierra")
show_time_series(active_object)
get_max_active_power(active_object) #Q: how is Kamran defining max_active_power?
get_time_series_keys(active_object)
get_time_series_array(SingleTimeSeries, active_object, "max_active_power")
get_time_series_array(SingleTimeSeries, active_object, "max_active_power_Y1998")
# get_time_series_array(SingleTimeSeries, active_object, "max_active_power_Y1999")

#create deterministic single time series fxs for missing data; 48-hr horizon & 24-hr lookahead; i.e. 24 hour "realized intervals")
transform_single_time_series!(sys, Hour(48), Hour(24)) #Q: do we need to execute this cmd everytime? 

#################################
# Define Device Model (transitioning to PowerSimulations.jl)
#################################
#Create an empty model reference of the PowerSimulations Optimization Problem
template_uc = ProblemTemplate()

#retrieve thermal standard objects with timeseries (fuel_price & max_active_power)
thermal_ts = collect(get_components(x -> has_time_series(x), ThermalStandard, sys))
show_time_series(thermal_ts[2]) 
get_time_series_keys(thermal_ts[2])
get_time_series_array(SingleTimeSeries, thermal_ts[2], "max_active_power")
get_time_series_array(SingleTimeSeries, thermal_ts[2], "fuel_price")

#define custom DeviceModel for ThermalStand object by defining time varying max_active_power 
thermal_model = DeviceModel(ThermalStandard, ThermalStandardUnitCommitment; time_series_names = Dict(ActivePowerTimeSeriesParameter => "max_active_power"))
# ActivePowerTimeSeriesParameter -> parameter to define active power time series
#Q: why are we not also defining the fuel price time series? 

#assign thermal_model to the template
set_device_model!(template_uc, thermal_model) 

#renewable dispatch model
renewable_model = DeviceModel(RenewableDispatch, RenewableFullDispatch; time_series_names = Dict(ActivePowerTimeSeriesParameter => "max_active_power_Y1998"))
set_device_model!(template_uc, renewable_model)

#PowerLoad (staticpowerload -> formulation to add a time series parameter for non-dispatchable load to power balance constraints)
load_model = DeviceModel(PowerLoad, StaticPowerLoad; time_series_names = Dict(ActivePowerTimeSeriesParameter => "max_active_power_Y1998"))
set_device_model!(template_uc, load_model)

#Hydro
set_device_model!(template_uc, HydroDispatch, HydroDispatchRunOfRiver)

#Storage
storage_model = DeviceModel(
    EnergyReservoirStorage,
    StorageDispatchWithReserves;
    attributes = Dict(
        "reservation" => true, # True prevents discharging and charging in the same period
        "cycling_limits" => false,
        "energy_target" => false,
        "complete_coverage" => false,
        "regularization" => true, # Regularizes storage dispatch to prevent large swings in dispatch.
    ),
)
set_device_model!(template_uc, storage_model)

#= thermal_model = DeviceModel(ThermalStandard, ThermalStandardUnitCommitment; time_series_names = Dict(ActivePowerTimeSeriesParameter => "max_active_power"))
set_device_model!(template_uc, thermal_model) 
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
        "regularization" => true, # Regularizes storage dispatch to prevent large swings in dispatch.
    ),
)
set_device_model!(template_uc, storage_model) =#

#Reserves (disabled for now)
# set_service_model!(template_uc, ServiceModel(VariableReserveNonSpinning, NonSpinningReserve; use_slacks = true))
# set_service_model!(template_uc, ServiceModel(VariableReserve{ReserveUp}, RangeReserve; use_slacks = true))


# copper_plate = NetworkModel(
#         CopperPlatePowerModel,
#         use_slacks=true,
#         PTDF_matrix=PTDF(sys),
#         duals=[CopperPlateBalanceConstraint],
#     )
# set_network_model!(template_uc, copper_plate)

# define our area balance power model to produce our zonal topology (Sienna default is copperplate)
area_interchange = NetworkModel(
        AreaBalancePowerModel, #creates power balance constraints for each area
        use_slacks=false, #disable slack variables; i.e. prevent line flow exceedances
        # PTDF_matrix=PTDF(sys),
        # duals=[CopperPlateBalanceConstraint],
    )
# define the branch model (static branch -> add unbounded flow variables and use flow constraints)
set_device_model!(template_uc, AreaInterchange, StaticBranch) #Q: is this defining TX?

#assign the area_interchange object from above as our network model 
set_network_model!(template_uc, area_interchange)

#lets retrieve all the bus types in the system
get_components(ACBus, sys)
get_name.(get_components(ACBus,sys))
get_bustype.(get_components(ACBus,sys))

#Q: can you have load and gen defined at a PQ load bus
#Q: similarly, can you load and gen defined at a PV gen bus
#Q: what about defining these at a slack bus? 

# Build Decision Model and Simulation
UC_decision = DecisionModel(
    template_uc,
    sys;
    name = "lookahead_UC",
    optimizer = optimizer_with_attributes(Gurobi.Optimizer, "MIPGap" => 1e-3),
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
    simulation_folder = mktempdir(joinpath(paths[:output_dir], "simulation_files"), cleanup = true),
)
#create this output simulation folder
build!(sim; console_level = Logging.Info,)
execute!(sim, enable_progress_bar = true)

###########################
# Export the results
###########################

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

storage_discharge = read_realized_variable(results, "StorageEnergyOutput__EnergyReservoirStorage")
storage_charge = read_realized_variable(results, "ActivePowerInVariable__EnergyReservoirStorage")

# Export Dataframes to csv
CSV.write(joinpath(paths[:scenario_dir] * "storage_charge.csv"), storage_charge)
CSV.write(joinpath(paths[:scenario_dir] * "storage_discharge.csv"), storage_discharge)
CSV.write(joinpath(paths[:scenario_dir] * "load_active_power.csv"), load_parameter)
CSV.write(joinpath(paths[:scenario_dir] * "renewable_parameters.csv"), renewable_parameter) #Q: input values?
CSV.write(joinpath(paths[:scenario_dir] * "renewable_active_power.csv"), renewable_active_power) #Q: output values?
CSV.write(joinpath(paths[:scenario_dir] * "generator_active_power.csv"), gen_active_power)
CSV.write(joinpath(paths[:scenario_dir] * "tx_flow.csv"), tx_flow)
CSV.write(joinpath(paths[:scenario_dir] * "production_costs.csv"), all_pc) 


# Export generation by fuel type (requires PowerAnalytics.jl)
#= all_gen_data = PowerAnalytics.get_generation_data(results)
cat = PowerAnalytics.make_fuel_dictionary(sys)
fuel = PowerAnalytics.categorize_data(all_gen_data.data, cat; curtailment = true, slacks = true)
fuel_agg = PowerAnalytics.combine_categories(fuel)
CSV.write(joinpath(paths[:scenario_dir] * "generation_by_fuel.csv"), fuel_agg) =#

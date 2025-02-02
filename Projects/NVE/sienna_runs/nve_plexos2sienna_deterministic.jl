###########################
# Deterministic Version of NVE-Sienna Script
###########################

# call packages
using Pkg
using Revise
using PowerSystems
using PowerSimulations
using PowerSystemCaseBuilder
using HydroPowerSimulations
using StorageSystemsSimulations
using InfrastructureSystems
using PowerAnalytics
using Gurobi # solver
using Dates
using Logging
using DataFrames
using Plots
using CSV
using TimeSeries

###########################
# Define Your Paths
###########################
# Specify the output name and scenario name dynamically
r2x_output_name = "output_stable_dec24" # name of the r2x scenario
scenario_name = "output_stable_dec24"  # name of the sienna scenario

# Call the function to initialize paths and inputs
include(joinpath(@__DIR__, "NVE_non_weather.jl"))
paths = initialize_paths_and_inputs(r2x_output_name, scenario_name)

###########################
# Call the helpers function 
###########################
# call _helpers.jl to load additional functions (modify_data, create_area_interchanges, attach_reserve_requirements, constrain_market_imports)
# define file path
helpers_file_path = joinpath(paths[:data_dir],"sienna_runs","_helpers.jl")
# load the script
include(helpers_file_path)

###########################
# Model Administration 
###########################
# Configure logging
logger = configure_logging(console_level=Logging.Info)

###########################
# Build The Initial System
###########################
sys, pw_data = build_system_from_r2x(paths, r2x_output_name);
get_units_base(sys)
set_units_base_system!(sys, "NATURAL_UNITS")
# set_units_base_system!(sys, "DEVICE_BASE")

###########################
# Modify The Initial System
###########################
# create area interchanges, define initial SOC, set generator services, define availability, add VOM to production costs, set reference bus)
modify_system!(sys, pw_data, paths)

###########################
# Missing time series for fuel_prices (?)
###########################
# assign fuel_price timeseries to dual fuel Thermal standard objects (R2X defaulted to hydrogen fuel price)
active_unit = get_component(ThermalStandard, sys, "Valmy CT 3")
show_time_series(active_unit)
get_time_series_array(SingleTimeSeries, active_unit, "fuel_price")
active_unit.operation_cost

# check to see if there are any missing timeseries for fuel_price
for g in collect(get_components(ThermalStandard, sys))
    if "fuel_price" ∉ get_name.(get_time_series_keys(g))
        @show g.name
        @show g.operation_cost.variable.fuel_cost
    end
end

# create and assign the timeseries for natural gas fuel prices
# ThermalStandard_missing_ts!(sys,paths)

# check to make sure missing timeseries were created successfully
#show_time_series(active_unit)
#get_time_series_array(SingleTimeSeries, active_unit, "fuel_price")
#active_unit.operation_cost

#= # remaining units should be oddballs (e.g., geothermal, waste heat, and biomass); assuming fixed fuel prices 
for g in collect(get_components(ThermalStandard, sys))
    if "fuel_price" ∉ get_name.(get_time_series_keys(g))
        @show g.name
        #@show g.operation_cost.variable.fuel_cost
    end
end =#

###########################
# Convert DPV units from RenewableDispatch to RenewableNonDispatch
###########################
convert_BTM_units!(sys, paths)

###########################
# Define production costs for TA resource and add in DR Units
###########################
Tuning_Adjustment_Costs!(sys)
Demand_Response_CleanUp!(sys)

###########################
# Fix Hydro Dispatch Profile for Hoover
###########################
fix_Hydro_Dispatch!(sys)

############################################################
# Reassign prime mover type for ThermalStandard generators and set initial conditions
############################################################
# read in datafile
df_pm = CSV.read(joinpath(paths[:data_dir],"nve_prime_mover_mapping.csv"), DataFrame);

# loop through all ThermalStandard generators
for thermal_gen in get_components(ThermalStandard, sys)
    obj_name = get_name(thermal_gen)  # Retrieve the name of the object

    # Find the corresponding row in the mapping table
    match_idx = findfirst(x -> x == obj_name, df_pm.resource)  # Match with the `resource` column
    if match_idx !== nothing  # case when a match is found
        # Access the prime_mover_type from the matched row
        new_prime_mover_type = df_pm.prime_mover_type[match_idx]  # Match with the `prime_mover_type` column
        set_prime_mover_type!(thermal_gen, new_prime_mover_type)
        # println("Updated $(obj_name) with PrimeMoverType: $new_prime_mover_type")  # Optional debug print
    else
        println("No match found for $(obj_name)")  # Debug print for unmatched objects
    end
end

#= #set all ThermalStandard generators that are CTs to zero
for thermal_gen in get_components(ThermalStandard, sys)
    if string(get_prime_mover_type(thermal_gen)) == "GT"
        set_active_power!(thermal_gen, 0.0)
    end
end =#

###########################
# Inspect Data
###########################
buses = collect(get_components(ACBus, sys));
loads = collect(get_components(PowerLoad, sys));
lines = collect(get_components(Line, sys));
arcs = collect(get_components(Arc, sys));
areas = collect(get_components(Area, sys));
area_interchanges = collect(get_components(AreaInterchange, sys));
gens_thermal = collect(get_components(ThermalStandard, sys));
gens_renew = collect(get_components(RenewableDispatch, sys));
# solar_renew = [gen for gen in gens_renew if get_prime_mover_type(gen) == PrimeMovers.PVe];
# wind_renew = [gen for gen in gens_renew if get_prime_mover_type(gen) == PrimeMovers.WT];
# Initialize empty collections for solar and wind generators
solar_renew = []
wind_renew = []

# Loop through the renewable generators and classify them
for gen in gens_renew
    if get_prime_mover_type(gen) == PrimeMovers.PVe
        push!(solar_renew, gen)  # Add to solar_renew
    elseif get_prime_mover_type(gen) == PrimeMovers.WT
        push!(wind_renew, gen)  # Add to wind_renew
    end
end

batteries = collect(get_components(EnergyReservoirStorage, sys));
reserves_spinning = collect(get_components(VariableReserve{ReserveUp}, sys));
reserves_non_spinning = collect(get_components(VariableReserveNonSpinning, sys));

############################################################
##  Timeseries
############################################################
show_time_series(sys)

#general querying of the system
#retrieve thermal standard objects with timeseries (fuel_price & max_active_power)
thermal_ts = collect(get_components(x -> has_time_series(x), ThermalStandard, sys));
active_unit = thermal_ts[1]
active_unit = get_component(ThermalStandard, sys, "Valmy CT 3")
show_time_series(active_unit) 
get_time_series_keys(active_unit)
get_time_series_array(SingleTimeSeries, active_unit, "max_active_power"; ignore_scaling_factors = true)
get_time_series_array(SingleTimeSeries, active_unit, "max_active_power"; ignore_scaling_factors = false)
get_time_series_array(SingleTimeSeries, active_unit, "fuel_price"; ignore_scaling_factors = true)
get_time_series_array(SingleTimeSeries, active_unit, "fuel_price"; ignore_scaling_factors = false)

#retrieve RenewableDispatch objects with timeseries (rating factor, max_active_power)
renew_ts = collect(get_components(x -> has_time_series(x), RenewableDispatch, sys));
active_re_unit = get_component(RenewableDispatch, sys, "_PCM Generic Expansion_SPPC_Wind (ID)")
#active_re_unit = get_component(RenewableDispatch, sys, "Spring Valley Wind")
active_re_unit = get_component(RenewableDispatch, sys, "ACE Searchlight Solar")
show_time_series(active_re_unit) 
get_time_series_keys(active_re_unit)
get_time_series_array(SingleTimeSeries, active_re_unit, "Rating Factor")
get_time_series_array(SingleTimeSeries, active_re_unit, "max_active_power"; ignore_scaling_factors = true)
get_time_series_array(SingleTimeSeries, active_re_unit, "max_active_power"; ignore_scaling_factors = false)

#retrieve PowerLoad objects with timeseries
power_load_ts = collect(get_components(x -> has_time_series(x), PowerLoad, sys));
active_load = power_load_ts[1]
get_max_active_power(active_load)
show_time_series(active_load) 
get_time_series_keys(active_load)
get_time_series_array(SingleTimeSeries, active_load, "max_active_power"; ignore_scaling_factors = true)
get_time_series_array(SingleTimeSeries, active_load, "max_active_power"; ignore_scaling_factors = false)

active_load = power_load_ts[2]
get_max_active_power(active_load)
show_time_series(active_load) 
get_time_series_keys(active_load)
get_time_series_array(SingleTimeSeries, active_load, "max_active_power"; ignore_scaling_factors = true)
get_time_series_array(SingleTimeSeries, active_load, "max_active_power"; ignore_scaling_factors = false)


#############
# create deterministic single time series fxs for missing data; 48-hr horizon & 24-hr lookahead; i.e. 24 hour "realized intervals")
#############
# after this command we will have DeterministicSingleTimeSeries objects for all missing time series serving as forecasts
transform_single_time_series!(sys, Hour(48), Hour(24)) #Q: when is the appropriate time to call this function?

###########################
# Sienna Temporary Patches
###########################
# first get baseline values
active_unit = get_component(ThermalStandard, sys, "Chuck Lenzi 2_B")
show_time_series(active_unit)
active_unit.operation_cost #note how fuel_cost has a fixed value specified (this is ignoring the ts we have attached)
show_time_series(active_load)

# correct for bug that has production cost expression ignoring fuel_prices sourced from timeseries
update_thermal_fuel_price_timeseries!(sys)

# check your work (ThermalStandard)
show_time_series(active_unit)
get_time_series(SingleTimeSeries, active_unit, "fuel_price") 
get_time_series_array(SingleTimeSeries, active_unit, "fuel_price"; ignore_scaling_factors = true) 
get_time_series_array(SingleTimeSeries, active_unit, "fuel_price"; ignore_scaling_factors = false) # this should be equal to the previous cmd 
get_time_series_array(DeterministicSingleTimeSeries, active_unit, "fuel_price")
active_unit.operation_cost # note: you should not see a fixed price under fuel_cost anymore; this should be a pointer to the timeseries

#################################
# Define Device, Branch, an Network Models
#################################
#assign name
uc_decision_name = "lookahead_UC"

# Create an empty model reference
template_uc = ProblemTemplate()

# Define thermal, hydro, and storage device models (non-weather-dependent)
define_device_model_non_weather(template_uc)

# Define load and renewable device models (deterministic)
define_device_model_weather_deterministic(template_uc)

# Define branch and network models
define_branch_model(template_uc)
define_network_model(template_uc)

###########################
# Build and Execute Simulation
###########################
get_units_base(sys)
set_units_base_system!(sys, "NATURAL_UNITS")
sim, UC_decision = build_and_execute_simulation(template_uc, sys, paths; decision_name=uc_decision_name);

###########################
# Review Production Costs
###########################
#= exprs = UC_decision.internal.container.expressions
cost_ths = exprs[InfrastructureSystems.Optimization.ExpressionKey{ProductionCostExpression, ThermalStandard}("")]
cost_ths["Chuck Lenzi 1_A", 1] =#

###########################
# Export the Results
###########################
# define file paths to store (processed) results for the active year
file_path = (paths[:scenario_dir_d])

# check if folder directory exists; if not, create it
if !ispath(file_path)
    mkpath(file_path)
else
end  

query_write_export_results(sim, file_path, uc_decision_name)
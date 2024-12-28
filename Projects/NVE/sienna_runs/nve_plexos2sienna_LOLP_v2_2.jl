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

#general querying of the system
#retrieve thermal standard objects with timeseries (fuel_price & max_active_power)
thermal_ts = collect(get_components(x -> has_time_series(x), ThermalStandard, sys))
show_time_series(thermal_ts[2]) 
get_time_series_keys(thermal_ts[2])
get_time_series_array(SingleTimeSeries, thermal_ts[2], "max_active_power")
get_time_series_array(SingleTimeSeries, thermal_ts[2], "fuel_price")

###########################################################################################
# For Loop to Iterate Over Each Weather Year for our Monte Carlo RA LOLP Simulation 
###########################################################################################
# Define the range of weather years
weather_years = 1998:1998

# Dictionary to store results for each weather year
weather_year_results = Dict{Int, Tuple{Simulation, DecisionModel}}()

# Iterate over each weather year
for year in weather_years
    # Generate strings for the current year
    year_str = string(year)

    #define unique identifies for timeseries pointers and decision model names 
    timeseries_name = "max_active_power_Y$year_str"  # e.g., "max_active_power_Y1998"
    uc_decision_name = "DA_WY_$year_str"  # e.g., "DA_WY_1998"

    # Update paths to store results for this year
    paths[:scenario_dir] = joinpath(paths[:output_dir], "results_WY_$year_str")
    if !isdir(paths[:scenario_dir])
        mkdir(paths[:scenario_dir])
    end

    #################################
    # Define Device, Branch, an Network Models
    #################################
    # Create an empty model reference
    template_uc = ProblemTemplate()

    # Define thermal, hydro, and storage device models (non-weather-dependent)
    define_device_model_non_weather(template_uc)

    # Define load and renewable dispatch models (weather-dependent)
    define_device_model_weather(template_uc; load_timeseries_name=timeseries_name, renewable_timeseries_name=timeseries_name)

    # Define branch and network models
    define_branch_model(template_uc)
    define_network_model(template_uc)

    ###########################
    # Build and Execute Simulation
    ###########################
    sim, UC_decision = build_and_execute_simulation(template_uc, sys, paths; decision_name=uc_decision_name)

    # Store results for this year
    weather_year_results[year] = (sim, UC_decision)

    ###########################
    # Export the Results
    ###########################
    query_write_export_results(sim, paths)
end

println("Simulation completed for all weather years.")
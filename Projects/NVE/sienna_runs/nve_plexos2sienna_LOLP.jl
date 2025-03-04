###########################
# Monte Carlo Version of NVE-Sienna Script
###########################

# call packages
using Pkg
# using Revise
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
using SiennaPRASInterface

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
df_outage_stats = CSV.read(joinpath(paths[:LOLP_inputs],"outage_statistics.csv"), DataFrame)

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

    # Set the outage statistics
    outage_stats = df_outage_stats[df_outage_stats.Item .== obj_name, :]
    # check if outage_stats is empty
    if size(outage_stats, 1) == 0
        @warn "No outage statistics found for $(obj_name)"
        continue
    end

    transition_data = GeometricDistributionForcedOutage(;
        mean_time_to_recovery=outage_stats.MTTR[1],  # Units of hours
        outage_transition_probability=outage_stats.outage_transition_probability[1],  # Probability for outage per hour
    )
    add_supplemental_attribute!(sys, thermal_gen, transition_data)

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
gens_ftm_renew = collect(get_components(RenewableDispatch, sys));
gens_btm_renew = collect(get_components(RenewableNonDispatch, sys));
gen_hydro = collect(get_components(HydroDispatch, sys));
# solar_renew = [gen for gen in gens_renew if get_prime_mover_type(gen) == PrimeMovers.PVe];
# wind_renew = [gen for gen in gens_renew if get_prime_mover_type(gen) == PrimeMovers.WT];
# Initialize empty collections for solar and wind generators
solar_renew = []
wind_renew = []

# Loop through the renewable generators and classify them
for gen in gens_ftm_renew
    if get_prime_mover_type(gen) == PrimeMovers.PVe
        push!(solar_renew, gen)  # Add to solar_renew
    elseif get_prime_mover_type(gen) == PrimeMovers.WT
        push!(wind_renew, gen)  # Add to wind_renew
    end
end

batteries = collect(get_components(EnergyReservoirStorage, sys));
reserves_spinning = collect(get_components(VariableReserve{ReserveUp}, sys));
reserves_non_spinning = collect(get_components(VariableReserveNonSpinning, sys));

# Retrieve all generator-type components in one go
all_generators = collect(get_components(Generator, sys))
all_storage = collect(get_components(Storage, sys))

# Define collections to iterate over
unit_collections = Dict(
    "GenUnits" => all_generators,
    "StorageUnits" => all_storage)

############################################################
##  Retrieve NamePlate Capacity of System
############################################################
#= # Initialize an empty DataFrame
df = DataFrame(Resource = String[], MW_capacity = Float64[])

# for each generator collection, loop through each unit w/in that collection
for (category, gen_collection) in unit_collections
    if category == "StorageUnits" #batteries
        for unit in gen_collection
            if get_available(unit)  # Check if the unit is active
                name = get_name(unit)  # Get the generator's name
                capacity = get_output_active_power_limits(unit).max  # Get the max active discharge power (MW)

                # Append to DataFrame
                push!(df, (name, capacity))
            else
            # do nothing
            end
        end
    else # all other generator types
        for unit in gen_collection
            if get_available(unit)  # Check if the unit is active

                name = get_name(unit)  # Get the generator's name
                capacity = get_max_active_power(unit)  # Get the max active power (MW)

                # Append to DataFrame
                push!(df, (name, capacity))
            else
                #do nothing
            end
        end
    end # if loop
end

#write df to csv
CSV.write(joinpath(paths[:data_dir], "nve_nameplate_capacity.csv"), df); =#

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
active_re_unit = get_component(RenewableDispatch, sys, "Idaho Wind")
active_re_unit = get_component(RenewableDispatch, sys, "Spring Valley Wind")
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

"""
NOTE: deterministic load fx - which comes from WY 1998 and is represented by "max_active_power" is slightly different
than what we will see with stochastic load fx, which is represented by "max_active_power_Y1998"

this reflects the same setup that was donen in PLEXOS
"""

###########################
# Define Probabilistic TimeSeries
###########################
# define LOLP-related functions
include("NVE_weather.jl")

# Solar
###########################
#define solar PowerSystems.jl time series
solar_ts_container, df_solar_max = define_solar_time_series(paths[:solar_dir], sys);

# let's review our work
df_solar = DataFrame(generator = map(x -> x[1], solar_ts_container),
               time_series = map(x -> x[2].name, solar_ts_container));

# check to see if all objects are listed equal number of times
combine(groupby(df_solar, :generator), nrow => :count)

#now we will add our solar time series container to the system
add_solar_time_series_to_system!(sys,solar_ts_container)

# now that we have the PowerSystems.jl timeseries added to the system, let's check your work
active_re_unit = get_component(RenewableDispatch, sys, "ACE Searchlight Solar")
show_time_series(active_re_unit)
get_time_series_array(SingleTimeSeries, active_re_unit, "Rating Factor")
get_time_series_array(SingleTimeSeries, active_re_unit, "max_active_power"; ignore_scaling_factors = true)
get_time_series_array(SingleTimeSeries, active_re_unit, "max_active_power"; ignore_scaling_factors = false)
get_time_series_array(SingleTimeSeries, active_re_unit, "max_active_power_Y1998"; ignore_scaling_factors = true)
get_time_series_array(SingleTimeSeries, active_re_unit, "max_active_power_Y1998"; ignore_scaling_factors = false)

# Wind
###########################
wind_ts_container = define_wind_ts_container(paths[:wind_dir], sys);

# let's review our work
df_wind = DataFrame(generator = map(x -> x[1], wind_ts_container),
               time_series = map(x -> x[2].name, wind_ts_container));

# check to see if all objects are listed equal number of times
combine(groupby(df_wind, :generator), nrow => :count)

#now we will add our wind time series container to the system
add_wind_time_series_to_system!(sys,wind_ts_container)

#spot check your work
# active_re_unit = get_component(RenewableDispatch, sys, "Idaho Wind")
active_re_unit = get_component(RenewableDispatch, sys, "Spring Valley Wind")
show_time_series(active_re_unit)
get_max_active_power(active_re_unit)
get_time_series_keys(active_re_unit)
get_time_series_array(SingleTimeSeries, active_re_unit, "Rating Factor")
get_time_series_array(SingleTimeSeries, active_re_unit, "max_active_power"; ignore_scaling_factors = true)
get_time_series_array(SingleTimeSeries, active_re_unit, "max_active_power"; ignore_scaling_factors = false)
get_time_series_array(SingleTimeSeries, active_re_unit, "max_active_power_Y2014"; ignore_scaling_factors = true)
get_time_series_array(SingleTimeSeries, active_re_unit, "max_active_power_Y2014"; ignore_scaling_factors = false)

#############
# Demand
#############
#show PowerLoad objects w/ timeseries
show_components(sys, PowerLoad, Dict("has_time_series" => x -> has_time_series(x)))

#show time series for each PowerLoad object
show_time_series(loads[1]) #default name "max_active_power"
show_time_series(loads[2]) #default name "max_active_power"

# create / upload powersystems.jl timeseries for regional areas of Nevada Power and Sierra regions
load_ts_container = upload_split_load_forecasts(paths[:load_dir], loads);

# check your work
df_load = DataFrame(generator = map(x -> x[1], load_ts_container),
               time_series = map(x -> x[2].name, load_ts_container));

# check to see if all objects are listed equal number of times
combine(groupby(df_load, :generator), nrow => :count)

# Call the function to add time series to the system
add_load_time_series_to_system!(sys, load_ts_container)

#spot check your work
active_load = get_component(PowerLoad, sys, "Nevada Power")
show_time_series(active_load)
get_max_active_power(active_load)
get_time_series_keys(active_load)
get_time_series_array(SingleTimeSeries, active_load, "max_active_power"; ignore_scaling_factors = true)
get_time_series_array(SingleTimeSeries, active_load, "max_active_power"; ignore_scaling_factors = false)
get_time_series_array(SingleTimeSeries, active_load, "max_active_power_Y1998"; ignore_scaling_factors = true)
get_time_series_array(SingleTimeSeries, active_load, "max_active_power_Y1998"; ignore_scaling_factors = false)

active_load = get_component(PowerLoad, sys, "Sierra")
show_time_series(active_load)
get_max_active_power(active_load)
get_time_series_keys(active_load)
get_time_series_array(SingleTimeSeries, active_load, "max_active_power"; ignore_scaling_factors = true)
get_time_series_array(SingleTimeSeries, active_load, "max_active_power"; ignore_scaling_factors = false)
get_time_series_array(SingleTimeSeries, active_load, "max_active_power_Y1998"; ignore_scaling_factors = true)
get_time_series_array(SingleTimeSeries, active_load, "max_active_power_Y1998"; ignore_scaling_factors = false)

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

###########################################################################################
# For Loop to Iterate Over Each Weather Year for our Monte Carlo RA LOLP Simulation
###########################################################################################
# Define the range of weather years
weather_years = 1998:2002 # testing for only a few yrs for now

# Dictionary to store results for each weather year
# weather_year_results = Dict{Int, Tuple{Simulation, DecisionModel}}()

# Iterate over each weather year
for wy in weather_years

    # Generate strings for the current year
    year_str = string(wy)

    #define unique identifies for timeseries pointers and decision model names
    uc_decision_name = "DA_WY_$year_str"  # e.g., "DA_WY_1998"
    ts_RD_name = "max_active_power_Y$year_str"  # e.g., "max_active_power_Y1998"
    ts_PL_name = "max_active_power_Y$year_str"  # e.g., "max_active_power_Y1998"

    #################################
    # Define Device, Branch, an Network Models
    #################################
    # Create an empty model reference
    template_uc = ProblemTemplate()

    # Define thermal, hydro, and storage device models (non-weather-dependent)
    define_device_model_non_weather(template_uc)

    # Define load and renewable dispatch models (weather-dependent)
    define_device_model_weather_stochastic(template_uc; load_timeseries_name=ts_PL_name, renewable_timeseries_name=ts_RD_name)

    # Define branch and network models
    define_branch_model(template_uc)
    define_network_model(template_uc)

    ###########################
    # Build and Execute Simulation
    ###########################
    get_units_base(sys)
    set_units_base_system!(sys, "NATURAL_UNITS")
    sim, UC_decision = build_and_execute_simulation(template_uc, sys, paths; decision_name=uc_decision_name);

    # Print a message to indicate that the simulation is complete
    println("Simulation completed for: $uc_decision_name.")

    ###########################
    # Export the Results
    ###########################
    # define file paths to store (processed) results for the active weather yr
    file_path = joinpath(paths[:scenario_dir_s], "results_WY_$year_str")

    # check if folder directory exists; if not, create it
    if !ispath(file_path)
        mkpath(file_path)
    else
    end
    # now write the files
    query_write_export_results(sim, file_path, uc_decision_name)
end



###########################################################################################
# For Loop to Iterate Over Each Weather Year for our Monte Carlo RA LOLP Simulation using SiennaPRASInterface
###########################################################################################
# Define the range of weather years
weather_years = 1998:2022 # testing for only a few yrs for now
# Dictionary to store results for each weather year
# weather_year_results = Dict{Int, Tuple{Simulation, DecisionModel}}()
shortfall_results = []

# Hot-Fix Function to update max_active_power time series for loads
function update_max_active_power_ts!(sys, load_name, ts_name)
    active_load = get_component(PowerLoad, sys, load_name)
    ts = get_time_series_array(SingleTimeSeries, active_load, ts_name; ignore_scaling_factors = true)
    ts_d = SingleTimeSeries(name = "max_active_power", data = ts)
    remove_time_series!(sys, SingleTimeSeries, active_load, "max_active_power")
    add_time_series!(sys, active_load, ts_d)
end

# Iterate over each weather year
for wy in weather_years

    # Generate strings for the current year
    year_str = string(wy)

    #define unique identifies for timeseries pointers and decision model names
    uc_decision_name = "DA_WY_$year_str"  # e.g., "DA_WY_1998"
    ts_RD_name = "max_active_power_Y$year_str"  # e.g., "max_active_power_Y1998"
    ts_PL_name = "max_active_power_Y$year_str"  # e.g., "max_active_power_Y1998"

    # Update both load areas
    update_max_active_power_ts!(sys, "Sierra", ts_RD_name)
    update_max_active_power_ts!(sys, "Nevada Power", ts_RD_name)

    ###########################
    # Run SiennaPRASInterface
    ###########################
    problem_template = RATemplate(
        PowerSystems.Area,
        [
            DeviceRAModel(
                PowerSystems.ThermalGen,
                GeneratorPRAS(max_active_power=ts_RD_name),
            ),
            DeviceRAModel(
                PowerSystems.RenewableGen,
                GeneratorPRAS(max_active_power=ts_RD_name),
            ),
        ],
    )
    pras_sys = generate_pras_system(sys, problem_template)

    method = SequentialMonteCarlo(samples=5000, seed=1)
    shortfalls = assess(pras_sys, method, Shortfall())
    push!(shortfall_results, shortfalls)
    println("SiennaPRASInterface simulation completed for: WY $wy.")
end


# Process and export shortfall results to CSV files

# Create a DataFrame to store summary statistics for all weather years
summary_df = DataFrame(weather_year = Int[], eue = Float64[], std_error = Float64[])

# Process each weather year's results
for (idx, wy) in enumerate(weather_years)
    # Calculate EUE (Expected Unserved Energy) for this weather year
    eue_value = EUE(shortfall_results[idx][1])
    eue = eue_value.eue.estimate
    std_error = eue_value.eue.standarderror

    # Add to summary DataFrame
    push!(summary_df, (wy, eue, std_error))

    # Export individual shortfall mean data for this weather year
    shortfall_mean = shortfall_results[idx][1].shortfall_mean

    # Convert shortfall mean to DataFrame for easier CSV export
    # Fix: Add :auto as second argument to DataFrame constructor
    shortfall_df = DataFrame(shortfall_mean, :auto)

    # Export to CSV
    shortfall_csv_path = joinpath(paths[:scenario_dir_s], "shortfall_mean_WY_$(wy).csv")
    CSV.write(shortfall_csv_path, shortfall_df)
    println("Exported shortfall mean data for WY $(wy) to: $(shortfall_csv_path)")
end

# Export the summary statistics to CSV
summary_csv_path = joinpath(paths[:scenario_dir_s], "shortfall_summary.csv")
CSV.write(summary_csv_path, summary_df)
println("Exported shortfall summary statistics to: $(summary_csv_path)")

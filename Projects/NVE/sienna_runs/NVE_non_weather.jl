function initialize_paths_and_inputs(r2x_output_name::String, scenario_name::String)
    # Define root directory and related paths
    current_dir = pwd()

    # Check if "Projects" exists in the path (want to have root directory get you to \\FPA_Sienna)
    if occursin("Projects", current_dir)
        # Find the position where "Projects" starts
        start_pos = first(findfirst("Projects", current_dir)) #return the starting index of the string position for "Projects"
        # Trim off everything from "Projects" onward
        root_dir = current_dir[1:start_pos-1]
    else
    end
    # @show root_dir

    data_dir = joinpath(root_dir, "Projects", "NVE") # root data directory
    r2x_dir = joinpath(data_dir, r2x_output_name) # R2X folder
    output_dir = joinpath(root_dir, "Projects", "NVE", "sienna_runs", "run_output") # Sienna processed outputs and simulation files
    sim_files_dir = joinpath(output_dir, "simulation_files") # Sienna outputs

    # Directory for output results 
    scenario_dir_deterministic = joinpath(output_dir, scenario_name,"deterministic") # Scenario name passed as argument
    scenario_dir_stochastics = joinpath(output_dir, scenario_name,"stochastics") # Scenario name passed as argument

    # Stochastic inputs
    solar_dir = joinpath(data_dir, "LOLP_inputs", "solar")
    wind_dir = joinpath(data_dir, "LOLP_inputs", "wind")
    load_dir = joinpath(data_dir, "LOLP_inputs", "load")

    # Ensure that simulation_files exists
    if !ispath(sim_files_dir)
        mkpath(sim_files_dir)
    else
    end

    # Ensure that deterministic directory exists
    if !ispath(scenario_dir_deterministic)
        mkpath(scenario_dir_deterministic)
    else
    end

    # Ensure that stochastic directory exists
    if !ispath(scenario_dir_stochastics)
        mkpath(scenario_dir_stochastics)
    else
    end

    # Point to the appropriate input file
    descriptors_dir = joinpath(root_dir, "Projects", "NVE", "sienna_runs", "user_descriptors")

    # Return all paths as a dictionary for easy access
    return Dict(
        :root_dir => root_dir,
        :data_dir => data_dir,
        :r2x_dir => r2x_dir,
        :output_dir => output_dir,
        :sim_files_dir => sim_files_dir,
        :scenario_dir_d => scenario_dir_deterministic,
        :scenario_dir_s => scenario_dir_stochastics,
        :solar_dir => solar_dir,
        :wind_dir => wind_dir,
        :load_dir => load_dir,
        :descriptors_dir => descriptors_dir
    )
end

function build_system_from_r2x(paths::Dict{Symbol, String}, r2x_output_name::String)
    # Base power for the system
    base_power = 1.0

    # Extract paths from the dictionary
    root_dir = paths[:root_dir]
    # data_dir = paths[:data_dir]

    # Define paths to input files
    descriptors = joinpath(paths[:descriptors_dir], "$r2x_output_name.yaml")
    generator_mapping = joinpath(root_dir, "Projects", "NVE", "sienna_runs", "generator_mapping.yaml")
    timeseries_metadata = joinpath(root_dir, "Projects", "NVE", r2x_output_name, "timeseries_pointers.json")

    # Load the data
    data = PowerSystemTableData(
        paths[:r2x_dir],
        base_power,
        descriptors;
        generator_mapping_file = generator_mapping,
        timeseries_metadata_file = timeseries_metadata,
    )

    #call the helper function modify_data
    modify_data(data)

    # Create the system
    sys = System(data, time_series_in_memory= true) #Q: what is time_series_in_memory?

    # Define the path to the PWL output CSV
    pw_file = joinpath(paths[:r2x_dir], "generator_PWL_output.csv")

    # Read the PWL output into a DataFrame
    pw_data = DataFrame(CSV.File(pw_file))

    # Return the system and the PWL data
    return sys, pw_data
end

function modify_system!(sys::System, pw_data::DataFrame, paths::Dict)
    #create area interchanges so that system goes from 1 area to 4
    create_area_interchanges(sys, paths[:r2x_dir])
    # attach_reserve_requirements(sys, joinpath(paths[data_dir], r2x_output_name))

    # Define initial state of charge (SOC) for storage
    for storage in get_components(EnergyReservoirStorage, sys)
        set_initial_storage_capacity_level!(storage, 0.33)
    end

    # Set generator services (i.e., assign memberships)
    for gen in get_components(ThermalStandard, sys)
        if !occursin("Purchases", get_name(gen))
            #concat the two vectors of services 
            eligible_services = vcat(
                collect(get_components(VariableReserve{ReserveUp}, sys)),
                # disabling non-spinning reserves Q: what is going on here 
                # collect(get_components(VariableReserveNonSpinning, sys))
                )
            set_services!(gen, eligible_services)
        end
    end

    # Disable all reserves
    for reserve in get_components(VariableReserve{ReserveUp}, sys)
        set_available!(reserve, false)
    end

    # Constrain the Market imports (i.e., convert mkt purchases to renewable dispatch)
    #constrain_market_imports(sys, paths[:r2x_dir])

    # Set market purchases availability
    # set_available!(get_component(ThermalStandard, sys, "Southern Purchases (NVP)"), false)
    # set_available!(get_component(ThermalStandard, sys, "Northern Purchases (Sierra)"), false)
    set_available!(get_component(ThermalStandard, sys, "Tuning Adjustment"), false)
    set_available!(get_component(RenewableDispatch, sys, "NVE.Owned.DR/DSM.PV"), false)
    set_available!(get_component(RenewableDispatch, sys, "PPA.Contracted.DR/DSM.PV"), false)   

    #set_available!(get_component(RenewableDispatch, sys, "Sierra Solar II"), false) # COD: 4/1/2030

    # Set hydro availability
    for hydro in get_components(HydroDispatch, sys)
        set_available!(hydro, false)
    end

    # Modify generator heat rates
    for row in eachrow(pw_data)
        generator_name = row.name
        generator = get_component(ThermalStandard, sys, generator_name)
        generator_op_cost = get_operation_cost(generator)
    
        new_vc = PiecewisePointCurve(
            [
                (row.output_point_0 , row.heat_rate_avg_0),
                (row.output_point_1 , row.heat_rate_incr_1),
                (row.output_point_2 , row.heat_rate_incr_2),
                (row.output_point_3 , row.heat_rate_incr_3),
                (row.output_point_4 , row.heat_rate_incr_4),
                (row.output_point_5 , row.heat_rate_incr_5),
            ]
        )
    
        fuel_curve = FuelCurve(
            value_curve = new_vc, 
            fuel_cost = generator_op_cost.variable.fuel_cost,
            vom_cost = generator_op_cost.variable.vom_cost
            )
    
        new_generator_cost = ThermalGenerationCost(
            variable = fuel_curve, 
            fixed = 0, 
            start_up = generator_op_cost.start_up, 
            shut_down = generator_op_cost.shut_down
            )
        set_operation_cost!(generator, new_generator_cost)
    end

    # Set the reference (slack) bus
    set_bustype!(get_component(ACBus, sys, "Nevada Power"), "REF")
end

function ThermalStandard_missing_ts!(sys,paths::Dict{Symbol, String})
    # Extract paths from the dictionary
    root_dir = paths[:r2x_dir]

    # Define paths to input files
    file_path = joinpath(root_dir, "missing_fuel_timeseries.csv")

    # read in datafile
    df = CSV.read(file_path, DataFrame)

    # generate and assign fuel price timeseries to ThermalStandard generators that are missing them (dual fuel units)
    DFU = ["Valmy CT 3", "Valmy CT 4", "Silverhawk 3", "Silverhawk 4"]
    for device_name in DFU # loop through dual fuel units
        # Retrieve the active device by its name
        active_device = get_component(ThermalStandard, sys, device_name)

        # create the time series
        ts = SingleTimeSeries(
            name = "fuel_price",
            data = TimeArray(df[!,"DateTime"],df[!,device_name]), #create a TimeArray object 
        )

        # Add the time series to the system
        add_time_series!(sys, active_device, ts)

        @show "Added fuel price time series to $device_name"
    end
end

function update_thermal_fuel_price_timeseries!(sys)
    # look at an example unit
    gen = get_component(ThermalStandard, sys, "Chuck Lenzi 1_A")
    ts_test = get_time_series(DeterministicSingleTimeSeries, gen, "fuel_price")
    get_time_series_array(DeterministicSingleTimeSeries, gen, "fuel_price")
    
    # retrieve forecast horizon and interval
    horizon = get_horizon(ts_test)
    interval = get_interval(ts_test)

    # remove DeterministicSingleTimeSeries (i.e. forecasts) from ALL objects (ThermalStandard, RenewableDispatch, etc.)
    remove_time_series!(sys, DeterministicSingleTimeSeries)

    #reassign fuel_price timeseries to ThermalStandard objects
    for g in collect(get_components(ThermalStandard, sys))
        if "fuel_price" ∈ get_name.(get_time_series_keys(g))
            fuel_ts = get_time_series(SingleTimeSeries, g, "fuel_price")
            fuel_array = get_time_series_array(SingleTimeSeries, g, "fuel_price"; ignore_scaling_factors = true)
            tstamp = timestamp(fuel_array)
            vals = values(fuel_array)
            new_ts = SingleTimeSeries("fuel_price", TimeArray(tstamp, vals))
            remove_time_series!(sys, SingleTimeSeries, g, "fuel_price")
            set_fuel_cost!(sys, g, new_ts)
        end
    end 
    # add back in the forecasts for all objects (e.g., ThermalStandard, RenewableDispatch, etc.)   
    transform_single_time_series!(sys, horizon, interval)
end

function define_device_model_non_weather(template_uc)
    # Define custom DeviceModel for ThermalStandard with time-varying max_active_power
    thermal_model = DeviceModel(ThermalStandard, ThermalStandardUnitCommitment; time_series_names = Dict{Any, String}(
                    PowerSimulations.FuelCostParameter => "fuel_price",
                    PowerSimulations.ActivePowerTimeSeriesParameter => "max_active_power",))
    set_device_model!(template_uc, thermal_model)

    # Define Hydro model
    set_device_model!(template_uc, HydroDispatch, HydroDispatchRunOfRiver)

    # Define custom DeviceModel for EnergyReservoirStorage
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
    # Assign the storage model to the template_uc
    set_device_model!(template_uc, storage_model)
end

function define_device_model_weather_deterministic(template_uc)
    # define the load model
    set_device_model!(template_uc, PowerLoad, StaticPowerLoad)

    # define the renewable dispatch model
    set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
end

function define_device_model_weather_stochastic(template_uc; load_timeseries_name, renewable_timeseries_name)
    # Define custom PowerLoad model for MC runs
    load_model = DeviceModel(
        PowerLoad,
        StaticPowerLoad;
        time_series_names = Dict(ActivePowerTimeSeriesParameter => load_timeseries_name)
    )
    # Assign custom load model to template
    set_device_model!(template_uc, load_model)

    # Define custom RenewableDispatch model for MC runs
    renewable_model = DeviceModel(
        RenewableDispatch,
        RenewableFullDispatch;
        time_series_names = Dict(ActivePowerTimeSeriesParameter => renewable_timeseries_name)
    )
    # Assign custom RenewableDispatch model to template
    set_device_model!(template_uc, renewable_model)
end

function define_branch_model(template_uc)
    # define the branch model (static branch -> add unbounded flow variables and use flow constraints)
    set_device_model!(template_uc, AreaInterchange, StaticBranch)  #Q: is this defining TX?
end

function define_network_model(template_uc)
    # define our area balance power model to produce our zonal topology (Sienna default is copperplate)
    
    area_interchange = NetworkModel(
        AreaBalancePowerModel, #creates power balance constraints for each area
        use_slacks=false, #disable slack variables; i.e. prevent line flow exceedance
    )
    #assign the area_interchange object from above as our network model 
    set_network_model!(template_uc, area_interchange)
end

function build_and_execute_simulation(template_uc, sys::System, paths::Dict; decision_name::String)
    UC_decision = DecisionModel(
        template_uc,
        sys;
        name = decision_name,
        optimizer = optimizer_with_attributes(Gurobi.Optimizer, "MIPGap" => 1e-2),
        system_to_file = false, # write the json and hf to file
        initialize_model = true, # what does this do?
        optimizer_solve_log_print = true,
        direct_mode_optimizer = true,
        rebuild_model = false,
        store_variable_names = true,
        calculate_conflict = true,
        export_optimization_model = true, # this exports the LP
    )

    # Create Simulation Models
    sim_model = SimulationModels(
        decision_models = [UC_decision],
    )

    # Define Simulation Sequence
    sim_sequence = SimulationSequence(
        models = sim_model,
    )

    # Define Simulation
    sim = Simulation(
        name = "test-sim",
        steps = 3,  # Steps in your simulation
        models = sim_model,
        sequence = sim_sequence,
        simulation_folder = mktempdir(paths[:sim_files_dir], cleanup = true),
    )

    # Build the simulation folder
    build!(sim; console_level = Logging.Info,)

    # Execute the simulation
    execute!(sim, enable_progress_bar = true)

    # Return sim and UC_decision
    return sim, UC_decision

end

function query_write_export_results(sim::Simulation, path_scenario::String, uc_decision_name::String)
    ###########################
    # Query Results
    ###########################
    sim_results = SimulationResults(sim)
    results = get_decision_problem_results(sim_results, uc_decision_name) # UC stage result metadata

    # Input Parameters
    load_parameter = read_realized_parameter(results, "ActivePowerTimeSeriesParameter__PowerLoad")
    renewable_parameter = read_realized_parameter(results, "ActivePowerTimeSeriesParameter__RenewableDispatch")
    thermal_parameter = read_realized_parameter(results, "ActivePowerTimeSeriesParameter__ThermalStandard")    
    
    # Output Variables
    thermal_active_power = read_realized_variable(results, "ActivePowerVariable__ThermalStandard")
    renewable_active_power = read_realized_variable(results, "ActivePowerVariable__RenewableDispatch")
    gen_active_power = hcat(thermal_active_power, select(renewable_active_power, Not(1)))
    tx_flow = read_realized_variable(results, "FlowActivePowerVariable__AreaInterchange")
    storage_charge = read_realized_variable(results, "ActivePowerInVariable__EnergyReservoirStorage")
    storage_discharge = read_realized_variable(results, "ActivePowerOutVariable__EnergyReservoirStorage")
    
    # Output Expressions
    power_balance = read_realized_expression(results, "ActivePowerBalance__Area")
    
    # Get Production Costs
    pc_thermal = read_realized_expression(results, "ProductionCostExpression__ThermalStandard")
    pc_renewable = read_realized_expression(results, "ProductionCostExpression__RenewableDispatch")
    # pc_hydro = read_realized_expression(results, "ProductionCostExpression__HydroDispatch")
    all_pc = hcat(pc_thermal,select(pc_renewable, Not(1)))
    # all_pc = hcat(pc_thermal,select(pc_renewable, Not(1)), select(pc_hydro, Not(1)))

    ###########################
    # Export Results
    ###########################
    # Define output paths and write dataframes to CSV
    CSV.write(joinpath(path_scenario, "load_active_power.csv"), load_parameter) # Input values
    CSV.write(joinpath(path_scenario, "renewable_parameters.csv"), renewable_parameter) # Input values
    CSV.write(joinpath(path_scenario, "thermal_parameters.csv"), thermal_parameter) # Input values
    CSV.write(joinpath(path_scenario, "renewable_active_power.csv"), renewable_active_power)
    CSV.write(joinpath(path_scenario, "generator_active_power.csv"), gen_active_power)
    CSV.write(joinpath(path_scenario, "tx_flow.csv"), tx_flow)
    CSV.write(joinpath(path_scenario, "storage_charge.csv"), storage_charge)
    CSV.write(joinpath(path_scenario, "storage_discharge.csv"), storage_discharge)
    CSV.write(joinpath(path_scenario, "power_balance.csv"), power_balance)
    CSV.write(joinpath(path_scenario, "production_costs.csv"), all_pc)

    # Export generation by fuel type
    all_gen_data = PowerAnalytics.get_generation_data(results)
    cat = PowerAnalytics.make_fuel_dictionary(sys)
    fuel = PowerAnalytics.categorize_data(all_gen_data.data, cat; curtailment = true, slacks = true)
    fuel_agg = PowerAnalytics.combine_categories(fuel)
    CSV.write(joinpath(path_scenario, "generation_by_fuel.csv"), fuel_agg)
end


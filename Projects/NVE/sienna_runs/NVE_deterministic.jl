
function initialize_paths_and_inputs(r2x_output_name::String, scenario_name::String)
    # Define root directory and related paths
    current_dir = pwd()

    # Check if "Projects" exists in the path
    if occursin("Projects", current_dir)
        # Split the path and remove "Projects"
        root_dir = joinpath(splitdir(current_dir)[1:end-1]...)  # Remove the last part of project
    else
        root_dir = current_dir
    end
    # @show root_dir

    data_dir = joinpath(root_dir, "Projects", "NVE") # R2X output
    output_dir = joinpath(root_dir, "Projects", "NVE", "sienna_runs", "run_output") # Sienna outputs

    # Deterministic inputs
    scenario_dir = joinpath(output_dir, scenario_name) # Scenario name passed as argument

    # Stochastic inputs
    solar_dir = joinpath(data_dir, "LOLP_inputs", "solar")
    wind_dir = joinpath(data_dir, "LOLP_inputs", "wind")
    load_dir = joinpath(data_dir, "LOLP_inputs", "load")

    # Ensure the scenario directory exists
    if !isdir(scenario_dir)
        mkdir(scenario_dir)
    end

    # Point to the appropriate input file
    descriptors = joinpath(root_dir, "Projects", "NVE", "sienna_runs", "user_descriptors_$r2x_output_name.yaml")

    # Return all paths as a dictionary for easy access
    return Dict(
        :root_dir => root_dir,
        :data_dir => data_dir,
        :output_dir => output_dir,
        :scenario_dir => scenario_dir,
        :solar_dir => solar_dir,
        :wind_dir => wind_dir,
        :load_dir => load_dir,
        :descriptors => descriptors
    )
end

function build_system_from_r2x(paths::Dict{Symbol, String}, r2x_output_name::String)
    # Base power for the system
    base_power = 1.0

    # Extract paths from the dictionary
    root_dir = paths[:root_dir]
    data_dir = paths[:data_dir]

    # Define paths to input files
    descriptors = joinpath(root_dir, "Projects", "NVE", "sienna_runs", "user_descriptors_$r2x_output_name.yaml")
    generator_mapping = joinpath(root_dir, "Projects", "NVE", "sienna_runs", "generator_mapping.yaml")
    timeseries_metadata_file = joinpath(root_dir, "Projects", "NVE", r2x_output_name, "timeseries_pointers.json")

    # Load the data
    data = PowerSystemTableData(
        joinpath(data_dir, r2x_output_name),
        base_power,
        descriptors;
        generator_mapping_file = generator_mapping,
        timeseries_metadata_file = timeseries_metadata_file,
    )

    # Define the path to the PWL output CSV
    pw_file = joinpath(data_dir, r2x_output_name, "generator_PWL_output.csv")

    # Read the PWL output into a DataFrame
    pw_data = DataFrame(CSV.File(pw_file))

    # Create the system
    sys = System(data, time_series_in_memory = true)

    # Return the system and the PWL data
    return sys, pw_data
end


function modify_system!(sys::System, pw_data::DataFrame, data_dir::String, r2x_output_name::String)
    #create area interchanges
    create_area_interchanges(sys, joinpath(data_dir, r2x_output_name))
    attach_reserve_requirements(sys, joinpath(data_dir, r2x_output_name))

    # Define initial state of charge (SOC) for storage
    for storage in get_components(EnergyReservoirStorage, sys)
        set_initial_storage_capacity_level!(storage, 0.33)
    end

    # Set generator services
    for gen in get_components(ThermalStandard, sys)
        if !occursin("Purchases", get_name(gen))
            eligible_services = vcat(
                collect(get_components(VariableReserve{ReserveUp}, sys))
                # Uncomment the line below to include Non-Spinning Reserves
                # collect(get_components(VariableReserveNonSpinning, sys))
            )
            set_services!(gen, eligible_services)
        end
    end

    # Disable all reserves
    for reserve in get_components(VariableReserve{ReserveUp}, sys)
        set_available!(reserve, false)
    end

    # Set market purchases availability to false
    set_available!(get_component(ThermalStandard, sys, "Southern Purchases (NVP)"), false)
    set_available!(get_component(ThermalStandard, sys, "Northern Purchases (Sierra)"), false)
    set_available!(get_component(RenewableDispatch, sys, "Sierra Solar II"), false)

    # Enable hydro availability
    for hydro in get_components(HydroDispatch, sys)
        set_available!(hydro, true)
    end

    # Modify generator heat rates
    for row in eachrow(pw_data)
        generator_name = row.name
        generator = get_component(ThermalStandard, sys, generator_name)
        generator_op_cost = get_operation_cost(generator)

        new_vc = PiecewisePointCurve(
            [
                (row.output_point_0, row.heat_rate_avg_0),
                (row.output_point_1, row.heat_rate_incr_1),
                (row.output_point_2, row.heat_rate_incr_2),
                (row.output_point_3, row.heat_rate_incr_3),
                (row.output_point_4, row.heat_rate_incr_4),
                (row.output_point_5, row.heat_rate_incr_5),
            ]
        )

        fuel_curve = FuelCurve(
            value_curve = new_vc,
            fuel_cost = generator_op_cost.variable.fuel_cost
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
    set_bustype!(get_component(ACBus, sys, "Sierra"), "REF");
end

function define_device_model_non_weather(template_uc)
    # Define custom DeviceModel for ThermalStandard with time-varying max_active_power
    thermal_model = DeviceModel(
        ThermalStandard,
        ThermalStandardUnitCommitment;
        time_series_names = Dict(ActivePowerTimeSeriesParameter => "max_active_power")
    )
    set_device_model!(template_uc, thermal_model)

    # Define Hydro model
    set_device_model!(template_uc, HydroDispatch, HydroDispatchRunOfRiver)

    # Define custom DeviceModel for EnergyReservoirStorage
    storage_model = DeviceModel(
        EnergyReservoirStorage,
        StorageDispatchWithReserves;
        attributes = Dict(
            "reservation" => true,  # Prevents discharging and charging in the same period
            "cycling_limits" => false,
            "energy_target" => false,
            "complete_coverage" => false,
            "regularization" => true  # Regularizes storage dispatch to prevent large swings in dispatch
        ),
    )
    set_device_model!(template_uc, storage_model)
end

function define_device_model_weather(template_uc; load_timeseries_name, renewable_timeseries_name)
    # Define PowerLoad model
    load_model = DeviceModel(
        PowerLoad,
        StaticPowerLoad;
        time_series_names = Dict(ActivePowerTimeSeriesParameter => load_timeseries_name)
    )
    set_device_model!(template_uc, load_model)

    # Define RenewableDispatch model
    renewable_model = DeviceModel(
        RenewableDispatch,
        RenewableFullDispatch;
        time_series_names = Dict(ActivePowerTimeSeriesParameter => renewable_timeseries_name)
    )
    set_device_model!(template_uc, renewable_model)
end

function define_branch_model(template_uc)
    # define the branch model (static branch -> add unbounded flow variables and use flow constraints)
    set_device_model!(template_uc, AreaInterchange, StaticBranch) #Q: is this defining TX?
end

function define_network_model(template_uc)
    # define our area balance power model to produce our zonal topology (Sienna default is copperplate)
    area_interchange = NetworkModel(
        AreaBalancePowerModel, #creates power balance constraints for each area
        use_slacks=false, #disable slack variables; i.e. prevent line flow exceedances
        # PTDF_matrix=PTDF(sys),
        # duals=[CopperPlateBalanceConstraint],
    )

    #assign the area_interchange object from above as our network model 
    set_network_model!(template_uc, area_interchange)
end

function build_and_execute_simulation(template_uc, sys, paths::Dict; decision_name::String)
    UC_decision = DecisionModel(
        template_uc,
        sys;
        name = decision_name,
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
        steps = 5,  # Steps in your simulation
        models = sim_model,
        sequence = sim_sequence,
        simulation_folder = mktempdir(joinpath(paths[:output_dir], "simulation_files"), cleanup = true),
    )

    # Build the simulation folder
    build!(sim; console_level = Logging.Info)

    # Execute the simulation
    execute!(sim, enable_progress_bar = true)

    # Return sim and UC_decision
    return sim, UC_decision

end

function query_write_export_results(sim::Simulation, paths::Dict)
    ###########################
    # Query Results
    ###########################
    sim_results = SimulationResults(sim)
    results = get_decision_problem_results(sim_results, "DA_WY_1998") # UC stage result metadata

    # Get Production Costs
    pc_thermal = read_realized_expression(results, "ProductionCostExpression__ThermalStandard")
    pc_renewable = read_realized_expression(results, "ProductionCostExpression__RenewableDispatch")
    pc_hydro = read_realized_expression(results, "ProductionCostExpression__HydroDispatch")
    all_pc = hcat(pc_thermal, select(pc_renewable, Not(1)), select(pc_hydro, Not(1)))

    # Input Parameters
    load_parameter = read_realized_parameter(results, "ActivePowerTimeSeriesParameter__PowerLoad")
    renewable_parameter = read_realized_parameter(results, "ActivePowerTimeSeriesParameter__RenewableDispatch")

    # Output Expressions
    power_balance = read_realized_expression(results, "ActivePowerBalance__System")

    # Output Variables
    thermal_active_power = read_realized_variable(results, "ActivePowerVariable__ThermalStandard")
    renewable_active_power = read_realized_variable(results, "ActivePowerVariable__RenewableDispatch")
    gen_active_power = hcat(thermal_active_power, select(renewable_active_power, Not(1)))
    tx_flow = read_realized_variable(results, "FlowActivePowerVariable__AreaInterchange")

    storage_discharge = read_realized_variable(results, "StorageEnergyOutput__EnergyReservoirStorage")
    storage_charge = read_realized_variable(results, "ActivePowerInVariable__EnergyReservoirStorage")

    ###########################
    # Export Results
    ###########################
    # Define output paths and write dataframes to CSV
    CSV.write(joinpath(paths[:scenario_dir], "storage_charge.csv"), storage_charge)
    CSV.write(joinpath(paths[:scenario_dir], "storage_discharge.csv"), storage_discharge)
    CSV.write(joinpath(paths[:scenario_dir], "load_active_power.csv"), load_parameter)
    CSV.write(joinpath(paths[:scenario_dir], "renewable_parameters.csv"), renewable_parameter) # Input values
    CSV.write(joinpath(paths[:scenario_dir], "renewable_active_power.csv"), renewable_active_power) # Output values
    CSV.write(joinpath(paths[:scenario_dir], "generator_active_power.csv"), gen_active_power)
    CSV.write(joinpath(paths[:scenario_dir], "tx_flow.csv"), tx_flow)
    CSV.write(joinpath(paths[:scenario_dir], "production_costs.csv"), all_pc)
    CSV.write(joinpath(paths[:scenario_dir], "power_balance.csv"), power_balance)

    # Export generation by fuel type (requires PowerAnalytics.jl)
    #= all_gen_data = PowerAnalytics.get_generation_data(results)
    cat = PowerAnalytics.make_fuel_dictionary(sys)
    fuel = PowerAnalytics.categorize_data(all_gen_data.data, cat; curtailment = true, slacks = true)
    fuel_agg = PowerAnalytics.combine_categories(fuel)
    CSV.write(joinpath(paths[:scenario_dir] * "generation_by_fuel.csv"), fuel_agg) =#
end
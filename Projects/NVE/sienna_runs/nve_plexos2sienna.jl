
using Pkg
using Revise
using PowerSystems
using PowerSimulations
using PowerSystemCaseBuilder
using HydroPowerSimulations
using StorageSystemsSimulations
using PowerAnalytics
using Gurobi # solver
using Dates
using Logging
using DataFrames
using Plots
using CSV
using TimeSeries

include("sienna_runs/_helpers.jl")
# include("_helpers.jl")

#Set all Paths
data_dir = "" #"Projects/NVE/" # r2x output
output_dir =  data_dir * "sienna_runs/run_output/" # Sienna outputs

r2x_output_name = "output_stable_dec24"
scenario_dir = output_dir * "output_stable_dec24" # Change if youre creating a different sienna scenario
if !isdir(scenario_dir)
    mkdir(scenario_dir)
end

## Load and Save System From Parse R2X Data
logger = configure_logging(console_level=Logging.Info)
base_power = 1.0
descriptors = "sienna_runs/user_descriptors/"* r2x_output_name *".yaml"
generator_mapping = data_dir *"sienna_runs/generator_mapping.yaml"
timeseries_metadata_file = "" * r2x_output_name * "/timeseries_pointers.json"
data = PowerSystemTableData(
    data_dir * r2x_output_name,
    base_power,
    descriptors;
    generator_mapping_file = generator_mapping,
    timeseries_metadata_file = timeseries_metadata_file,
)
modify_data(data)
sys = System(data, time_series_in_memory= true)

pw_data = DataFrame(CSV.File(data_dir * r2x_output_name * "/generator_PWL_output.csv"))

###########################
# Save/Load the System
###########################
# to_json(sys, output_dir * "nve_system.json", force=true)
# sys = System(output_dir * "nve_system.json")

###########################
# Modify System
###########################
create_area_interchanges(sys, data_dir * r2x_output_name)
# attach_reserve_requirements(sys, data_dir * r2x_output_name)

########################### 
# Modifying Reserve Requirements
###########################
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

# Disable all reserves
for reserve in collect(get_components(VariableReserve{ReserveUp}, sys))
    set_available!(reserve, false)
end

######
# Modify Imports
######
# Either Constrain the Market imports
constrain_market_imports(sys, data_dir * r2x_output_name)
# set_market_imports_availability(sys, false)

set_available!(get_component(RenewableDispatch, sys, "Sierra Solar II"), false)

for hydro in get_components(HydroDispatch, sys)
    set_available!(hydro, false)
end

for thermal_gen in get_components(ThermalStandard, sys)
    set_active_power!(thermal_gen, 0.0)
end

##############
## Additional network edits
##############
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


# No Slack bus was created, set our own.
set_bustype!(get_component(ACBus, sys, "Nevada Power"), "REF")
transform_single_time_series!(sys, Hour(48), Hour(24))

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

############################################################
##  Network Simulation
############################################################
template_uc = ProblemTemplate()
thermal_model = DeviceModel(ThermalStandard, ThermalStandardUnitCommitment; time_series_names = Dict(ActivePowerTimeSeriesParameter => "max_active_power"))
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
        "regularization" => false, # Regularizes storage dispatch to prevent large swings in dispatch.
    ),
)
set_device_model!(template_uc, storage_model)

# set_service_model!(template_uc, ServiceModel(VariableReserveNonSpinning, NonSpinningReserve; use_slacks = true))
# set_service_model!(template_uc, ServiceModel(VariableReserve{ReserveUp}, RangeReserve; use_slacks = true))

# copper_plate = NetworkModel(
#         CopperPlatePowerModel,
#         use_slacks=true,
#         # PTDF_matrix=PTDF(sys),
#         # duals=[CopperPlateBalanceConstraint],
#     )
# set_network_model!(template_uc, copper_plate)

area_interchange = NetworkModel(
        AreaBalancePowerModel,
        use_slacks=false,
    )
set_device_model!(template_uc, AreaInterchange, StaticBranch) 
set_network_model!(template_uc, area_interchange)

# Build Decision Model and Simulaiton
UC_decision = DecisionModel(
    template_uc,
    sys;
    name = "lookahead_UC",
    optimizer = optimizer_with_attributes(Gurobi.Optimizer, "MIPGap" => 1e-2),
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
    steps = 3,  # Step in your simulation
    models = sim_model,
    sequence = sim_sequence,
    simulation_folder = mktempdir(output_dir * "simulation_files", cleanup = true),
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
# pc_hydro = read_realized_expression(results, "ProductionCostExpression__HydroDispatch")
all_pc = hcat(pc_thermal,select(pc_renewable, Not(1)))
# all_pc = hcat(pc_thermal,select(pc_renewable, Not(1)), select(pc_hydro, Not(1)))

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
CSV.write(scenario_dir * "/storage_charge.csv", storage_charge)
CSV.write(scenario_dir * "/storage_discharge.csv", storage_discharge)
CSV.write(scenario_dir * "/load_active_power.csv", load_parameter)
CSV.write(scenario_dir * "/renewable_parameters.csv", renewable_parameter)
CSV.write(scenario_dir * "/renewable_active_power.csv", renewable_active_power)
CSV.write(scenario_dir * "/generator_active_power.csv", gen_active_power)
CSV.write(scenario_dir * "/tx_flow.csv", tx_flow)
CSV.write(scenario_dir * "/production_costs.csv", all_pc)

# ### Post Process and Analyze Network results
# plot_dataframe(load)
# plot_dataframe(thermal_active_power)

# Export generation by fuel type
all_gen_data = PowerAnalytics.get_generation_data(results)
cat = PowerAnalytics.make_fuel_dictionary(sys)
fuel = PowerAnalytics.categorize_data(all_gen_data.data, cat; curtailment = true, slacks = true)
fuel_agg = PowerAnalytics.combine_categories(fuel)
CSV.write(scenario_dir * "/generation_by_fuel.csv", fuel_agg)

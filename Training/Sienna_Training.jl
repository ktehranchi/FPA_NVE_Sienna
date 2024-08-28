"""
First Step towards this demo is to create a Julia Project Enviornment for the training session. Within your Julia REPL, you can create a new project by running the following command:
    generate demo_training
This will create a new folder called demo_training with the following structure:
    demo_training/
        Project.toml
        Manifest.toml
        src/
            demo_training.jl
These files will be used to manage the dependencies for the training session.

Next, you should add the packages you will use in the training within the REPL by running the following commands:
    ] add PowerSystems PowerSimulations PowerSystemCaseBuilder PowerGraphics HiGHS Gurobi Dates Logging DataFrames Plots

Everytime you open a Julia REPL to work with sienna you can navigate to the folder which contains the Project.toml and type '] activate .' to activate the project environment. This will load the dependencies you added in the previous step.
"""
using Pkg
using PowerSystems
using PowerSimulations
using PowerSystemCaseBuilder
using PowerGraphics
using HiGHS # solver
using Gurobi # solver
using Dates
using Logging
using DataFrames
using Plots

###########################
#### PowerSystems Tutorial
###########################
""""
In this example we review loading an example network, accessing its components, modifying data in the system, and running a simple simulation with a CopperPlatePowerModel. 
"""
# Load a System from the PowerSystemsCaseBuilder.jl library
sys_DA = build_system(PSISystems, "c_sys5_pjm")

# Examples of Accessing Component Data (https://nrel-sienna.github.io/PowerSystems.jl/stable/tutorials/basics/#Accessing-System-Data)
# Often you will want to understand the potential arguements of PSI component or model constructors. Using the help ? functionality will give you access to the docstring information.
# For example:
# ? show_components - will show you the fields that the show_components function has.
# ? ThermalStandard - will show you the fields that the ThermalStandard component has.

show_components(ThermalStandard, sys_DA, [:bus, :must_run, :active_power_limits])

# Next lets imagine we want to set the availability of a generator to false. We can use the set_available function to do this.
# get_components returns an iterable of components that match the filter function
# set_available(component, True/False) modifies the field availability of the device in the model. 
# Always use set_X or get_X functions to modify or return fields.
for g in get_components(x -> occursin("Park", get_name(x),), ThermalStandard, sys_DA)
    set_available!(g, false) 
end

gens = get_components(x -> occursin("a", get_name(x),), ThermalStandard, sys_DA)
collect(gens) # to collect into an array
collect(gens)[1] # to access the first element

# Example of getting a component by name
gen = get_component(ThermalStandard, sys_DA, "Alta")

# Instead of typing gen.name to return the name of the component, we should always us the get_X function. Likewise for setting the name we should use set_X!
@show get_name(gen);

# Lets undo setting the availability to false
for g in get_components(x -> occursin("Park", get_name(x),), ThermalStandard, sys_DA)
    set_available!(g, true) 
end

# To set up a DA simulation we need to create the forecast DeterministicSingleTimeSeries from the SingleTimeSeries Object
transform_single_time_series!(sys_DA, Hour(24), Hour(24))

# Examine the Difference bewteen Forecast (DeterministicSingleTimeSeries) and StaticTimeSeries (SingleTimeSeries)
# https://nrel-sienna.github.io/PowerSystems.jl/stable/modeler_guide/time_series/#Retrieving-time-series-data
loads = collect(get_components(PowerLoad, sys_DA))
get_forecast_initial_times(sys_DA)
show_time_series(loads[1]) # Load 1 has a forecast and a static time series

# get_time_series(loads[1], get_time_series_keys(loads[1]))

ts_arr = get_time_series_array(SingleTimeSeries, loads[1], "max_active_power")

plot!(ts_arr, label = "Static Time Series")

ts_forecast = get_time_series_array(Deterministic, loads[1], "max_active_power")
plot!(ts_forecast, label = "Forecast Time Series")

sys_DA # to view change

######################################
############## PowerSimulations Tutorial
######################################

##########
## Simple Copper Plate Network Example
##########
template_uc = ProblemTemplate()

set_device_model!(template_uc, ThermalStandard, ThermalBasicUnitCommitment)
set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_uc, PowerLoad, StaticPowerLoad)

set_device_model!(template_uc, Line, StaticBranch)
set_network_model!(template_uc, NetworkModel(CopperPlatePowerModel))

mod = DecisionModel(
    template_uc,
    sys_DA;
    name = "UC",
    optimizer = optimizer_with_attributes(HiGHS.Optimizer),
    system_to_file = false,
    initialize_model = true,
    optimizer_solve_log_print = true,
    direct_mode_optimizer = true,
    rebuild_model = false,
    store_variable_names = true,
    calculate_conflict = false,
)

build!(mod; console_level = Logging.Info, output_dir = ".")

solve!(mod)

# https://nrel-sienna.github.io/PowerSimulations.jl/latest/modeler_guide/read_results/
results = OptimizationProblemResults(mod) 
thermal_active_power = read_variable(results, "ActivePowerVariable__ThermalStandard")
load = read_parameter(results, "ActivePowerTimeSeriesParameter__PowerLoad")

### Post Process and Analyze Network results
plot_dataframe(load)
plot_dataframe(thermal_active_power)

############################
### Now Lets Create a powersimulations Optimization Problem with an Area Balance model
############################

sys_DA = build_system(PSISystems, "c_sys5_pjm")

# Our Network does not have Areas in the System. First we create Areas then assign Buses their respective Area
for bus in get_components(ACBus, sys_DA)
    add_component!(sys_DA, Area(name = get_name(bus)))
    set_area!(bus, get_component(Area, sys_DA, get_name(bus)))
    # set_area!(bus, Area(get_name(bus))) # This is incorrect since we are not referencing the Area Object that we just created and added to the system
end
show_components(ACBus, sys_DA, [:area])
show_components(Area, sys_DA)

# In an AreaBalancePowerModel, a given area needs to have an AreaInterchange Objects that defines the Branch constraint between areas.
# Create new AreaInterchange for each Arc defined in the system
for line in get_components(Line, sys_DA)
    arc = get_arc(line) # An Arc defines the topology of the network. Each line is assigned an Arc.
    from_bus = get_from(arc)
    to_bus = get_to(arc)
    add_component!(
        sys_DA, 
        AreaInterchange(
            name = get_name(line),
            active_power_flow = 0.0,
            available = true,
            from_area = get_area(from_bus),
            to_area = get_area(to_bus),
            flow_limits = (from_to= get_rating(line), to_from= get_rating(line))
        )
    )
end
show_components(AreaInterchange, sys_DA)
sys_DA

# We need to create the forecast DeterministicSingleTimeSeries from the SingleTimeSeries Object
transform_single_time_series!(sys_DA, Hour(24), Hour(24))

###########################
#### PowerSimulations
############################
template_uc = ProblemTemplate()

# Note we needed to add the AreaInterchange device model since we are modeling AreaBalancePowerModel
set_device_model!(template_uc, ThermalStandard, ThermalBasicUnitCommitment)
set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_uc, PowerLoad, StaticPowerLoad)

set_device_model!(template_uc, AreaInterchange, StaticBranch) 
set_network_model!(template_uc, NetworkModel(AreaBalancePowerModel))

mod = DecisionModel(
    template_uc,
    sys_DA;
    name = "UC",
    optimizer = optimizer_with_attributes(Gurobi.Optimizer),
    system_to_file = false,
    initialize_model = true,
    optimizer_solve_log_print = true,
    direct_mode_optimizer = true,
    rebuild_model = false,
    store_variable_names = true,
    calculate_conflict = true, # This will help you debug issues in simulation formulation
)

build!(mod; console_level = Logging.Info, output_dir = ".")

solve!(mod)

# https://nrel-sienna.github.io/PowerSimulations.jl/latest/modeler_guide/read_results/
results = OptimizationProblemResults(mod) 
thermal_active_power = read_variable(results, "ActivePowerVariable__ThermalStandard")
load = read_parameter(results, "ActivePowerTimeSeriesParameter__PowerLoad")

### Post Process and Analyze Network results

# Create Plot of Network Loads
plot_dataframe(thermal_active_power)
plot_fuel(results; stair = true)


###########
#### Reviewing the Difference bewteen OptimizationProblems and Simulations in PowerSimulations
###########

"""
In PSI nomenclature, a DecisionModel is a single optimization problem that is part of a simulation. The SimulationModel is a container for multiple decision models. FeedForward objects define the relation between each decision model. The SimulationSequence is a container for a SimulationModel and the FeedForward objects. The SimulationSequence is used to define interproblem chronology between the individual decision models. The Simulation object is the top level object that contains the SimulationSequence and the SimulationModel. 

For single decision model problems it is possible to solve as a single "OptimizationProblem" or Through a SimulationModel.
"""

# Lets repeat the above simulation except model it as a single Simulation Object instead of a singular decision model

#### PowerSimulations Usage
template_uc = ProblemTemplate()

# Note we needed to add the AreaInterchange device model since we are modeling AreaBalancePowerModel
set_device_model!(template_uc, ThermalStandard, ThermalBasicUnitCommitment)
set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_uc, PowerLoad, StaticPowerLoad)

set_device_model!(template_uc, AreaInterchange, StaticBranch) 
set_network_model!(template_uc, NetworkModel(AreaBalancePowerModel))

dec_mod = DecisionModel(
    template_uc,
    sys_DA;
    name = "UC",
    optimizer = optimizer_with_attributes(Gurobi.Optimizer),
    system_to_file = false,
    initialize_model = true,
    optimizer_solve_log_print = true,
    direct_mode_optimizer = true,
    rebuild_model = false,
    store_variable_names = true,
    calculate_conflict = true, # This will help you debug issues in simulation formulation
)


sim_model = SimulationModels(
    decision_models = [dec_mod],
    )

sim_sequence = SimulationSequence(
    models = sim_model,
    # ini_cond_chronology = InterProblemChronology(),
    # feedforwards = feedforward,
    )

sim = Simulation(
    name = "test-sim",
    steps = 1,
    models = sim_model,
    sequence = sim_sequence,
    simulation_folder = mktempdir(".", cleanup = true),
)

build!(sim, console_level = Logging.Info)

execute!(sim, enable_progress_bar = true)

sim_results = SimulationResults(sim);
uc_sim_results = get_decision_problem_results(sim_results, "UC"); # UC stage result metadata

using PowerGraphics
plot_fuel(uc_sim_results; stair = true)



###########
## Multi-Stage Simulation Example
###########

"""
In this example we will set up a multi-stage DA-RT simulation sequence with the same system as above. 
"""

# Load the real-time system
sys_DA = build_system(PSISystems, "c_sys5_pjm")
sys_rt = build_system(PSISystems, "c_sys5_pjm_rt")

# You can compare the difference in the resolution of the timeseries data between the DA and RT systems
@show get_time_series_resolutions(sys_DA)
@show get_time_series_resolutions(sys_rt)

# Create forcast for the RT system
# (Sys, Horizon of forecast, Interval of update)
transform_single_time_series!(sys_DA, Hour(24), Hour(24))
transform_single_time_series!(sys_rt, Hour(2), Minute(15))

#### PowerSimulations

template_uc = template_unit_commitment()

set_device_model!(template_uc, ThermalStandard, ThermalBasicUnitCommitment)
set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_uc, PowerLoad, StaticPowerLoad)

set_device_model!(template_uc, Line, StaticBranch)
set_network_model!(template_uc, NetworkModel(CopperPlatePowerModel))


template_ed = template_economic_dispatch()

set_device_model!(template_ed, ThermalStandard, ThermalStandardDispatch) # Note: This is different from the UC model
set_device_model!(template_ed, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_ed, PowerLoad, StaticPowerLoad)

set_device_model!(template_ed, Line, StaticBranch)
set_network_model!(template_ed, NetworkModel(CopperPlatePowerModel))


dec_mod_UC = DecisionModel(
    template_uc,
    sys_DA;
    name = "UC",
    optimizer = optimizer_with_attributes(Gurobi.Optimizer),
    system_to_file = false,
    initialize_model = true,
    optimizer_solve_log_print = true,
    direct_mode_optimizer = true,
    rebuild_model = false,
    store_variable_names = true,
    calculate_conflict = true, # This will help you debug issues in simulation formulation
)


dec_mod_ed = DecisionModel(
    template_ed,
    sys_rt;
    name = "ED",
    optimizer = optimizer_with_attributes(Gurobi.Optimizer),
    system_to_file = false,
    initialize_model = true,
    optimizer_solve_log_print = false,
    direct_mode_optimizer = true,
    rebuild_model = false,
    store_variable_names = true,
    calculate_conflict = true, # This will help you debug issues in simulation formulation
)

sim_model = SimulationModels(
    decision_models = [dec_mod_UC, dec_mod_ed],
    )

feedforward = Dict(
    "ED" => [
        SemiContinuousFeedforward(
            component_type = ThermalStandard,
            source = OnVariable,
            affected_values = [ActivePowerVariable],
        ),
    ],
)

sim_sequence = SimulationSequence(
    models = sim_model,
    ini_cond_chronology = InterProblemChronology(),
    feedforwards = feedforward,
    )

sim = Simulation(
    name = "test-sim",
    steps = 1,
    models = sim_model,
    sequence = sim_sequence,
    simulation_folder = mktempdir("", cleanup = true)
)

build!(sim, console_level = Logging.Info)

execute!(sim, enable_progress_bar = true)

sim_results = SimulationResults(sim);
uc_sim_results = get_decision_problem_results(sim_results, "UC"); # UC stage result metadata
ed_sim_results = get_decision_problem_results(sim_results, "ED"); # ED stage result metadata

using PowerGraphics
plot_fuel(uc_sim_results; stair = true)
plot_fuel(ed_sim_results; stair = true)



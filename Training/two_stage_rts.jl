using PowerSystems
using PowerSystemCaseBuilder
using PowerSimulations
using HiGHS
using Logging
using Gurobi

sys_DA = build_system(PSISystems, "RTS_GMLC_DA_sys")
sys_RT = build_system(PSISystems, "RTS_GMLC_RT_sys")


for g in get_components(x -> occursin("SYNC_COND", get_name(x),), ThermalStandard, sys_DA)
    set_available!(g, false)
end

for g in get_components(x -> occursin("SYNC_COND", get_name(x),), ThermalStandard, sys_RT)
    set_available!(g, false)
end


template_uc = template_unit_commitment()
set_device_model!(template_uc, ThermalStandard, ThermalStandardUnitCommitment)
set_network_model!(template_uc, NetworkModel(PTDFPowerModel))

template_ed = template_economic_dispatch()
#Not official way to clear models. Needs a new function to do this
empty!(template_ed.services)
set_device_model!(template_ed, ThermalStandard, ThermalStandardDispatch)
set_network_model!(template_ed, NetworkModel(PTDFPowerModel))

solver = optimizer_with_attributes(Gurobi.Optimizer, "MIPGap" => 0.01)


models = SimulationModels(
    decision_models = [
        DecisionModel(template_uc, sys_DA, optimizer = solver, name = "UC"),
        DecisionModel(template_ed, sys_RT, optimizer = solver, name = "ED"),
    ],
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

DA_ed_sequence = SimulationSequence(
    models = models,
    ini_cond_chronology = InterProblemChronology(),
    feedforwards = feedforward,
)

sim = Simulation(
    name = "rts-single_stage",
    steps = 6,
    models = models,
    sequence = DA_ed_sequence,
    simulation_folder = ".",
)

build!(sim; console_level = Logging.Info)

execute!(sim, enable_progress_bar = true)

results = SimulationResults(sim);
uc_results = get_decision_problem_results(results, "UC"); # UC stage 
ed_results = get_decision_problem_results(results, "ED"); # ED stage 

using PowerGraphics
plotlyjs()
plot_fuel(uc_results; stair = true)

gen = read_realized_variable(uc_results, "ActivePowerVariable__ThermalStandard")

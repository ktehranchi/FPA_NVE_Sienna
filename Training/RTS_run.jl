using PowerSystems
using PowerSimulations
const PSI = PowerSimulations
using PowerSystemCaseBuilder
using Dates
using HiGHS #solver
using Gurobi
using Logging

solver = optimizer_with_attributes(HiGHS.Optimizer, "mip_rel_gap" => 0.5) 

# sys_DA = build_system(PSISystems, "modified_RTS_GMLC_DA_sys")
# sys_RT = build_system(PSISystems, "modified_RTS_GMLC_RT_sys")

### Test real RTS
sys_DA = build_system(PSISystems, "RTS_GMLC_DA_sys")


set_units_base_system!(sys_DA, "NATURAL_UNITS")

show_components(ThermalStandard, sys_DA)
show_components(sys_DA, RenewableDispatch, [:base_power])

for g in get_components(x -> get_prime_mover_type(x)== PrimeMovers.PVe, RenewableDispatch, sys_DA)
    set_available!(g, false)
end

to_json(sys_DA, "sys_DA.json")




template_uc = template_unit_commitment()
set_device_model!(template_uc, ThermalStandard, ThermalStandardUnitCommitment)


f = collect(get_components(VariableReserve{ReserveUp}, sys_DA))
f[1]



template_uc = template_unit_commitment()

models = SimulationModels(
    decision_models = [
        DecisionModel(template_uc, sys_DA, optimizer = solver, name = "UC")
    ]
)

DA_sequence = SimulationSequence(
    models = models,
    ini_cond_chronology = InterProblemChronology()
)

sim = Simulation(
    name = "rts-test",
    steps = 2,
    models = models,
    sequence = DA_sequence,
    simulation_folder = mktempdir(".", cleanup = true)
)




build!(sim, console_level = Logging.Info)

execute!(sim, enable_progress_bar = true)


results = SimulationResults(sim);
uc_results = get_decision_problem_results(results, "UC"); # UC stage result metadata

using PowerGraphics
plot_fuel(uc_results, stair = true)


##################
template_ed = template_economic_dispatch(
    network = NetworkModel(PTDFPowerModel, use_slacks = true),
)

models = SimulationModels(
    decision_models = [
        DecisionModel(template_uc, sys_DA, optimizer = solver, name = "UC"),
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

DA_RT_sequence = SimulationSequence(
    models = models,
    ini_cond_chronology = InterProblemChronology(),
    feedforwards = feedforward,
)

sim = Simulation(
    name = "rts-test",
    steps = 2,
    models = models,
    sequence = DA_RT_sequence,
    simulation_folder = mktempdir(".", cleanup = true),
)

build!(sim, console_level = Logging.Info)

execute!(sim, enable_progress_bar = true)

results = SimulationResults(sim);
uc_results = get_decision_problem_results(results, "UC"); # UC stage result metadata
ed_results = get_decision_problem_results(results, "ED"); # ED stage result metadata

using PowerGraphics
plot_fuel(uc_results)
plot_fuel(ed_results)

read_parameter(
    ed_results,
    "ActivePowerTimeSeriesParameter__RenewableFix",
    initial_time = DateTime("2020-01-01T06:00:00"),
    count = 5,)
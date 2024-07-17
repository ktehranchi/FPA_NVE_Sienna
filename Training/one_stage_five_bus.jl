using PowerSystems
using PowerSystemCaseBuilder
using PowerSimulations
using HiGHS
using Logging
using Ipopt
using Dates

sys_DA = build_system(PSISystems, "c_sys5_pjm")
transform_single_time_series!(sys_DA, Hour(48), Hour(24))
sys_DA_rt = build_system(PSISystems, "c_sys5_pjm_rt")
transform_single_time_series!(sys_DA_rt, Hour(2), Minute(5))

template_uc = ProblemTemplate()
set_device_model!(template_uc, DeviceModel(Line, StaticBranch))
set_device_model!(template_uc, ThermalStandard, ThermalStandardUnitCommitment)
set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_uc, PowerLoad, StaticPowerLoad)
#set_network_model!(template_uc, NetworkModel(CopperPlatePowerModel))

#set_network_model!(template_uc, NetworkModel(CopperPlatePowerModel,duals=[CopperPlateBalanceConstraint]))
#set_network_model!(template_uc, NetworkModel(PTDFPowerModel,duals=[CopperPlateBalanceConstraint],))
set_network_model!(template_uc, NetworkModel(ACPPowerModel))

### Simulation
solver = optimizer_with_attributes(HiGHS.Optimizer)
template_uc = template_unit_commitment(;
    network = NetworkModel(PTDFPowerModel;
        reduce_radial_branches = true,
        use_slacks = true,
    ))

template_ed = template_economic_dispatch(;
    network = NetworkModel(PTDFPowerModel;
        reduce_radial_branches = true,
        use_slacks = true),
)

models = SimulationModels(;
    decision_models = [
        DecisionModel(
            template_uc,
            sys_DA;
            optimizer = optimizer_with_attributes(HiGHS.Optimizer),
            name = "UC",
            store_variable_names = true,
            optimizer_solve_log_print = false,
            direct_mode_optimizer = true,
        ),
        DecisionModel(
            template_ed,
            sys_DA_rt;
            optimizer = optimizer_with_attributes(Ipopt.Optimizer),
            name = "ED",
            store_variable_names = true,
            optimizer_solve_log_print = false,
        ),
    ],
)

feedforward = Dict(
    "ED" => [
        SemiContinuousFeedforward(;
            component_type = ThermalStandard,
            source = OnVariable,
            affected_values = [ActivePowerVariable],
        ),
    ],
)

DA_RT_sequence = SimulationSequence(;
    models = models,
    ini_cond_chronology = InterProblemChronology(),
    feedforwards = feedforward,
)

sim = Simulation(;
    name = "rts-test",
    steps = 2,
    models = models,
    sequence = DA_RT_sequence,
    simulation_folder = ".",
)

build!(sim; console_level = Logging.Info)
execute!(sim)

using PowerGraphics
plotlyjs()

using PowerSystems
using PowerSystemCaseBuilder
using PowerSimulations
using HydroPowerSimulations
using StorageSystemsSimulations
using HiGHS
using Logging
using Gurobi
using Dates

sys_twin_rts_DA = build_system(PSISystems, "AC_TWO_RTO_RTS_1Hr_sys")
sys_twin_rts_HA = build_system(PSISystems, "AC_TWO_RTO_RTS_5min_sys")
# Set lookahead to 2 hours for HA and interval to 1-hour
transform_single_time_series!(sys_twin_rts_HA, Hour(2), Hour(1))
sys_twin_rts_RT = build_system(PSISystems, "AC_TWO_RTO_RTS_5min_sys")
# Set lookahead to 1 5 min period for RT and interval to 5-minutes
transform_single_time_series!(sys_twin_rts_RT, Minute(5), Minute(5))

# UC model
template_uc =
    ProblemTemplate(
        NetworkModel(PTDFPowerModel;
            use_slacks = true),
    )

set_device_model!(template_uc, ThermalStandard, ThermalStandardUnitCommitment)
set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_uc, RenewableNonDispatch, FixedOutput)
set_device_model!(template_uc, PowerLoad, StaticPowerLoad)
set_device_model!(template_uc, Line, StaticBranchUnbounded)
set_device_model!(template_uc, Transformer2W, StaticBranchUnbounded)
set_device_model!(template_uc, TapTransformer, StaticBranchUnbounded)
set_device_model!(template_uc, HydroDispatch, FixedOutput)
set_device_model!(template_uc, HydroEnergyReservoir, FixedOutput)
# define battery model
storage_model = DeviceModel(
    EnergyReservoirStorage,
    StorageDispatchWithReserves;
    attributes = Dict(
        "reservation" => false,
        "cycling_limits" => false,
        "energy_target" => false,
        "complete_coverage" => false,
        "regularization" => true,
    ),
)
set_device_model!(template_uc, storage_model)

set_service_model!(
    template_uc,
    ServiceModel(VariableReserve{ReserveUp}, RangeReserve; use_slacks = true),
)
set_service_model!(
    template_uc,
    ServiceModel(VariableReserve{ReserveDown}, RangeReserve; use_slacks = true),
)

# add the HVDC line in case is present
set_device_model!(template_uc, TwoTerminalHVDCLine, HVDCTwoTerminalLossless)
set_device_model!(template_uc, MonitoredLine, StaticBranchUnbounded)

# HA model (fixing the hydro from the UC)
template_ha = deepcopy(template_uc)
set_device_model!(template_ha, ThermalStandard, ThermalStandardUnitCommitment)
set_device_model!(template_ha, HydroDispatch, HydroDispatchRunOfRiver)
set_device_model!(template_ha, HydroEnergyReservoir, HydroDispatchRunOfRiver)

# ED model
template_ed = deepcopy(template_uc)
set_device_model!(template_ed, ThermalStandard, ThermalStandardDispatch)
set_device_model!(template_ed, HydroDispatch, HydroDispatchRunOfRiver)
set_device_model!(template_ed, HydroEnergyReservoir, HydroDispatchRunOfRiver)
set_device_model!(template_uc, MonitoredLine, StaticBranchUnbounded)

models = SimulationModels(;
    decision_models = [
        DecisionModel(
            template_uc,
            sys_twin_rts_DA;
            name = "UC",
            optimizer = optimizer_with_attributes(
                Gurobi.Optimizer,),
            system_to_file = false,
            optimizer_solve_log_print = false,
            direct_mode_optimizer = true,
            store_variable_names = true,
            calculate_conflict = true,
        ),
        DecisionModel(
            template_ha,
            sys_twin_rts_HA;
            name = "HA",
            optimizer = optimizer_with_attributes(
                Gurobi.Optimizer),
            system_to_file = false,
            optimizer_solve_log_print = false,
            calculate_conflict = true,
            store_variable_names = true,
        ),
        DecisionModel(
            template_ed,
            sys_twin_rts_RT;
            name = "ED",
            optimizer = optimizer_with_attributes(
                Gurobi.Optimizer,),
            system_to_file = false,
            optimizer_solve_log_print = false,
            calculate_conflict = true,
            store_variable_names = true,
        ),
    ],
)

# define the different values for the simulation sequence
LBFF = LowerBoundFeedforward(;
    component_type = ThermalStandard,
    source = OnVariable,
    affected_values = [OnVariable],
)
FVFF_moniterd_line = FixValueFeedforward(;
    component_type = MonitoredLine,
    source = FlowActivePowerVariable,
    affected_values = [FlowActivePowerVariable],
)
LBFF_reserve_up = LowerBoundFeedforward(;
    component_type = VariableReserve{ReserveUp},
    source = ActivePowerReserveVariable,
    affected_values = [ActivePowerReserveVariable],
    add_slacks = true,
)
LBFF_reserve_dwn = LowerBoundFeedforward(;
    component_type = VariableReserve{ReserveDown},
    source = ActivePowerReserveVariable,
    affected_values = [ActivePowerReserveVariable],
    add_slacks = true,
)
SCFF = SemiContinuousFeedforward(;
    component_type = ThermalStandard,
    source = OnVariable,
    affected_values = [ActivePowerVariable],
)

ha_simulation_ff = Vector{PowerSimulations.AbstractAffectFeedforward}()
ed_simulation_ff = Vector{PowerSimulations.AbstractAffectFeedforward}()

push!(ha_simulation_ff, LBFF_reserve_up)       # LB on Reserve UP
push!(ha_simulation_ff, LBFF_reserve_dwn)      # LB on Reserve DOWN

push!(ed_simulation_ff, SCFF)
push!(ed_simulation_ff, LBFF_reserve_up)       # LB on Reserve UP
push!(ed_simulation_ff, LBFF_reserve_dwn)      # LB on Reserve DOWN

push!(ha_simulation_ff, FVFF_moniterd_line)
push!(ed_simulation_ff, FVFF_moniterd_line)

sequence = SimulationSequence(;
    models = models,
    feedforwards = Dict(
        "HA" => ha_simulation_ff,
        "ED" => ed_simulation_ff,
    ),
    ini_cond_chronology = InterProblemChronology(),
);

# use different names for saving the solution
sim = Simulation(;
    name = "sim",
    steps = 10,
    models = models,
    sequence = sequence,
    initial_time = DateTime("2020-01-01T00:00:00"),
    simulation_folder = mktempdir(),
);

build_out = build!(sim; console_level = Logging.Info, serialize = false)

execute_status = execute!(sim; enable_progress_bar = true);

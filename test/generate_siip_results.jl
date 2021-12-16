#####################################################
# Surya
# NREL
# December 2021
# Generate SIIP results to comapre with EGRET Results
#####################################################
# Required Packages
#####################################################
using PowerSystems
const PSY = PowerSystems
using PowerSimulations
const PSI = PowerSimulations

using Dates
using DataFrames
using CSV

using SCIP 
#####################################################
# RTS-GMLC System using PSY
#####################################################
rts_dir = "/Users/sdhulipa/Desktop/OneDrive - NREL/NREL-Github/temp/RTS-GMLC"
rts_src_dir = joinpath(rts_dir, "RTS_Data", "SourceData");
rts_siip_dir = joinpath(rts_dir, "RTS_Data", "FormattedData", "SIIP");

rawsys = PSY.PowerSystemTableData(
    rts_src_dir,
    100.0,
    joinpath(rts_siip_dir, "user_descriptors.yaml"),
    timeseries_metadata_file = joinpath(rts_siip_dir, "timeseries_pointers.json"),
    generator_mapping_file = joinpath(rts_siip_dir, "generator_mapping.yaml"),
);
#####################################################
# DA System - Transforming Single Time Series
#####################################################
sys_DA = PSY.System(rawsys; time_series_resolution = Dates.Hour(1));
PSY.transform_single_time_series!(sys_DA, 48, Dates.Hour(24))
#####################################################
# Parse initial_status.csv to assign initial status
# for Generator
# set_time_at_status! implemented for ThermalStandard,
# ThermalMultiStart, HydroEnergyReservoir,HydroPumpedStorage
# set_status! only implemented for ThermalStandard,
# ThermalMultiStart
#####################################################
sys_base = sys_DA.units_settings.base_value;
initial_status_csv_location = joinpath(pwd(),"data","initial_status.csv")
df_initial_status = DataFrames.DataFrame(CSV.File(initial_status_csv_location));

for col_name in names(df_initial_status)
    comp = get_component(Generator,sys_DA,col_name)
    if (typeof(comp) in [ThermalStandard, ThermalMultiStart])
        if (df_initial_status[1,col_name]<0)
            set_status!(comp, false)
            set_time_at_status!(comp, abs(df_initial_status[1,col_name]))
        else
            set_status!(comp, true)
            set_time_at_status!(comp, df_initial_status[1,col_name])
        end
        set_active_power!(comp,(df_initial_status[2,col_name]/sys_base))
    end
    if (typeof(comp) in [HydroEnergyReservoir,HydroPumpedStorage])
        if (df_initial_status[1,col_name]<0)
            #comp.status = false
            set_time_at_status!(comp, abs(df_initial_status[1,col_name]))
        else
            #comp.status = true
            set_time_at_status!(comp, df_initial_status[1,col_name])
        end
        set_active_power!(comp,(df_initial_status[2,col_name]/sys_base))
    end
end
#####################################################
# RT System - Transforming Single Time Series
#####################################################
sys_RT = PSY.System(rawsys; time_series_resolution = Dates.Minute(5));
PSY.transform_single_time_series!(sys_RT, 12, Dates.Minute(60))
# Remove Flex_Down and Fex_Up Services from RT System because
# time series doesn't exist in RT System
flex_down_comp = get_component(VariableReserve, sys_RT, "Flex_Down")
remove_component!(sys_RT, flex_down_comp)
flex_up_comp = get_component(VariableReserve, sys_RT, "Flex_Up")
remove_component!(sys_RT, flex_up_comp)
#####################################################
# # Operations Problem Template
#####################################################
template_uc = OperationsProblemTemplate()

# Branch Formulations
set_device_model!(template_uc, Line, StaticBranch)
set_device_model!(template_uc, Transformer2W, StaticBranch)
set_device_model!(template_uc, TapTransformer, StaticBranch)

# Injection Device Formulations
set_device_model!(template_uc, ThermalStandard, ThermalStandardUnitCommitment)
set_device_model!(template_uc, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template_uc, PowerLoad, StaticPowerLoad)
set_device_model!(template_uc, HydroDispatch, FixedOutput)
set_device_model!(template_uc, HydroEnergyReservoir, HydroDispatchRunOfRiver)
set_device_model!(template_uc, RenewableFix, FixedOutput)

# Service Formulations
set_service_model!(template_uc, VariableReserve{ReserveUp}, RangeReserve)
set_service_model!(template_uc, VariableReserve{ReserveDown}, RangeReserve)

# Network Formulations
set_transmission_model!(template_uc, CopperPlatePowerModel)

# Optimizer
solver = optimizer_with_attributes(SCIP.Optimizer,"limits/gap" => 1e-3,"limits/time" => 100,)

# Build the Operations Problem
op_problem = OperationsProblem(template_uc, sys_DA; optimizer = solver, horizon = 24,initial_time = DateTime("2020-07-01T00:00:00"))

build!(op_problem, output_dir = mktempdir())
#####################################################
# Economic Dispatch
#####################################################
# ED Template
template_ed = template_economic_dispatch()
# Problems
problems = SimulationProblems(
    UC = OperationsProblem(template_uc, sys_DA, optimizer = solver),
    ED = OperationsProblem(
        template_ed,
        sys_RT,
        optimizer = solver,
        balance_slack_variables = true,
    ),
)
# Feed-Forward
feedforward_chronologies = Dict(("UC" => "ED") => Synchronize(periods = 24))

feedforward = Dict(
    ("ED", :devices, :ThermalStandard) => SemiContinuousFF(
        binary_source_problem = PSI.ON,
        affected_variables = [PSI.ACTIVE_POWER],
    ),
)

intervals = Dict("UC" => (Hour(24), Consecutive()), "ED" => (Minute(60), Consecutive()))

DA_RT_sequence = SimulationSequence(
    problems = problems,
    intervals = intervals,
    ini_cond_chronology = InterProblemChronology(),
    feedforward_chronologies = feedforward_chronologies,
    feedforward = feedforward,
)
# Simulation
sim = Simulation(
    name = "RTS-GMLC",
    steps = 14,
    problems = problems,
    sequence = DA_RT_sequence,
    simulation_folder = joinpath(pwd(), "data", "Results"),
    initial_time = DateTime("2020-07-01T00:00:00")
)

build!(sim)

execute!(sim, enable_progress_bar = false)

results = SimulationResults(sim);

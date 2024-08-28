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


data_dir = "Projects/NVE/output/"
base_power = 100.0
descriptors = "Projects/NVE/user_descriptors.yaml"
timeseries_metadata_file = "timeseries_pointers.json"
data = PowerSystemTableData(
    data_dir,
    base_power,
    descriptors;
    timeseries_metadata_file = timeseries_metadata_file,
)
sys = System(data, time_series_in_memory = true)

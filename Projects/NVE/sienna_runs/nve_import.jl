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


data_dir = "/data/my-data-dir"
base_power = 100.0
descriptors = "./user_descriptors.yaml"
timeseries_metadata_file = "./timeseries_pointers.json"
generator_mapping_file = "./generator_mapping.yaml"
data = PowerSystemTableData(
    data_dir,
    base_power,
    descriptors;
    timeseries_metadata_file = timeseries_metadata_file,
    generator_mapping_file = generator_mapping_file,
)
sys = System(data, time_series_in_memory = true)
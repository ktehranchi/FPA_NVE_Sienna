# FPA_Sienna Project

## Overview
This project implements a power system analysis framework that converts the representation of Nevada Energy (NVE) with publicly available data originated from PLEXOS db and converts it into a Sienna format to perform production cost modeling with PowerSimulations.jl and resource adequacy assessments with PRAS via the SiennaPRASInterface.jl package. 

## Key Components

### Main Script (`nve_plexos2sienna_final.jl`)
**This is the only script you need to run.** It handles both PCM and RA analysis modes:

**For Production Cost Modeling (PCM):**
- Set `run_type = "Deterministic"`
- Uses single weather year (default: 1998)
- Runs economic dispatch optimization

**For Resource Adequacy (RA):**
- Set `run_type = "Monte_Carlo"`
- Uses multiple weather years (1998-2022)
- Runs Monte Carlo reliability analysis with PRAS

**Core Functions:**
- Configures simulation parameters and paths
- Builds and modifies the power system model
- Handles time series processing for weather-dependent resources
- Executes simulations based on selected mode
- Exports results for further analysis

### Support Modules

#### Helper Functions (`_helpers.jl`)
Core utility functions that support system modifications:
- Data modification utilities
- Area interchange creation
- Reserve requirement attachment
- Market import constraints
- Other essential system modifications

#### Non-Weather Components (`NVE_non_weather.jl`)
Handles core system components and modifications:
- System initialization and path management
- PLEXOS to Sienna data conversion
- Device model definitions (thermal, hydro, storage)
- Network topology and constraints
- Results processing and export functionality

#### Weather-Related Components (`NVE_weather.jl`)
Manages weather-dependent resources and their time series:
- Front-of-the-Meter (FTM) solar processing
- Behind-the-Meter (BTM) solar processing
- Wind resource processing
- Load forecasting and regional allocation

## Data Conversion with R2X

This framework relies on [NREL's R2X tool](https://github.com/NREL/R2X) for converting PLEXOS model data to Sienna-compatible formats. 

**R2X Features:**
- **Model Translation**: Converts ReEDS and PLEXOS models to PowerSystems.jl representations
- **PLEXOS XML Parser**: Comprehensive parser for PLEXOS database files
- **Format Conversion**: Translates between different power system modeling formats
- **Sienna Integration**: Direct output compatibility with Sienna ecosystem tools

**In This Project:**
- R2X converts the Nevada Energy PLEXOS database to Sienna format
- Output data is stored in the `output_stable_dec24/` directory
- Includes generator parameters, load data, and time series metadata
- Enables seamless integration between PLEXOS and Sienna workflows

For more information, visit the [R2X documentation](https://nrel.github.io/R2X/).

## Key Features

### Resource Management
- Converts distributed PV units between dispatch types
- Handles demand response cleanup
- Manages hydro dispatch profiles
- Assigns outage statistics to generators and storage
- Processes multiple weather years for renewable resources

### Time Series Processing
- Handles both deterministic and stochastic scenarios
- Processes multiple weather years (1998-2022)
- Manages regional load allocations
- Integrates renewable generation profiles

### Simulation Capabilities
- Deterministic production cost modeling
- Monte Carlo reliability analysis
- Area interchange modeling

## Workflow

1. **System Building**
   - Initialize paths and configurations
   - Convert PLEXOS data to Sienna format
   - Apply system modifications and constraints

2. **Time Series Processing**
   - Process weather-dependent resources
   - Handle load forecasts
   - Create forecast time series

3. **Simulation Execution**
   - Run deterministic or Monte Carlo simulations
   - Process results
   - Export data for analysis

4. **Reliability Analysis**
   - Convert system to PRAS model
   - Run sequential Monte Carlo simulation
   - Calculate reliability metrics
   - Export results

## Output Data (RA analysis)
The framework generates several key outputs:
- Shortfall summaries
- Hourly Energy Not Served (ENS)
- Daily MWh calculations
- Daily ENS hours
- Daily event indicators

## Prerequisites

### System Requirements
- **Julia 1.9+** (tested with Julia 1.10)
- **Memory**: Minimum 8GB RAM (16GB+ recommended for large simulations)
- **Storage**: ~5GB for repository and dependencies
- **OS**: Windows, macOS, or Linux

### Required Data
The framework requires the following input data to run:

1. **R2X Output Data**: Converted PLEXOS data in the `output_stable_dec24/` folder
   - Generated using [NREL's R2X tool](https://github.com/NREL/R2X) for model translation
   - Converts PLEXOS XML databases to Sienna-compatible format
2. **Weather Time Series**: Multi-year data (1998-2022) in `LOLP_inputs/`:
   - Solar generation profiles (`solar/Y{year}.csv`)
   - Distributed PV profiles (`DPV/Y{year}.csv`) 
   - Wind generation profiles (`wind/Y{year}.csv`)
   - Load forecasts (`load/Stochastic_Loads_CY2030_WY{year}.csv`)
3. **Generator Data**: Outage statistics and capacity information
4. **Configuration Files**: `nve-current.yaml` and user descriptors

## Getting Started

### 1. Environment Setup
```bash
# Clone the repository
cd /path/to/your/workspace

# Navigate to the NVE project
cd Projects/NVE

# Start Julia in the project directory
julia --project=.
```

### 2. Install Dependencies
```julia
# In Julia REPL
using Pkg
Pkg.instantiate()  # Install all required packages
```

### 3. Verify Installation
```julia
# Test that key packages load correctly
using PowerSystems, PowerSimulations, SiennaPRASInterface
using HiGHS  # or Gurobi if you have a license
println("Setup complete!")
```

## Dependencies
- PowerSystems.jl
- PowerSimulations.jl
- PowerSystemCaseBuilder
- HydroPowerSimulations
- StorageSystemsSimulations
- SiennaPRASInterface
- Optimization solver: HiGHS (free, open-source) or Gurobi (commercial, faster for large problems)
- Other supporting Julia packages (CSV, DataFrames, Plots, etc.)

## Usage

### Solver Configuration
The scripts are pre-configured to use Gurobi, but you can easily switch to HiGHS (free alternative):

**To use HiGHS instead of Gurobi:**
1. In the main script (`nve_plexos2sienna_final.jl`), replace:
   ```julia
   using Gurobi # solver
   ```
   with:
   ```julia
   using HiGHS # solver
   ```

2. In `NVE_non_weather.jl`, replace:
   ```julia
   optimizer = optimizer_with_attributes(Gurobi.Optimizer, "MIPGap" => 1e-2),
   ```
   with:
   ```julia
   optimizer = optimizer_with_attributes(HiGHS.Optimizer),
   ```

### Simulation Modes
The single script `nve_plexos2sienna_final.jl` supports two analysis modes:

1. **Deterministic Mode (PCM)**: 
   - Production Cost Modeling with single weather year
   - Economic dispatch optimization
   - Set: `run_type = "Deterministic"`

2. **Monte Carlo Mode (RA)**: 
   - Resource Adequacy analysis with multiple weather years
   - Monte Carlo reliability assessment using PRAS
   - Set: `run_type = "Monte_Carlo"`

**Configuration Location**: Edit lines 29 and 32-35 in `nve_plexos2sienna_final.jl`

### Running Your First Simulation

#### Quick Test Run (Deterministic PCM)
```julia
# 1. Navigate to sienna_runs directory
cd("sienna_runs")

# 2. Configure for a quick test
# Edit nve_plexos2sienna_final.jl to set:
# run_type = "Deterministic"
# weather_years = 1998

# 3. Run the simulation
include("nve_plexos2sienna_final.jl")
```

#### Full Resource Adequacy Analysis
```julia
# For comprehensive RA analysis with multiple weather years
# Edit nve_plexos2sienna_final.jl to set:
# run_type = "Monte_Carlo"
# weather_years = 1998:2022

# Run the simulation
include("nve_plexos2sienna_final.jl")
```

### Configuration Examples

#### Deterministic PCM Configuration
```julia
# Edit these lines in nve_plexos2sienna_final.jl (around line 29)
run_type = "Deterministic"          # Single weather year PCM
weather_years = 1998               # Automatically set for deterministic

# Scenario configuration (around line 44-45)
r2x_output_name = "output_stable_dec24"
scenario_name = "output_stable_dec24"
```

**Simulation Duration:**
To modify the number of days simulated, edit `NVE_non_weather.jl` on line 604:
```julia
sim = Simulation(
    name = "test-sim",
    steps = 364,  # Number of days to simulate (364 = almost full year)
    # ... other parameters
)
```

#### Resource Adequacy (RA) Configuration
```julia
# Edit these lines in nve_plexos2sienna_final.jl (around line 29)
run_type = "Monte_Carlo"           # Multi-year RA analysis
weather_years = 1998:2022         # Automatically set for Monte Carlo

# For subset analysis, manually edit line 35:
weather_years = [2008, 2012, 2015]  # Specific drought years
```

## File Structure
```text
FPA_Sienna/
├── Projects/
│   └── NVE/
│       ├── sienna_runs/
│       │   ├── nve_plexos2sienna_final.jl    # MAIN SCRIPT - Use this only
│       │   ├── NVE_non_weather.jl            # Support module
│       │   ├── NVE_weather.jl                # Support module  
│       │   ├── _helpers.jl                   # Support module
│       │   ├── nve_plexos2sienna_LOLP.jl     # Legacy (don't use)
│       │   ├── nve_plexos2sienna_deterministic.jl  # Legacy (don't use)
│       │   └── user_descriptors/
│       ├── LOLP_inputs/                      # Weather data (1998-2022)
│       ├── output_stable_dec24/              # R2X converted data
│       └── run_output/                       # Simulation results
```

## Module Dependencies
```text
nve_plexos2sienna_final.jl
├── _helpers.jl
├── NVE_non_weather.jl
└── NVE_weather.jl
```

## Understanding Outputs

### Production Cost Modeling Results
Located in: `sienna_runs/run_output/{scenario_name}/deterministic/`

**Key Files:**
- `generation_by_fuel.csv` - Aggregated generation by fuel type (MW)
- `generator_active_power.csv` - Individual generator dispatch schedules (MW)
- `production_costs.csv` - Total system operational costs ($)
- `renewable_active_power.csv` - Renewable generation profiles (MW)
- `storage_charge.csv` / `storage_discharge.csv` - Battery operations (MW)
- `load_active_power.csv` - Load profiles by region (MW)

**Analysis Tips:**
- Check energy balance: sum of generation should equal load + losses
- Examine peak/off-peak dispatch patterns
- Identify renewable curtailment periods
- Review storage cycling behavior

### Resource Adequacy Results
Located in: `sienna_runs/run_output/{scenario_name}/stochastics/`

**Key Files:**
- `all_shortfall_samples.csv` - Raw shortfall data for all Monte Carlo samples
- `daily_shortfall_ENS.csv` - Daily Energy Not Served by weather year (MWh)
- `summary_stats_by_weather_year.csv` - Reliability metrics by year

**Key Metrics:**
- **EUE (Expected Unserved Energy)**: Average annual shortfall (MWh/year)
- **LOLP (Loss of Load Probability)**: Fraction of time with shortfalls
- **Peak Shortfall**: Maximum instantaneous shortfall (MW)

**Reliability Standards:**
- EUE < 0.1 days/year typically considered adequate
- LOLP < 0.1% (1 day in 1000) is common criterion

## Troubleshooting

### Common Issues

#### 1. Package Installation Errors
```
ERROR: Package not found
```
**Solution:**
```julia
# Update package registry and reinstall
using Pkg
Pkg.update()
Pkg.resolve()
Pkg.instantiate()
```

#### 2. Solver Errors
```
ERROR: No solver attached
```
**Solution:**
- Ensure HiGHS or Gurobi is properly installed
- Check solver configuration in scripts
- For Gurobi: verify license is active

#### 3. Memory Issues
```
ERROR: OutOfMemoryError
```
**Solution:**
- Reduce number of weather years for testing
- Set `time_series_in_memory = false` in system creation
- Use a machine with more RAM (16GB+ recommended)

#### 4. Missing Time Series Data
```
ERROR: File not found: Y2023.csv
```
**Solution:**
- Verify all required weather year files exist in `LOLP_inputs/`
- Check file naming convention matches `Y{year}.csv`
- Ensure weather_years in script matches available data

#### 5. Simulation Convergence Issues
```
WARNING: Solver did not converge
```
**Solution:**
- Check for infeasible constraints
- Review generator capacity vs. load requirements
- Examine reserve requirement settings
- Try different solver tolerances

### Performance Tips

1. **Start Small**: Test with single weather year before full runs
2. **Shorter Test Runs**: For debugging, reduce simulation days in `NVE_non_weather.jl` (e.g., `steps = 7` for one week)
3. **Monitor Memory**: Use system monitor during large simulations  
4. **Parallel Processing**: Enable threading where supported
5. **Solver Tuning**: Adjust solver tolerances for speed vs. accuracy trade-off

### Getting Help

**Debugging Steps:**
1. Check log files in `power-systems.log`
2. Verify input data integrity with spot checks
3. Test with smaller weather year ranges first
4. Compare results with PLEXOS validation data using `comparison.py`
5. Check `run_type` and `weather_years` settings in `nve_plexos2sienna_final.jl`

**Resources:**
- PowerSystems.jl documentation: [https://nrel-sienna.github.io/PowerSystems.jl/](https://nrel-sienna.github.io/PowerSystems.jl/)
- PowerSimulations.jl documentation: [https://nrel-sienna.github.io/PowerSimulations.jl/](https://nrel-sienna.github.io/PowerSimulations.jl/)
- PRAS documentation: [https://nrel.github.io/PRAS/](https://nrel.github.io/PRAS/)
- R2X model translation tool: [https://github.com/NREL/R2X](https://github.com/NREL/R2X)
- R2X documentation: [https://nrel.github.io/R2X/](https://nrel.github.io/R2X/)

## Contributing

When contributing to this repository:

1. **Test Changes**: Run validation suite before submitting
2. **Document Updates**: Update this README for any new features
3. **Performance**: Test with both HiGHS and Gurobi solvers
4. **Data Compatibility**: Ensure changes work with existing data formats

## License and Acknowledgments

This framework builds upon the work of the NREL team and the Julia ecosystem:
- **Sienna Ecosystem**: PowerSystems.jl, PowerSimulations.jl, PowerSystemCaseBuilder.jl, SiennaPRASInterface.jl
- **R2X**: Model translation framework for converting PLEXOS to Sienna ([GitHub](https://github.com/NREL/R2X))
- **PRAS**: Probabilistic Resource Adequacy Suite for reliability analysis
- **Julia Optimization**: JuMP.jl, HiGHS.jl, Gurobi.jl for mathematical optimization

**Nevada Energy Data**: This analysis only uses publicly available data from EIA and other public datasets.
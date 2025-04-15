# FPA_Sienna Project

## Overview
This project implements a power system analysis framework that converts the representation of Nevada Energy (NVE) using only public data in PLEXOS and converts it into a Sienna format to perform production cost modeling with PowerSimulations.jl and resource adequacy assessments with PRAS via the SiennaPRASInterface.jl package. 

## Key Components

### Main Script (`nve_plexos2sienna_final.jl`)
The master script that orchestrates the entire workflow:
- Configures simulation parameters and paths
- Builds and modifies the power system model
- Handles time series processing
- Executes simulations
- Performs reliability analysis using PRAS (Probabilistic Resource Adequacy Suite)
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

## Dependencies
- PowerSystems.jl
- PowerSimulations.jl
- PowerSystemCaseBuilder
- HydroPowerSimulations
- StorageSystemsSimulations
- SiennaPRASInterface
- Other supporting Julia packages

## Usage
The system can be run in two modes:
1. **Deterministic Mode**: Single weather year analysis
2. **Monte Carlo Mode**: Multiple weather year analysis with reliability assessment

Configure the run type and parameters in `nve_plexos2sienna_final.jl` before execution.

## File Structure
```text
FPA_Sienna/
├── Projects/
│   └── NVE/
│       ├── sienna_runs/
│       │   ├── nve_plexos2sienna_final.jl
│       │   ├── NVE_non_weather.jl
│       │   ├── NVE_weather.jl
│       │   ├── _helpers.jl
│       │   └── user_descriptors/
│       ├── LOLP_inputs/
│       └── run_output/
```

## Module Dependencies
```text
nve_plexos2sienna_final.jl
├── _helpers.jl
├── NVE_non_weather.jl
└── NVE_weather.jl
```
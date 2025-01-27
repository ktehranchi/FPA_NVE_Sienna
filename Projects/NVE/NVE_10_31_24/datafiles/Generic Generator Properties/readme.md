# Generic Generator Data Files

The PLEXOS properties included for every thermal power plant in the QFER list are listed below. The max, summer, and winter capacities and average heat rates are unique to every unit in the model. All other thermal properties are based on a generic fuel/unit type assignment. The source for each characteristic is listed as well.

* Capacity (Max, Summer, and Winter) - QFER and EIA 860
* Heat Rate (Average annual heat rate) - QFER and EIA 923
* VO&M Charge - 2018 Variable Operations and Maintenance Cost (CAISO External Report) 
* Each property below is based on NREL Eastern Renewable Generation Integration Study (based on EIPC 2014/15 data)
    * Start Cost
    * Min Up/Down Time
    * Max Ramp Up/Down
* Each property below is based on NERC GADS Brochure 4 (5-year period). Please refer to the Telos provided Forced Outage Modeling documentation for reference to how the values were derived. NERC GADS Statistical Brochure 4 2017-2021 All Units Reporting
    * Forced Outage Rate (using EFORd)
    * Maintenance Frequency
    * Mean Time to Repair
    * Min Time to Repair
    * Repair Time Scale
* Repair Time Distribution
    * Based on typical outage distribution formations for forced outages (exponential) and a planned maintenance period (constant)


## PLEXOS Implementation Details

### Heat Rates & Capacities (`Average Heat Rate.csv`)

These properties are added to the PLEXOS database using a unique data file for each property (Average Heat Rate, Max Capacity, Min Stable Level, Summer Capacity, and Winter Capacity). These data files reference each thermal generator's unique name in PLEXOS and are tagged to the respective Generator Property in the model.

### Generic Thermal Properties (`Generic Generator Properties by Type.csv`)

These properties are added in a single data file based on the name of the fuel/prime mover (e.g. NG CC) and the property name (e.g. Min Up Time). Each of the properties are also tagged to a PLEXOS variable object which are mapped to the unit class associated with the name (e.g. Biogas CC Forced Outage Rate).

Some of the properties are based on a percentage of Max Capacity, therefore the PLEXOS structure references both the Max Capacity data file and the variable (e.g. Max Ramp Up) and uses the "X" action to create the final property input for the model.

The generic properties data file also includes additional metadata to define the property units and data source. The headers for both columns are empty which is required to bypass PLEXOS validation logic. If column headers are defined then PLEXOS will assume a different  file format.

Name|Value||
--- | --- | --- | --- 
Biogas CC Forced Outage Rate|4.06|%|Based on NERC GADS Brochure 4 CC All Sizes
Biogas CC Maintenance Frequency|2.21|Events|Based on NERC GADS Brochure 4 CC All Sizes
Biogas CC Max Ramp Down|0.05|% Max Capacity|"Based on NREL Eastern Renewable Generation Integration Study (2016| uses EIPC study base data) for unit class characteristics"
Biogas CC Max Ramp Up|0.05|% Max Capacity|"Based on NREL Eastern Renewable Generation Integration Study (2016| uses EIPC study base data) for unit class characteristics"

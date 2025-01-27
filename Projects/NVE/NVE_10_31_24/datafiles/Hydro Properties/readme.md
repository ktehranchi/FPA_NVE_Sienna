# Hydro Data Files

This document describes the process used to develop the PLEXOS hydroelectric generator database using the CEC Quarterly Fuel & Energy Reports and EIA 923 monthly electricity generation data for 2001 - 2021.

In PLEXOS, the hydro generators share a similar generic unit characteristic setup to thermal generators for VO&M, Min Up/Down Time, and forced and maintenance outage rates. These values reference variables (e.g., Hydro Min Time to Repair) that are detailed in the “Generic Generator Properties by Type.csv” data file. In addition to those properties, the hydro generators have a few unique considerations also included that use the following PLEXOS properties.

* Max Energy Month - used to create monthly energy budgets based on historical hydro years and an average hydro year.
* Max Energy Penalty - set to higher than VOLL in the model so that hydro units cannot exceed their budget. This setup makes the energy budget a “soft constraint” but it cannot be violated in lieu of shedding * load. The reason it is a “soft” constraint is to avoid infeasibility errors when it is “hard”
* Min Energy Hour - used to create a minimum generation for conventional hydro based on the assumption that most or all the units are Run-of-River and have a portion of their budget expended in a “must-run” fashion.
* Min Energy Hour Penalty - same set up as the max penalty
* Head & Tail Storage objects - for pumped storage hydro modeled with pumping capabilities (see section further in documentation on PSH modeling)

## QFER & EIA 860 Generator Data

### Hydro ICAP & Node Assignment

The installed capacity for hydro units in CA was taken directly from the QFER using the latest available data (2021) at a unit level. Initially, the QFER hydro plants were aggregated based on their CEC Plant ID with an additional aggregation to the PLEXOS node (balancing authority level) for hydro units that were less than 5 MW.

* Several hydro plants in the QFER data had duplicate entries which needed to be removed. This data is summarized in Appendix B. The total duplicate MW was 2,147.8 which is a significant portion of the CA hydro fleet capacity; these duplicate values were removed from the model.
* A small number of plants did not have generation listed for several years in the QFER report, it may be that these units are on ephemeral streams or have been out of service for extended periods of time. Since there is limited data for these units they were removed from the model using a scenario, but can be reincorporated at a later date if needed. These units only totaled approximately 15 MW.
  * The scenario to turn off these units is named “Remove Hydro Missing Gen” in the PLEXOS model

Node assignments were based on the CEC Utility ID and mapped to the balancing authority or ISO where the unit is physically located. When the CEC Utility ID did not directly align with one of the balancing authorities or an ISO, the utility name was mapped to the PLEXOS nodes based in Appendix A. Below, Table 1 shows the total installed capacity by PLEXOS node in the model. It provides a breakdown of Large vs Small hydro and pumped storage hydro. In total, CA has 9,801.6 MW of conventional hydro resources, 4,382 MW of pumped storage hydro resources and 1,160 MW of dedicated Hoover hydro resources.

**Table 1** CA Hydro Breakdown by PLEXOS Node and Hydro Type
PLEXOS Node | Large Hydro (MW) | Small Hydro (MW) | Pumped Storage Hydro (MW) | Notes
--- | --- | --- | --- | ---
BANC | 2,626 | 65.3 | 8 | PSH modeled as conventional
IID | 0 | 86.4 | 0 |
LADWP | 0 | 290.2 | 1,683 |
PG&E | 4,017.5 | 1,026.9 | 2,422 | 786 MW of PSH modeled as conventional
SCE | 1,202 | 293.2 | 229 | 30 MW of PSH modeled as conventional
SDGE | 0 | 9 | 40 |
TIDC | 172 | 13 | 0 |
Hoover (SCE + LADWP) | 365 (LADWP) + 795 (SCE) | |
Total | 8,017.5 | 1,784.1 | 4,382 |
Total + Dedicated Hoover | 9,177.5 | - | - | -

### Hydro Annual Variations

Hydro generation varies annually based on a variety of factors including snowpack and precipitation across a large geographic area. To capture the variation in available hydro energy across different hydrologic conditions the EIA 923 and QFER annual generation data was used for the 2001 - 2021 period. In this effort, the EIA 923 data took precedence because generation data is also provided in a monthly format and was used to create monthly energy budgets (see following section). Figure 1 shows the total CA hydro generation excluding Hoover and PSH units for 2001 - 2021.

**Figure 1** Annual CA Hydro Generation based on EIA 923 (2001 - 2021)

![image](/docs/images/Annual%20CA%20Hydro%20Generation.png)

### Hydro Monthly Energy Budgets

The EIA 923 monthly net generation for each hydro plant was used to create monthly energy budgets for each hydro year (2001 - 2021). This was done by using the CEC ArcGIS database which maps the CEC Plant ID to EIA Plant IDs. For hydro units that were missing monthly generation but had annual generation in the QFER the trend in monthly generation as a percentage of annual generation across all CA hydro units was used to distribute the annual generation across each month by hydro year. Across the period of available data, the monthly generation as a percentage of annual generation is fairly consistent as shown in figure 2. For any units with negative values for monthly or annual generation data their entries were set to 0 after checking both QFER and EIA data.

**Figure 2** Monthly hydro generation as a % of annual generation (2001 - 2021)

![Figure-2](/docs\images\Monthly%20CA%20Hydro%20Gen.png)

### Minimum Generation Constraints (must-run hydro)

One issue that arises from using monthly energy budgets for hydro modeling is that often hydro generation can be a “use or lose it” resource unless there is some amount of pondage available to the plant. Since this data is difficult to find and may be proprietary, an alternative approach was used to ensure that the hydro generation was not over-optimized and withholding energy for only the peak risk periods.

To develop the minimum energy constraints the Min Energy Hour PLEXOS property was used to force hydro generators to dispatch at a specific MW level based on each unit's monthly energy budget. To make sure that the minimum generation constraint does not exceed their monthly energy budget a factor was applied to each plants monthly energy budget to evenly distribute a portion of the generation across each hour of each month. The formula used to calculate this is as follows:
Min Energy Hour = (1 / # of hours in month) * 20%

This setup forces an hourly dispatch for the hydro generators that evenly distributes the energy budget across all hours of a month, then derates it by 80% to allow for some flexibility in dispatch. This setup can be changed by modifying the “Conv Hydro Min Energy Factor.csv” datafile located in the “datafiles\Hydro Properties” folder in the GitHub repository. Each month is defined here (based on the number of hours per month). An example of why one would want to change this flexibility for hydro units is to test the sensitivity of RA or production cost results on the flexibility of hydro generators.

## All Hydro Max Generation Capability

Consideration was also given to the maximum hydro generation that the CA hydro fleet can output in a given hour. Even in high hydro years, review of hourly generation data from CAISO and EIA shows that the CAISO and Muni hydro fleets (inclusive of conventional and PSH) do not output at their total installed capacity. This data is based on EIA real time grid monitor data for 2019 - 2023 and CAISO production and curtailment reports from 2014 - 2022., The figures below represent the monthly maximum generation seen across the hydro years to show the potential maximum generation seen rather than the maximum generation seen in a specific hydro year. The PLEXOS model maximum is based on the 2019 hydro year to set a  limit on all CAISO and Muni hydro units.

![CAISO-Hydro](/docs\images\CAISO%20Hydro%20Max%20Gen%20Normalized%20to%20ICAP.png)
![Muni-Hydro](/docs\images\Muni%20Hydro%20Max%20Gen%20Normalized%20to%20ICAP.png)

## Pumped Storage Hydro Modeling

### Pumped Storage Hydro ICAP

Based on the QFER report, there is a total of 4,382 MW of pumped storage hydro capacity in CA. Table X summarizes the total capacity for these plants. In the PLEXOS model, each unit of the plants are modeled and EIA 860 data on which units are generating-pumping units was used to differentiate which units can be in pumping mode.

Based on recent IEPR and CAISO models, several of the pumped storage hydro plants are being modeled as conventional hydro with energy budgets rather than pumped storage units. This is likely due to a lack of information on the stream inflow and working volume for the pumped storage reservoirs. Units that were modeled as conventional hydro used monthly energy budgets developed using the same method discussed in the conventional hydro modeling section. This may be an important enhancement to focus on going forward since pumped storage hydro will be increasingly important in higher renewable energy systems for balancing and energy shifting. The plants modeled as conventional hydro can be turned into PSH units using the “Model Residual PSH” scenario, although lack of data currently prevents accurate modeling of these units as PSH.

**Table 2** CA Pumped Storage Hydro Units and Notes
Plant Name | PLEXOS Node | Capacity | Notes
--- | --- | --- | ---
Castaic (Pumped Storage) | LADWP | 1,682 | Modeled as PSH
Diamond Valley Lake (Pumping-Generating) | SCE | 30 | Modeled as conventional
Eastwood (Pumped Storage) | SCE | 199 | Modeled as PSH
Edward C Hyatt (Unit 1,3,5 Pumping-Generating) | PG&E | 645 | Modeled as conventional
Helms (Pumped Storage) | PG&E | 1,212 | Modeled as PSH
Lake Hodges Station (Olivenhain Pumped Storage) | SDGE | 40 | Modeled as PSH
North Hollywood Pumping Plant | LADWP | 1 | Modeled as conventional
O’Neill (Pumping-Generating) | PG&E | 24 | Modeled as conventional
Senator Wash (Pumping-Generating) | BANC | 8 | Modeled as conventional
Thermalito (Unit 1 HY Unit 2-3-4 Pumping-Generating) | PG&E | 117 | Modeled as conventional
W R Gianelli (Pumping-Generating) | PG&E | 424 | Modeled as PSH

### Pumped Storage Hydro Storage Size and Inflows

For the pumped storage units modeled with pumping capabilities, the CAISO 2021 IRP PLEXOS model was used to inform the reservoir and natural inflow characteristics for these units. It is important that the dynamic of working volume (reservoir volume available to be dispatched or filled to without violating physical constraints) and natural inflow (water from streams and rivers naturally filling the system) are represented. Table 4 summarizes the PSH units in terms of their capacity, storage size, and natural inflows and max spill (allows storage to be spilled to maintain volume limits).
More work is needed to enhance the accuracy of the pumped storage units and confirm that the implied durations for these plants reflect reality.

**Table 2** CA Pumped Storage Hydro Detailed Generator and Storage Setup
Plant Name | PLEXOS Node | Generating Capacity (MW) | Pumping Capacity (MW) | Storage Size (GWh) | Implied Storage Duration (hr) | Natural Inflow Range (MW) | Reservoir Max Spill (MW)
--- | --- | --- | --- | --- | --- | --- | ---
Castaic (Pumped Storage) | LADWP | 1,682 | 1,682 | 100 | 59 | 22 - 53 | 400
Eastwood (Pumped Storage) | SCE | 199 | 199 | 5 | 25 | 3.5 - 90.5 | 400
Helms (Pumped Storage) | PG&E | 1,212 | 1,212 | 184.5 | 152 | 0 - 19 | N/A
Lake Hodges Station (Olivenhain Pumped Storage) | SDGE | 40 | 40 | 2.24 | 56 | N/A | N/A
W R Gianelli (Pumping-Generating) | PG&E | 424 | 424 | 100 | 235 | 0 - 184 | 400

### Pumped Storage Hydro - Conventional Monthly Energy Budgets

PSH units modeled as conventional hydro were assigned monthly energy budgets based on annual monthly net generation data from the EIA 923 forms for 2001 - 2021. If monthly values were negative, indicating pumping load was greater than generation, the monthly energy budget was set to 0 because PLEXOS does not support negative energy budgets. Table 3 shows the average monthly energy budget for each of the conventional PSH units for the 2001 - 2021 period.

**Table 3** PSH as Conventional Avg Monthly Energy Budget in GWh (2001 - 2021)
Plant Name | M01 | M02 | M03 | M04 | M05 | M06 | M07 | M08 | M09 | M10 | M11 | M12
--- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | ---
Diamond Valley Lake | 1.4 | 1.3 | 1.7 | 2.0 | 2.4 | 2.3 | 2.5 | 2.2 | 1.6 | 1.3 | 1.1 | 1.2
Edward C Hyatt | 77.6 | 62.9 | 91.7 | 122 | 172 | 171 | 238 | 201 | 127 | 84 | 83 | 75
North Hollywood | 0.04 | 0.05 | 0.06 | 0.06 | 0.08 | 0.09 | 0.10 | 0.09 | 0.07 | 0.05 | 0.03 | 0.03
O’Neill | 0.21 | 0.23 | 0.28 | 0.44 | 0.90 | 0.67 | 0.45 | 0.40 | 0.30 | 0.23 | 0.18 | 0.21
Senator Wash | 0.65 | 0.59 | 0.79 | 0.93 | 1.15 | 1.11 | 1.10 | 0.98 | 0.74 | 0.59 | 0.49 | 0.59
Thermalito | 4 | 5.4 | 7.3 | 8.6 | 14.8 | 14.4 | 21.3 | 17.5 | 11.2 | 8.5 | 8.2 | 15.4

Figure 3 shows the total monthly energy budget for the units in Table X from the 2006, 2016, and 2021 hydro years (High, Medium, Low hydro years) to show a sample of how the pumped storage units will be available for dispatch using the EIA 923 monthly generation data.

**Figure 3** PSH as Conventional Total Monthly Energy Budgets in GWh (2006, 2016, 2021)

![Figure-3](/docs\images\PSH Energy%20Budgets.png)

## Appendix A. CEC Utility ID & PLEXOS Node Mapping

CEC Utility ID| PLEXOS Node
--- | ---
Burbank Water and Power | LDWP
City of Redding Electric Utility | BANC
Imperial Irrigation District | IID
Los Angeles Department of Water & Power (LADWP) | LDWP
Merced Irrigation District | PG&E
Modesto Irrigation District | BANC
Nevada Irrigation District | BANC
Pacific Gas & Electric (PG&E) | PG&E
Plumas Sierra Rural Electric Cooperative | PG&E
Sacramento Municipal Utility District (SMUD) | BANC
San Diego Gas & Electric | SDGE
Southern California Edison (SCE) | SCE
Turlock Irrigation District | TIDC
Utica Power Authority | PG&E
Western Area Power Administration Sierra Nevada | BANC

# R2X User Notes

# Set-Up

## 1. Install Sotfware
[Mamba](https://mamba.readthedocs.io/en/latest/installation/mamba-installation.html#): Python software package managment tool. Used to manage the r2x environment.

[R2X](https://github.com/NREL/R2X/blob/main/README.md): R2X python package

[plexosdb](https://github.com/NREL/plexosdb/tree/main): plexos sqlite python package that R2X uses. To be installed while your R2X mamba environment is activated.

[Infrasys](https://github.com/NREL/infrasys): core dependency for R2X which is used to build the power system from plexos, ReEDS, or other file systems. To be installed while your R2X mamba environment is activated. Technically this is already installed in the main R2X dependencies, but if NREL pushes new changes pre-release to infrasys then you will need to have a local developer version installed.

[DBeaver](https://dbeaver.io): Used to examine the plexos sqlite database for debugging.

## 2. Download Plexos Files

Download the plexos files from the FPA Sienna Google Drive folder. Move the entire folder into the corresponding parent folder (NVE/Sonoma). Structure should be `Projects/NVE/NVE_7_19_24`.

## 3. Set up User-Dictionary

Copy or download the user_dict.yaml file from github or a previous project. If you are starting a new project you can keep all mappings from a previous project temporarily. The first time you run R2X you will get warning regarding generators missing fuel-types, you will need re-fill the dictionary accordingly to match the new plexos file fuel names and generator naming conventions.

See [here](https://github.com/NREL/R2X/blob/c169f1bda29686a7a0725bddf7b74ba08285f4e6/src/r2x/defaults/config.json#L36) for list of fuel and PrimeMover Types

```
    # Plexos Model Name, if left blank, R2X will provide you a list of models
    # in the file. You can select one in-termal, or copy and paste the name here to rerun.
    model: model_name

    fmap:
    xml_file:
        fname:  your_plexos_file_name.xml

    # Mapping of PLEXOS Generators to Sienna Fuels and PM Types
    # First read-order priority
    # {plexos_object: {fuel: sienna_fuel, pm_type: sienna_primemover_type}}
    device_map:
        Lone Mountain: # For generators without 
        fuel: GAS
        type: GT

    # Plexos Fuel Type Mapping
    # Second read-order priority
    # {plexos_fuel: {fuel: sienna_fuel, pm_type: sienna_pm_type}}
    plexos_fuel_map: 
        Nat. Gas:
        fuel: GAS
        type: GT
        default:
        fuel: GAS
        type: OT

    # Infers Fuel Type and PrimeMover from inference_string
    # Third read-order priority
    # {inference_string: {fuel: sienna_fuel, pm_type: sienna_pm_type}}
    device_name_inference_map:
        wind: 
        fuel: SOLAR
        type: WT
        solar:
        fuel: SOLAR
        type: PV
```

# Running

NVE run: 
`python -m r2x -i NVE_7_19_24/ --input-model plexos --output-model sienna --user-dict /Users/kamrantehranchi/Local_Documents/FPA_Sienna/Projects/NVE/user_dict_nve.yaml --debug  --weather-year=2030 -o output`

## Manual Changes of Output Files
1. If thermal gen is missing HR info, fill it in with zero (purchases in NVE sys)
2. Hydrogen and Waste should be renamed to OTHER
3. NA fuel prices fill to zero
4. Fill base_mva column with 1's
5. Change reserve direction from UP to Up


# Debugging

## SQLite

To debug issues with the sqlite database, it is often easier to use DBeaver to make quick modifications to fine-tune your SQL query before moving back to your query in R2X. 

1: Download [DBeaver](https://dbeaver.io) and install the software on your machine.

2: Save the plexos XML file to a sqlite database which can use in DBeaver. From your termal with the R2X mamba environment activated run these:

```
python
>>> import plexosdb
>>> from plexosdb import PlexosSQLite
>>> db = PlexosSQLite(xml_fname = 'your/path/to/file')
>>> db.save('output/path/to/sqlite.db')
>>> quit()
```

3: Open the SQLite database in DBeaver. The main `object_query` used in plexosdb is [here](https://github.com/NREL/plexosdb/blob/main/src/plexosdb/queries/object_query.sql)
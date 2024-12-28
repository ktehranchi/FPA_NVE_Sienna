function define_solar_time_series(solar_dir::String, sys::System)
    #################
    # Step 1: Read Solar Data
    #################
    # Create a dictionary to store the data
    solar_ts_dict = Dict{String, DataFrame}()

    # List all .csv files in the directory
    for file in readdir(solar_dir)
        if endswith(file, ".csv")
            # Extract the year from the filename (e.g., "Y1998.csv" -> "Y1998")
            year = splitext(file)[1]

            # Read the file into a DataFrame
            file_path = joinpath(solar_dir, file)
            df = CSV.read(file_path, DataFrame)

            # Filter out leap day (February 29)
            df = filter(row -> !(row.Month == 2 && row.Day == 29), df)

            # Store the filtered DataFrame in the dictionary
            solar_ts_dict[year] = df
        end
    end

    # Confirming sizes of the DataFrames
    for (year, df) in solar_ts_dict
        println("$year: $(size(df)) rows")
    end

    ##########################
    # Step 2: Solar Resources
    ##########################
    # Filter RenewableDispatch for solar
    solar_resources = get_components(x -> get_prime_mover_type(x) == PrimeMovers.PVe, RenewableGen, sys)

    # Define an 8760 vector based on a date interval object
    tstamps = collect(range(DateTime("2030-01-01T00:00:00"), DateTime("2030-12-31T23:00:00"), step = Dates.Hour(1)))

    # Solar mapping for missing profiles
    solar_device_mapping = Dict(
        "Dry Lake East Solar" => "Dry Lake Solar",
        "_NVE IRP Expansion_SPPC_PV (Standalone)" => "NV Generic Solar Hybrid",
        "_NVE IRP Expansion_NVP_PV (Hybrid)" => "NV Generic Solar Hybrid",
        "Libra Solar" => "NV Generic Solar",
        "Sierra Solar" => "NV Generic Solar"
    )

    ###########################
    # Step 3: Process Generators
    ###########################
    # Define the list of generator names in the CSV folder
    active_df = first(values(solar_ts_dict))  # Get the first DataFrame
    solar_ts_dict_s = String[]  # Initialize an array to store column names

    # Define solar_ts_dict_s by looping through all column names in the DataFrame
    for name in names(active_df)
        if name ∈ ["Month", "Day", "Period"]
            continue  # Skip these column names
        else
            push!(solar_ts_dict_s, name)  # Append valid names
        end
    end

    ##############################
    # Step 4: Define Time Series
    ##############################
    ts_container = Vector{Tuple{String, SingleTimeSeries}}()  # Container for all time series of all solar devices

    for device in solar_resources
        # Retrieve device name
        device_name = get_name(device)

        # Reset loop variables
        selected_name = nothing

        # Define the profile to assign to the device
        if device_name in solar_ts_dict_s
            selected_name = device_name
        elseif haskey(solar_device_mapping, device_name)
            substituted_name = solar_device_mapping[device_name]
            if substituted_name in solar_ts_dict_s
                selected_name = substituted_name
            end
        end

        # If still no match found, assign default time series and log a warning
        if selected_name === nothing
            selected_name = "NV Generic Solar"
            @warn "No time series found for device $device_name. Using default time series: $selected_name."
        end

        # Collect all time series for the active device by looping through all weather years
        for (year, data) in solar_ts_dict
            # Generate a unique time series name
            ts_name = "max_active_power_$(year)"  # Unique name for each time series

            if selected_name in names(data)  # Check if the selected column exists in the DataFrame
                # Create the time series by extracting data from the DataFrame
                ts = SingleTimeSeries(
                    name = ts_name,
                    data = TimeArray(tstamps, data[!, selected_name]),
                )

                # Store the time series along with its device name
                push!(ts_container, (device_name, ts))
            else
                # Log a warning if something is wrong
                @warn "Selected name $selected_name not found in data for year $year."
            end
        end
    end

    return ts_container
end

function add_solar_time_series_to_system!(sys::System, s_ts_container::Vector{Tuple{String, SingleTimeSeries}})
    # Loop through each solar RenewableDispatch object and add time series
    for (device_name, time_series) in s_ts_container
        # Retrieve the active device by its name
        active_device = get_component(RenewableDispatch, sys, device_name)

        if active_device !== nothing
            # Add the time series to the system
            add_time_series!(sys, active_device, time_series)
            # println("Added time series: ", time_series.name, " to device: ", device_name)
        else
            @warn "Device $device_name not found in the system. Time series $(time_series.name) not added."
        end
    end
end

function define_wind_ts_container(wind_dir::String, sys::System)
    #################
    # Step 1: Wind Weather Year Mapping
    #################
    # Define the wind weather year mapping table (one-to-many assignment)
    wind_weather_mapping = Dict(
        "Y1998" => "2014",
        "Y1999" => "2007",
        "Y2000" => "2008",
        "Y2001" => "2009",
        "Y2002" => "2010",
        "Y2003" => "2011",
        "Y2004" => "2012",
        "Y2005" => "2013",
        "Y2006" => "2014",
        "Y2007" => "2007",
        "Y2008" => "2008",
        "Y2009" => "2009",
        "Y2010" => "2010",
        "Y2011" => "2011",
        "Y2012" => "2012",
        "Y2013" => "2013",
        "Y2014" => "2014",
        "Y2015" => "2007",
        "Y2016" => "2008",
        "Y2017" => "2009",
        "Y2018" => "2010",
        "Y2019" => "2011",
        "Y2020" => "2012",
        "Y2021" => "2013",
        "Y2022" => "2014"
    )

    #################
    # Step 2: Load Wind Data
    #################
    # Create a dictionary to store the original wind weather year data
    base_wind_ts_dict = Dict{String, DataFrame}()

    # List all .csv files in the directory
    for file in readdir(wind_dir)
        if endswith(file, ".csv")
            # Extract the year from the filename (e.g., "2007.csv" -> "2007")
            year = splitext(file)[1]

            # Read the file into a DataFrame
            file_path = joinpath(wind_dir, file)
            df = CSV.read(file_path, DataFrame)

            # Filter out leap day (February 29)
            df = filter(row -> !(row.Month == 2 && row.Day == 29), df)

            # Store the filtered DataFrame in the base dictionary
            base_wind_ts_dict[year] = df
        end
    end

    # Create the final dictionary with 25 entries
    wind_ts_dict = Dict{String, DataFrame}()

    for (sienna_wy, wind_yr) in wind_weather_mapping
        # Use the mapping from wind_weather_mapping dictionary
        wind_key = "Y$wind_yr"
        if haskey(base_wind_ts_dict, wind_key)
            wind_ts_dict[sienna_wy] = base_wind_ts_dict[wind_key]
        else
            @warn "Wind weather year $wind_key not found. Sienna year $sienna_wy will not have data."
        end
    end

    #################
    # Step 3: Prepare Generator Names and Resources
    #################
    # Filter RenewableDispatch for wind
    wind_resources = get_components(x -> get_prime_mover_type(x) == PrimeMovers.WT, RenewableGen, sys)

    # Define an 8760 vector based on a date interval object
    tstamps = collect(range(DateTime("2030-01-01T00:00:00"), DateTime("2030-12-31T23:00:00"), step = Dates.Hour(1)))

    # Wind mapping for missing profiles
    wind_device_mapping = Dict(
        "Idaho Wind" => "Wind_Idaho",
    )

    # Define the list of generator names in the CSV folder
    active_df = first(values(wind_ts_dict))  # Get the first DataFrame
    wind_ts_dict_s = String[]  # Initialize an array to store column names

    for name in names(active_df)
        if name ∈ ["Month", "Day", "Period"]
            continue  # Skip these column names
        else
            push!(wind_ts_dict_s, name)  # Append valid names
        end
    end

    #################
    # Step 4: Create Time Series Container
    #################
    ts_container = Vector{Tuple{String, SingleTimeSeries}}()  # Initialize container for wind time series

    for device in wind_resources
        # Retrieve device name
        device_name = get_name(device)

        # Reset loop variables
        selected_name = nothing

        # Define the profile to assign to the device
        if device_name in wind_ts_dict_s
            selected_name = device_name
        elseif haskey(wind_device_mapping, device_name)
            substituted_name = wind_device_mapping[device_name]
            if substituted_name in wind_ts_dict_s
                selected_name = substituted_name
            end
        end

        # If no match found, assign default time series and log the assignment
        if selected_name === nothing
            selected_name = "Wind_NV-AZ"
            @warn "No time series found for device $device_name. Using default time series: $selected_name."
        end

        # Collect all time series for the active device by looping through all weather years
        for (year, data) in wind_ts_dict
            # Generate a unique time series name
            ts_name = "max_active_power_$(year)"  # Unique name for each time series

            if selected_name in names(data)  # Check if the selected column exists in the DataFrame
                # Create the time series by extracting data from the DataFrame
                ts = SingleTimeSeries(
                    name = ts_name,
                    data = TimeArray(tstamps, data[!, selected_name]),
                )

                # Store the time series along with its device name
                push!(ts_container, (device_name, ts))
            else
                @warn "Selected name $selected_name not found in data for year $year."
            end
        end
    end

    return ts_container
end

function add_wind_time_series_to_system!(sys::System, w_ts_container::Vector{Tuple{String, SingleTimeSeries}})
    # Loop through each wind RenewableDispatch object and add the time series
    for (device_name, time_series) in w_ts_container
        # Retrieve the active device by its name
        active_device = get_component(RenewableDispatch, sys, device_name)

        if active_device !== nothing
            # Add the time series to the system
            add_time_series!(sys, active_device, time_series)
            # println("Added time series: ", time_series.name, " to device: ", device_name)
        else
            @warn "Device $device_name not found in the system. Time series $(time_series.name) not added."
        end
    end
end

function create_load_forecasts(load_dir::String, loads::Vector{PowerLoad})
    #################
    # Step 1: Read and Process Stochastic Loads
    #################
    # Read in the stochastic load values
    file_name = "Stochastic_Loads_CY2028_WY1998-2022.csv"
    file_path = joinpath(load_dir, file_name)
    df = CSV.read(file_path, DataFrame)

    # Filter out leap day (February 29)
    df = filter(row -> !(row.Month == 2 && row.Day == 29), df)

    # Initialize the dictionary to store each weather year as a separate DataFrame
    load_ts_dict = Dict{String, DataFrame}()

    # Define the timestamps for 8760 hours in a year
    tstamps = collect(range(DateTime("2030-01-01T00:00:00"), DateTime("2030-12-31T23:00:00"), step = Dates.Hour(1)))

    # Populate the dictionary with weather year data
    for i in 1:25
        year_label = "Y$(1997 + i)"  # Construct year label (e.g., "Y1998", "Y1999", ...)
        load_values = df[!, Symbol(string(i))]  # Extract the load values for this year
        load_ts_dict[year_label] = DataFrame(:Time => tstamps, :Load => load_values)  # Add time and load columns
    end

    #################
    # Step 2: Read and Process Load Allocation Data
    #################
    # Read in monthly load allocations
    file_name = "NVE_Load_Share_Allocation.csv"
    file_path = joinpath(load_dir, file_name)
    df_demand_allocation = CSV.read(file_path, DataFrame)

    # Drop the :Month column
    df_demand_allocation = select!(df_demand_allocation, Not(:Month))

    #################
    # Step 3: Dynamically Initialize Split Load Dictionary
    #################
    # Initialize the dictionary to store split load time series
    split_load_ts_dict = Dict{String, Dict{String, DataFrame}}()

    # Populate split_load_ts_dict` with PowerLoad names
    for load in loads
        load_name = get_name(load)  # Dynamically retrieve the name of each PowerLoad
        split_load_ts_dict[load_name] = Dict{String, DataFrame}()  # Initialize an inner dictionary for each load
    end

    #################
    # Step 4: Populate Split Load Time Series
    #################
    for (year, load_df) in load_ts_dict
        # Extract hourly load data and timestamps
        total_load = load_df[:, :Load]
        timestamps = load_df[:, :Time]

        # Iterate through each PowerLoad in df_demand_allocation
        for (col, load_name) in zip(eachcol(df_demand_allocation), names(df_demand_allocation))
            # Initialize an array for the split load
            split_load = Vector{Float64}(undef, length(total_load))

            # Split the load based on the allocation factors
            for i in 1:length(total_load)
                current_month = month(timestamps[i])  # Extract the current month (1–12)
                allocation_factor = col[current_month]  # Get the allocation factor for this month
                split_load[i] = total_load[i] * allocation_factor  # Apply the allocation factor
            end

            # Create a DataFrame for the split load
            split_load_df = DataFrame(:Time => timestamps, :Load => split_load)

            # Store the DataFrame in the appropriate dictionary
            split_load_ts_dict[load_name][year] = split_load_df
        end
    end

    #################
    # Step 5: Return Results
    #################
    return split_load_ts_dict
end


function create_load_fx_timeseries(loads::Vector{PowerLoad}, split_load_ts_dict::Dict{String, Dict{String, DataFrame}})
    # Initialize a container for storing load forecasts
    load_fx_timeseries = Dict{String, Vector{SingleTimeSeries}}()

    # Iterate through all PowerLoad objects in the system
    for load in loads
        load_name = get_name(load)  # Retrieve the name of the current PowerLoad

        # Initialize the container for this load if not already present
        if !haskey(load_fx_timeseries, load_name)
            load_fx_timeseries[load_name] = Vector{SingleTimeSeries}()  # Initialize an empty vector
        end

        # Check if the load exists in split_load_ts_dict
        if haskey(split_load_ts_dict, load_name)
            # Iterate through each weather year in split_load_ts_dict for this load
            for (year, load_df) in split_load_ts_dict[load_name]
                #troubleshooting
                #@show year
                #@show load_df

                #enter in breakpoint
                # @bp

                # Generate a unique time series name
                ts_name = "max_active_power_$(year)"  # Unique name for each time series

                # Create the time series by extracting data from load_df
                ts = SingleTimeSeries(
                    name = ts_name,
                    data = TimeArray(load_df[:, :Time], load_df[:, :Load])  # Use TimeArray from load_df
                )

                # Add the time series to the load_fx_timeseries container
                push!(load_fx_timeseries[load_name], ts)

                # Log progress (optional)
                # println("Created time series $ts_name for load $load_name for year $year")
            end
        else
            # Warn if no forecast data is found for this load
            @warn "No forecast data found for load $load_name in split_load_ts_dict."
        end
    end

    return load_fx_timeseries
end


function add_load_time_series_to_system!(sys::System, load_fx_timeseries::Dict{String, Vector{SingleTimeSeries}})
    # Loop through each load in the load_fx_timeseries dictionary
    for (load_name, ts_list) in load_fx_timeseries
        # Retrieve the PowerLoad object from the system
        active_device = get_component(PowerLoad, sys, load_name)

        if active_device !== nothing
            # Add each time series in the ts_list to the system
            for ts in ts_list
                add_time_series!(sys, active_device, ts)
                println("Added time series: ", ts.name, " to device: ", load_name)
            end
        else
            # Warn if the load device is not found in the system
            @warn "Device $load_name not found in the system. Time series not added."
        end
    end
end


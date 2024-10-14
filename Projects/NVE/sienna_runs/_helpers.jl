
function modify_data(data::PowerSystemTableData, data_dir::String)
    # Manual Modifications to Data
    df_gen = data.category_to_df[PowerSystems.InputCategoryModule.InputCategory.GENERATOR]
    df_gen[!, :fuel] = replace(df_gen[!, :fuel], "HYDROGEN" => "OTHER")
    df_gen[!, :fuel] = replace(df_gen[!, :fuel], "WASTE_HEAT" => "OTHER")
    df_gen[!, :fuel_price] = replace(df_gen[!, :fuel_price], "NA" => "0")
    df_gen[!, :fuel_price] = parse.(Float64, df_gen[!, :fuel_price])
    df_gen[!, :base_mva] = ones(nrow(df_gen))
    df_gen[!, :shut_down] = zeros(nrow(df_gen))
    df_gen[!, :start_up] = df_gen[!, :startup_cost]
    df_gen[!, :fixed] = df_gen[!, :variable_cost] # variable and fixed are flipped from r2x
    df_gen[!, :vom_price] = df_gen[!, :fixed_cost]
    df_gen[!, :prime_mover_type] = df_gen[!, :unit_type]
    df_gen[!, :rating] = df_gen[!, :active_power]
    # Cols to drop
    columns_to_drop = ["startup_cost", "fixed_cost", "variable_cost"]
    df_gen = select(df_gen, Not(columns_to_drop))

    # Need to manually fill in the NA values in the linear heat rate data which I will later replace with the PWL function data, in the file i manully put trash values in there.
    for i in 1:nrow(df_gen)
        if df_gen[i, :heat_rate_incr_1] != "NA"
            df_gen[i, :heat_rate_a0] = "0"
            df_gen[i, :heat_rate_a1] = "0"
        end
    end

    # Specify the list of columns that should not be dropped
    columns_to_keep = ["heat_rate_a2", "category", "pump_load"]  
    df_gen = select(df_gen, Not([col for col in names(df_gen) if all(x -> x == "NA", df_gen[!, col]) && !(col in columns_to_keep)]))

    # Specify the list of columns to move into the new DataFrame
    cols = ["heat_rate_avg_0", "heat_rate_incr_1", "heat_rate_incr_2", "heat_rate_incr_3", "heat_rate_incr_4", "heat_rate_incr_5", "output_point_0", "output_point_1", "output_point_2", "output_point_3", "output_point_4", "output_point_5"]
    columns_to_remove= []
    columns_to_copy = ["name"]
    for col in cols
        if col in names(df_gen)
            push!(columns_to_copy, col)
            push!(columns_to_remove, col)
        end
    end
    pw_data = select(df_gen, columns_to_copy)
    if "heat_rate_incr_1" in names(pw_data)
        pw_data = filter(row -> row.heat_rate_incr_1 != "NA", pw_data)
    end
    for col in names(pw_data)
        if col != "name"
            pw_data[!, col] = parse.(Float64, pw_data[!, col])
        end
    end

    df_gen = select(df_gen, Not(columns_to_remove))

    CSV.write(data_dir * "/generator_TDP_output.csv", df_gen)
    CSV.write(data_dir * "/generator_PWL_output.csv", pw_data)
    data.category_to_df[PowerSystems.InputCategoryModule.InputCategory.GENERATOR] = df_gen

    df_storage = data.category_to_df[PowerSystems.InputCategoryModule.InputCategory.STORAGE]
    df_storage[!, :base_power] = ones(nrow(df_storage))
    data.category_to_df[PowerSystems.InputCategoryModule.InputCategory.STORAGE] = df_storage

    # # Get the list of column names for both DataFrames
    # cols_df1 = names(df_gen_stable)
    # cols_df2 = names(df_gen)
    # missing_in_df2 = setdiff(cols_df1, cols_df2)
    # missing_in_df1 = setdiff(cols_df2, cols_df1)
    # println("Columns in Stable but not in NEW: ", missing_in_df2)
    # println("Columns in NEW but not in STABLE: ", missing_in_df1)
    
    return pw_data
end

function create_area_interchanges(sys::System, data_dir::String)
    
    branch_path = data_dir * "/branch.csv"
    area_interchange_data = DataFrame(CSV.File(branch_path))

    # Our Network does not have Areas in the System. First we create Areas then assign Buses their respective Area
    for bus in get_components(ACBus, sys)
        add_component!(sys, Area(name = get_name(bus)))
        set_area!(bus, get_component(Area, sys, get_name(bus)))
    end

    # In an AreaBalancePowerModel, a given area needs to have an AreaInterchange Objects that defines the Branch constraint between areas.
    # Create new AreaInterchange for each Arc defined in the system
    for line in get_components(Line, sys)
        arc = get_arc(line) # An Arc defines the topology of the network. Each line is assigned an Arc.
        from_bus = get_from(arc)
        to_bus = get_to(arc)
        add_component!(
            sys, 
            AreaInterchange(
                name = get_name(line),
                active_power_flow = 0.0,
                available = true,
                from_area = get_area(from_bus),
                to_area = get_area(to_bus),
                flow_limits = (
                    from_to=  abs(area_interchange_data[area_interchange_data.name .== get_name(line), :rating_down][1]),
                    to_from= abs(area_interchange_data[area_interchange_data.name .== get_name(line), :rating_up][1]),
                    )
            )
        )
    end
    remove_component!(Area, sys, "nothing")
end


function attach_reserve_requirements(sys::System, data_dir::String)
    reserve_path = data_dir * "/reserve_req.csv"
    df_reserve_req = DataFrame(CSV.File(reserve_path))
    timestamps = range(DateTime("2030-01-01T00:00:00"), step = Hour(1), length = 8760)

    # Convert the VariableReserve{ReserveUp} to a VariableReserveNonSpinning if the name contains string "NonSpinning"
    for reserve in get_components(VariableReserve{ReserveUp}, sys)
        reserve_name = get_name(reserve)
        reserve_array = df_reserve_req[!, reserve_name]
        ta = TimeArray(timestamps, reserve_array)
        ts = SingleTimeSeries(
            name = "requirement",
            data = ta,
        )
        add_time_series!(sys, reserve, ts)
        set_requirement!(reserve, 1)
    end
end


function constrain_market_imports(sys::System, data_dir::String)
    plexos_imports = data_dir * "/plexos_imports.csv"
    df_plexos_imports = DataFrame(CSV.File(plexos_imports))
    timestamps = range(DateTime("2030-01-01T00:00:00"), step = Hour(1), length = 8760)
    gens_renew = collect(get_components(RenewableDispatch, sys));

    southern = get_component(ThermalStandard, sys, "Southern Purchases (NVP)")
    northern = get_component(ThermalStandard, sys, "Northern Purchases (Sierra)")

    # Add Market Purchases as RenewableDispatch
    names = ["Southern Purchases (NVP)", "Northern Purchases (Sierra)"]
    for name in names
        thermal_gen = get_component(ThermalStandard, sys, name)
        set_available!(thermal_gen, false)

        renew_dispatch = RenewableDispatch(
            name = name,
            bus = get_bus(thermal_gen),
            available = true,
            rating = get_max_active_power(thermal_gen),
            active_power = 0.0,
            reactive_power = 0.0,
            operation_cost = get_operation_cost(gens_renew[1]),
            prime_mover_type = PrimeMovers.PVe,
            reactive_power_limits = (0.0, 0.0),
            power_factor = 1.0,
            base_power= 1.0,
        )
        add_component!(sys, renew_dispatch)
        import_limits = df_plexos_imports[!, name]
        ta = TimeArray(timestamps, import_limits)
        ts = SingleTimeSeries(
            name = "max_active_power",
            data = ta,
            # scaling_factor_multiplier = get_max_active_power
        )
        add_time_series!(sys, renew_dispatch, ts)
    end
    set_available!(get_component(ThermalStandard, sys, "Southern Purchases (NVP)"), false)
    set_available!(get_component(ThermalStandard, sys, "Northern Purchases (Sierra)"), false)

end

# #Load Stable Data
# r2x_output_name = "output_stable"
# data_dir = "Projects/NVE/" # r2x output
# output_dir = "Projects/NVE/sienna_runs/run_output/" # Sienna outputs
# scenario_dir = output_dir * "results_no_imports/" # Change if youre creating a different sienna scenario
# if !isdir(scenario_dir)
#     mkdir(scenario_dir)
# end

# ## Load and Save System From Parse R2X Data
# logger = configure_logging(console_level=Logging.Info)
# base_power = 1.0
# descriptors = "Projects/NVE/sienna_runs/user_descriptors_"* r2x_output_name *".yaml"
# generator_mapping = "Projects/NVE/sienna_runs/generator_mapping.yaml"
# timeseries_metadata_file = "Projects/NVE/output/timeseries_pointers.json"
# stable = PowerSystemTableData(
#     data_dir * r2x_output_name,
#     base_power,
#     descriptors;
#     generator_mapping_file = generator_mapping,
#     timeseries_metadata_file = timeseries_metadata_file,
# )
# df_gen_stable = stable.category_to_df[PowerSystems.InputCategoryModule.InputCategory.GENERATOR]
# df_load_stable = stable.category_to_df[PowerSystems.InputCategoryModule.InputCategory.LOAD]






################################################################################

# # Interactive Plot
# plotlyjs()
# plot_fuel(results; stair = true)


# ### get LMPS
# network_dual = read_realized_dual(results, "CopperPlateBalanceConstraint__System")



# #######
# # Adding MarketBidCost to Generators
# #######
# # Loading fuel_price data
# fuel_price_path = data_dir * "Data/ThermalStandard_fuel_price__2030.csv"
# fuel_price = DataFrame(CSV.File(fuel_price_path))

# # # datetime_col = fuel_price.DateTime
# # for column in names(fuel_price)
# #     if column != "DateTime"
# #         gen = get_component(ThermalStandard, sys, column)
# #         fp_data = fuel_price[!, gen_name]
# #         oc = get_operation_cost(gen)
# #         vc = get_value_curve(get_variable(oc))
# #         function_data = get_function_data(vc)
# #         constant_term = get_constant_term(function_data)
# #         proportional_term = get_proportional_term(function_data)
        
# #         power = get_active_power(gen) #need to check if max_active_power ts is set, use that instead if solve
# #         powers = ones(length(fp_data)) * power
# #         mc_data = proportional_term * fp_data
# #         market_curve = make_market_bid_curve(powers, mc_data)
        
# #         mbc =MarketBidCost(no_load_cost= 0, start_up=0, shut_down =0, incremental_offer_curves = market_curve)
# #         set_operation_cost!(gen, mbc)
# #     end
# # end

# # Single Generator MarketBidCost Example
# gen_name = "Clark 14" # quadratic value curve
# gen_name = "Clark 7, 8, 9_B" # linear value curve
# gen = get_component(ThermalStandard, sys, gen_name)

# # First gather existing data on generator operation_cost
# fp_data = fuel_price[!, gen_name]
# oc = get_operation_cost(gen)
# vc = get_value_curve(get_variable(oc))
# function_data = get_function_data(vc)
# constant_term = get_constant_term(function_data) # zero
# proportional_term = get_proportional_term(function_data)

# # Set MarketBidCost Structure with empty variable_cost to populate with market bid data
# mbc = MarketBidCost(
#         no_load_cost= 0,
#         start_up=0, 
#         shut_down =0, 
#     )
# set_operation_cost!(gen, mbc)

# # Pass Market Bid Data to MarketBidCost
# # PiecewiseIncrementalCurve(0.0, [0.0, 100.0, 105.0, 120.0, 130.0], [25.0, 26.0, 28.0, 30.0])

# # Create MarketBidCurve
# # Single timestep example
# mc_data = proportional_term * fp_data
# min_active_power = get_active_power_limits(gen)[1]
# max_active_power = get_active_power_limits(gen)[2]

# market_curve = PiecewiseIncrementalCurve(constant_term, [min_active_power, max_active_power], [mc_data[1]])
# cost_curve = CostCurve(market_curve)

# mbc = MarketBidCost(
#         no_load_cost= 0,
#         start_up=0, 
#         shut_down =0, 
#         incremental_offer_curves = cost_curve
#     )
# set_operation_cost!(gen, mbc)
# get_operation_cost(gen)

# # Multi timestep example
# market_curve = []
# for (i, fp) in enumerate(fp_data)
#     mc_data = proportional_term * fp
#     # market_curve_i = PiecewiseIncrementalCurve(constant_term, [min_active_power, max_active_power], [mc_data])
#     market_curve_i = PiecewiseStepData([min_active_power, max_active_power], [mc_data])
#     push!(market_curve, market_curve_i)
# end
# timestamps = range(DateTime("2030-01-01T00:00:00"), step = Hour(1), length = 8760)
# market_bid_data = Dict(timestamps => market_curve)

# market_bid_data = Dict(Dates.DateTime("2030-01-01") => market_curve)
# time_series_data = Deterministic(
#            name = "variable_cost",
#            data = market_bid_data,
#            resolution = Dates.Hour(1)
#        )
# set_variable_cost!(sys, gen, time_series_data)

# get_operation_cost(gen)


# # # Time varying data to submit bids as generators in the network
# # market_bid_data = 
# #     Dict(Dates.DateTime("2030-01-01") => [
# #         PiecewiseStepData([0, 2.0, 3.0], [4.0, 6.0]),
# #         PiecewiseStepData([0, 2.0, 6.0], [2.0, 12.0]),]
# #     )

# # time_series_data = Deterministic(
# #            name = "variable_cost",
# #            data = market_bid_data,
# #            resolution = Dates.Hour(1)
# #        )

# # set_variable_cost!(sys, gen, time_series_data)

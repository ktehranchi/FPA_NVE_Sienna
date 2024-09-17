using PowerSystems, Dates

#### 
# Time Varying MarketBidCost
# We will need to use Time varying data to submit bids as generators in the network   
####
bus = ACBus(1, "nodeE", "REF", 0, 1.0, (min = 0.9, max = 1.05), 230, nothing, nothing)

generator = ThermalStandard(
               name = "Brighton",
               available = true,
               status = true,
               bus = bus,
               active_power = 6.0,
               reactive_power = 1.50,
               rating = 0.75,
               prime_mover_type = PrimeMovers.ST,
               fuel = ThermalFuels.COAL,
               active_power_limits = (min = 0.0, max = 6.0),
               reactive_power_limits = (min = -4.50, max = 4.50),
               time_limits = (up = 0.015, down = 0.015),
               ramp_limits = (up = 5.0, down = 3.0),
               operation_cost = MarketBidCost(
                   no_load_cost = 0.0,
                   start_up = (hot = 0.0, warm = 0.0, cold = 0.0),
                   shut_down = 0.0,
               ),
               base_power = 100.0,
           )

# These are functionally equivalent (Pretty sure?)
IncrementalCurve(PiecewiseStepData([1.0, 2.0, 3.0], [4.0, 6.0]), 20.0)
PiecewiseIncrementalCurve(20.0, [1.0, 2.0, 3.0], [4.0, 6.0])
PiecewiseStepData([1.0, 2.0, 3.0], [24.0, 26.0])
    
data = 
    Dict(Dates.DateTime("2020-01-01") => [
        PiecewiseStepData([1.0, 2.0, 3.0], [4.0, 6.0]),
        PiecewiseStepData([1.0, 2.0, 6.0], [2.0, 12.0]),]
    )

# This formulation will error: the data must be of type PiecewiseStepData
# data = Dict(Dates.DateTime("2020-01-01") => [
#     PiecewiseIncrementalCurve(20.0, [1.0, 2.5, 3.0], [4.0, 16.0]),
#     PiecewiseIncrementalCurve(20.0, [1.0, 2.0, 3.0], [4.0, 6.0])
#     ]
# )

# # This formulation will error: the data must be of type PiecewiseStepData
# data = Dict(Dates.DateTime("2020-01-01") => [
#     LinearCurve(6.0),
#     LinearCurve(3.0),
#     ]
# )

time_series_data = Deterministic(
           name = "variable_cost",
           data = data,
           resolution = Dates.Hour(1)
       )

sys = System(100.0, [bus], [generator])

set_variable_cost!(sys, generator, time_series_data)

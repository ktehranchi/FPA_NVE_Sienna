import marimo

__generated_with = "0.9.12"
app = marimo.App()


@app.cell
def __(mo):
    mo.md(r"""# R2X: Plexos & Sienna Comparison""")
    return


@app.cell
def __():
    import pandas as pd
    from pathlib import Path
    import matplotlib.pyplot as plt
    return Path, pd, plt


@app.cell
def __():
    def add_missing_carriers(df1, df2):
        for carrier in df1.columns:
            if carrier not in df2.columns:
                df2[carrier] = 0
        for carrier in df2.columns:
            if carrier not in df1.columns:
                df1[carrier] = 0
        return df1, df2

    colors_fuel = {
        "Natural gas": "#800080",
        "Hydropower": "#1f77b4",
        "Wind": "#87ceeb",
        "Biopower": "#228b22",
        "Geothermal": "#8b4513",
        "PV": "#ffd700",
        "Storage": "#5dbb26",
        "Storage_Charge": "#5dbb26",
        "Storage_Discharge": "#5dbb26",
        "Petroleum": "#333333",
        "Other": "#bcbd22",
        "Unserved Energy": "#ff0000",
        "Curtailment": "#ff6347",
        "Over Generation": "#00ff00",
    }

    fuel_name_mapper = { # Maps fuel names/ PM names to the fuel names used in Sienna data
        'OIL': 'Petroleum',
        'OTHER': 'Other',
        'HY': 'Hydropower',
        'WT': 'Wind',
        'WOOD_WASTE': 'Biopower',
        'WASTE_HEAT': 'Other',
        'GEOTHERMAL': 'Geothermal',
        'GAS': 'Natural gas',
        'PV': 'PV',
        'BA': 'Storage',
        'HYDROGEN': 'Other',
    }
    return add_missing_carriers, colors_fuel, fuel_name_mapper


@app.cell
def __(Path):
    sienna_results_folder = Path('run_output/output_test')
    plexos_results_path = Path('PLEXOS ST Results NVE 7_19_24  No AS 2030-2.xlsx')
    return plexos_results_path, sienna_results_folder


@app.cell(hide_code=True)
def __(mo):
    mo.md(r"""## Demand Comparison""")
    return


@app.cell
def __(pd, sienna_results_folder):
    # Read Sienna Demand
    df_sienna_demand = (pd.read_csv(sienna_results_folder / 'load_active_power.csv') *-1)
    df_sienna_demand
    return (df_sienna_demand,)


@app.cell
def __(df_sienna_demand, pd, plexos_results_path):
    # Read Plexos Results
    df_plexos_load = pd.read_excel(plexos_results_path, sheet_name='Native Load')
    df_plexos_load.drop(columns=[	"Parent Name", "Collection", "Property", "Band", "Units"], inplace=True)
    df_plexos_load.rename(columns={"Datetime": "DateTime"}, inplace=True)
    # Remove any zero load columns
    df_plexos_load = df_plexos_load.iloc[:len(df_sienna_demand)]
    df_plexos_load.set_index('DateTime', inplace=True)
    df_plexos_load = df_plexos_load.loc[:, (df_plexos_load.sum(axis=0) != 0)]
    df_plexos_load
    return (df_plexos_load,)


@app.cell
def __(df_plexos_load, df_sienna_demand, pd):
    df_plexos_load_1 = df_plexos_load[['Nevada Power', 'Sierra']].add_suffix('_Plexos')
    df_sienna_demand_1 = df_sienna_demand[['Nevada Power', 'Sierra']].add_suffix('_Sienna')
    df = pd.DataFrame([df_plexos_load_1['Nevada Power_Plexos'].reset_index(drop=True), df_sienna_demand_1['Nevada Power_Sienna'].reset_index(drop=True), df_plexos_load_1['Sierra_Plexos'].reset_index(drop=True), df_sienna_demand_1['Sierra_Sienna'].reset_index(drop=True)]).T
    df['diff_NP'] = df['Nevada Power_Plexos'] - df['Nevada Power_Sienna']
    df['diff_Sierra'] = df['Sierra_Plexos'] - df['Sierra_Sienna']
    df
    df.plot()
    return df, df_plexos_load_1, df_sienna_demand_1


@app.cell
def __(mo):
    mo.md(r"""## Generation Comparison""")
    return


@app.cell
def __(Path, fuel_name_mapper, pd):
    # Load Generator Fuel Mapping File
    gen_properties = pd.read_csv(Path('../output_test/gen.csv'), index_col=0)
    gen_properties['fuel_type'] = gen_properties.fuel.fillna(gen_properties.unit_type)
    gen_properties['fuel_name'] = gen_properties.fuel_type.map(fuel_name_mapper)
    print(gen_properties.fuel_name.unique())
    print(gen_properties.fuel_type.unique())
    return (gen_properties,)


@app.cell
def __(pd, plexos_results_path):
    # Read Plexos Results
    df_plexos_generation = pd.read_excel(plexos_results_path, sheet_name='Generation')
    df_plexos_generation.drop(columns=[	"Parent Name", "Collection", "Property", "Band", "Units"], inplace=True)
    df_plexos_generation.rename(columns={"Datetime": "DateTime"}, inplace=True)
    df_plexos_generation.set_index('DateTime', inplace=True)
    # Add storage data
    df_plexos_storage = pd.read_excel(plexos_results_path, sheet_name='Net_Gen (stor)')
    df_plexos_storage.drop(columns=["Parent Name", "Collection", "Property", "Band", "Units"], inplace=True)
    df_plexos_storage.rename(columns={"Datetime": "DateTime"}, inplace=True)
    df_plexos_storage.set_index('DateTime', inplace=True)

    df_plexos_generation = pd.concat([df_plexos_generation, df_plexos_storage], axis=1)
    df_plexos_generation.head(5)
    return df_plexos_generation, df_plexos_storage


@app.cell
def __(df_plexos_generation, gen_properties):
    # Group plexos results by fuel type
    df_plexos_gen_by_fuel = df_plexos_generation.groupby(gen_properties.fuel_name, axis =1).sum()
    df_plexos_gen_by_fuel['Storage_Charge'] = df_plexos_gen_by_fuel['Storage'].clip(upper=0)
    df_plexos_gen_by_fuel['Storage_Discharge'] = df_plexos_gen_by_fuel['Storage'].clip(lower=0)
    df_plexos_gen_by_fuel.drop(columns=['Storage'], inplace=True)
    df_plexos_gen_by_fuel.head(5)
    return (df_plexos_gen_by_fuel,)


@app.cell
def __(pd, sienna_results_folder):
    df_sienna_gen = pd.read_csv(sienna_results_folder / 'generator_active_power.csv')
    df_sienna_gen
    return (df_sienna_gen,)


@app.cell
def __(pd, sienna_results_folder):
    df_sienna_fuel = pd.read_csv(sienna_results_folder / 'generation_by_fuel.csv')
    df_sienna_fuel
    return (df_sienna_fuel,)


@app.cell
def __(pd, sienna_results_folder):
    df_storage_charge = pd.read_csv(sienna_results_folder / 'storage_charge.csv', index_col=0)
    df_storage_charge.plot()
    return (df_storage_charge,)


@app.cell
def __(df_sienna_fuel, df_sienna_gen, df_storage_charge, pd):
    # Read Sienna Resuts
    df_sienna_gen['DateTime'] = pd.to_datetime(df_sienna_gen['DateTime'])
    df_sienna_gen.set_index('DateTime', inplace=True)
    df_sienna_fuel.Curtailment = df_sienna_fuel.Curtailment.clip(lower=0) # clip small negative curtailment values
    df_sienna_fuel.index = df_sienna_gen.index # assign timestamp

    df_sienna_fuel['Storage_Charge'] = (df_storage_charge.sum(axis=1) * -1).clip(upper=0).values
    df_sienna_fuel.rename(columns={'Storage':'Storage_Discharge'}, inplace=True)
    df_sienna_fuel.plot(kind='area', stacked=True)
    return


@app.cell
def __(df_sienna_fuel, df_sienna_gen):
    # modify plot to show imports as thermal
    df_sienna_fuel['Natural gas'] = df_sienna_fuel['Natural gas'] + df_sienna_gen[['Southern Purchases (NVP)','Northern Purchases (Sierra)']].sum(axis=1)
    df_sienna_fuel['PV'] = df_sienna_fuel['PV'] - df_sienna_gen[['Southern Purchases (NVP)','Northern Purchases (Sierra)']].sum(axis=1)
    return


@app.cell
def __(df_plexos_gen_by_fuel, df_sienna_fuel):
    # Prepare for plotting
    plexos = df_plexos_gen_by_fuel.loc[df_sienna_fuel.index].copy()
    sienna = df_sienna_fuel

    COLUMN_ORDER = ['Geothermal', 'Biopower', 'Hydropower', 'Petroleum', 'Other','Natural gas', 'Wind', 'PV', 'Unserved Energy',  'Over Generation', 'Storage_Discharge', 'Storage_Charge']

    plexos = plexos.reindex(columns=COLUMN_ORDER)
    sienna = sienna.reindex(columns=COLUMN_ORDER)

    plexos.head(5)
    return COLUMN_ORDER, plexos, sienna


@app.cell
def __(pd, plexos, sienna):
    start_time = pd.Timestamp(2030, 1, 1)
    end_time = pd.Timestamp(2030, 1, 6)
    sienna_1 = sienna.loc[start_time:end_time]
    plexos_1 = plexos.loc[start_time:end_time]
    return end_time, plexos_1, sienna_1, start_time


@app.cell
def __(colors_fuel, plexos_1, plt, sienna_1):
    title = 'Generation by Fuel Type'
    save_path = 'validation/generation_by_fuel.png'
    colors = colors_fuel
    kwargs = dict(color=colors, ylabel='Production [MW]', xlabel='', linewidth=0)
    fig, axes = plt.subplots(3, 1, figsize=(9, 9))
    sienna_1.plot.area(ax=axes[0], **kwargs, legend=False, title='Sienna')
    order = sienna_1.columns
    plexos_1.plot.area(ax=axes[1], **kwargs, legend=False, title='Plexos')
    diff = (sienna_1 - plexos_1).fillna(0)
    diff.clip(lower=0).plot.area(ax=axes[2], title='$\\Delta$ (sienna - plexos)', legend=False, **kwargs)
    diff.clip(upper=0).plot.area(ax=axes[2], **kwargs, legend=False)
    lower_lim = min(axes[0].get_ylim()[0], axes[1].get_ylim()[0], axes[2].get_ylim()[0])
    upper_lim = max(axes[0].get_ylim()[1], axes[1].get_ylim()[1], axes[2].get_ylim()[1])
    axes[0].set_ylim(bottom=lower_lim, top=upper_lim)
    axes[1].set_ylim(bottom=lower_lim, top=upper_lim)
    diff_lim_upper = diff.clip(lower=0).sum(axis=1).max()
    diff_lim_lower = diff.clip(upper=0).sum(axis=1).min()
    axes[2].set_ylim(bottom=min(lower_lim, diff_lim_lower), top=max(upper_lim, diff_lim_upper))
    h, l = axes[0].get_legend_handles_labels()
    _fig.legend(h[::-1], l[::-1], loc='center left', bbox_to_anchor=(1.05, 0.5), ncol=1, frameon=True, labelspacing=0.1)
    plt.suptitle(title)
    _fig.tight_layout()
    _fig.savefig(save_path, dpi=300)
    return (
        axes,
        colors,
        diff,
        diff_lim_lower,
        diff_lim_upper,
        fig,
        h,
        kwargs,
        l,
        lower_lim,
        order,
        save_path,
        title,
        upper_lim,
    )


@app.cell
def __(df_plexos_generation, df_sienna_gen):
    df_plexos_match = df_plexos_generation.loc[df_sienna_gen.index, df_sienna_gen.columns]
    return (df_plexos_match,)


@app.cell
def __(df_plexos_generation, pd, sienna_results_folder):
    df_sienna_renewable_parameters = pd.read_csv(sienna_results_folder / 'renewable_parameters.csv')
    df_sienna_renewable_parameters.set_index('DateTime', inplace=True)
    df_sienna_renewable_parameters.index = pd.to_datetime(df_sienna_renewable_parameters.index)
    df_plexos_renew_match = df_plexos_generation.loc[df_sienna_renewable_parameters.index, df_sienna_renewable_parameters.columns]
    (df_sienna_renewable_parameters - df_plexos_renew_match).sum().sort_values().head(20)
    return df_plexos_renew_match, df_sienna_renewable_parameters


@app.cell
def __(df_plexos_match, df_sienna_gen):
    (df_sienna_gen - df_plexos_match)
    return


@app.cell
def __(df_plexos_match, df_sienna_gen):
    df_plexos_match[['Northern Purchases (Sierra)', 'Southern Purchases (NVP)']].plot(title='Plexos Purchases')
    df_sienna_gen[['Northern Purchases (Sierra)', 'Southern Purchases (NVP)']].plot(title='Sienna Purchases')
    return


@app.cell
def __(mo):
    mo.md(r"""## Compare Line Flows""")
    return


@app.cell
def __(pd, plexos_results_path):
    # Read Plexos Results
    df_plexos_tx = pd.read_excel(plexos_results_path, sheet_name='TX')
    df_plexos_tx.drop(columns=[	"Parent Name", "Collection", "Property", "Band", "Units"], inplace=True)
    df_plexos_tx.rename(columns={"Datetime": "DateTime"}, inplace=True)
    df_plexos_tx.set_index('DateTime', inplace=True)
    df_plexos_tx
    return (df_plexos_tx,)


@app.cell
def __(pd, sienna_results_folder):
    # Read Sienna Resuts
    df_sienna_tx = pd.read_csv(sienna_results_folder / 'tx_flow.csv')
    df_sienna_tx['DateTime'] = pd.to_datetime(df_sienna_tx['DateTime'])
    df_sienna_tx.set_index('DateTime', inplace=True)
    df_sienna_tx
    return (df_sienna_tx,)


@app.cell
def __(df_plexos_tx, df_sienna_tx, plt):
    import random
    df_plexos_tx_1 = df_plexos_tx.loc[df_sienna_tx.index]
    colors_tx = {column: '#' + ''.join(random.choices('0123456789ABCDEF', k=6)) for column in df_sienna_tx.columns}
    fig_1, ax = plt.subplots(1, 1, figsize=(9, 6))
    df_sienna_tx.plot(ax=ax, title='Sienna', legend=False, color=colors_tx)
    df_plexos_tx_1.plot(ax=ax, title='Plexos', legend=False, linestyle='--', color=colors_tx)
    handles, labels = ax.get_legend_handles_labels()
    unique_labels = list(set(labels))
    unique_handles = [handles[labels.index(label)] for label in unique_labels]
    dashed_handles = [plt.Line2D([], [], linestyle='--', color='black', label='Plexos')]
    dashed_labels = ['Plexos']
    all_handles = unique_handles + dashed_handles
    all_labels = unique_labels + dashed_labels
    ax.legend(all_handles, all_labels)
    return (
        all_handles,
        all_labels,
        ax,
        colors_tx,
        dashed_handles,
        dashed_labels,
        df_plexos_tx_1,
        fig_1,
        handles,
        labels,
        random,
        unique_handles,
        unique_labels,
    )


@app.cell
def __(pd, sienna_results_folder):
    df_sienna_pc = pd.read_csv(sienna_results_folder / 'production_costs.csv')

    df_sienna_pc['DateTime'] = pd.to_datetime(df_sienna_pc['DateTime'])
    df_sienna_pc.set_index('DateTime', inplace=True)

    df_sienna_pc.sum(axis=1).resample("1D").sum()
    return (df_sienna_pc,)


@app.cell
def __():
    def harry_plexos(production):
        constant = 4131.864122174
        set_point_coeff = 4.224868900963997
        tranch_rates = [-72.1847470888, -62.82746505604, -54.1187075206, -46.05847448248, -38.64676594168, -31.883581935, -25.7689223889, -20.30278734006, -15.4851767885]
        tranch_coeffs = [0.0693069306930693, 0.0796292395196966, 0.09244314013206, 0.1086206896551725, 0.129452054794, 0.156911581569115, 0.194144838212635, 0.2464146023468058, 0.27]
        tranch_setpoints = [coeff * production for coeff in tranch_coeffs]
        tranch_costs = 0
        for i in range(len(tranch_rates)):
            tranch_costs = tranch_costs + tranch_rates[i] * tranch_setpoints[i]
        return constant + set_point_coeff * production + tranch_costs
    return (harry_plexos,)


@app.cell
def __(mo):
    mo.md(
        r"""
        # Outstanding Issues

        ## R2X


        ## Sienna
        - MarketBid Cost
        - Max Energy Monthly for Market Purchases ThermalStandard Objects, and for The Hydro Resources
        """
    )
    return


@app.cell
def __(mo):
    mo.md(
        r"""
        Max Energy Month:
        - imports as transmission interface with a schedule. ... max energy month gets captured on the interfaces.

        Services:
        - turn off A/S for storage , and once completely
        - export the plexos allocation of reserves to units

        Plotting:
        - LMP spread
        """
    )
    return


@app.cell
def __(mo):
    mo.md(r""" """)
    return


@app.cell
def __():
    import marimo as mo
    return (mo,)


if __name__ == "__main__":
    app.run()

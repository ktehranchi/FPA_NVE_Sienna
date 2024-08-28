"""
First Step towards this demo is to create a Julia Project Enviornment for the training session. Within your Julia REPL, you can create a new project by running the following command:
    generate demo_training
This will create a new folder called demo_training with the following structure:
    demo_training/
        Project.toml
        Manifest.toml
        src/
            demo_training.jl
These files will be used to manage the dependencies for the training session.

Next, you should add the packages you will use in the training within the REPL by running the following commands:
    ] add PowerSystems PowerSimulations PowerSystemCaseBuilder PowerGraphics HiGHS Gurobi Dates Logging DataFrames Plots

Everytime you open a Julia REPL to work with sienna you can navigate to the folder which contains the Project.toml and type '] activate .' to activate the project environment. This will load the dependencies you added in the previous step.
"""
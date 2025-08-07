# Test Julia file for auto-detection

using LinearAlgebra
using Plots
using DataFrames

# This should trigger:
# 1. "Detected Julia file - checking for Jupyter support..."
# 2. Auto kernel initialization or selection
# 3. Package detection showing: LinearAlgebra, Plots, DataFrames

function greet(name)
    println("Hello, $name!")
end

greet("Pyworks")
#####################################################
# Surya
# NREL
# December 2021
# Compare SIIP PSI results to EGRET UC/ED (Prescient) Results
# Filter by timestamp ; Filter by Unit Type (CC/CT)
#####################################################
import DataFrames
import JSON
import CSV
import Dates
#####################################################
# Struct to make a JSON with result discrepancy
#####################################################
struct result_disc
    component_name::String
    EGRET::Union{Int64,Float64,Bool}
    SIIP::Union{Int64,Float64,Bool}
    timestamp::Dates.DateTime

    result_disc(x="101_CT_1",y=20.01,z=20.009,ts=Dates.DateTime(2020,7,1,12)) = new(x,y,z,ts)
end
#####################################################
# Loading the EGRET and SIIP Results
#####################################################
Location_1 = "/Users/sdhulipa/Desktop/OneDrive - NREL/NREL-Github/EGRET-SIIP-Results/data/CSV_Results/UC/On__ThermalStandard_UC.csv"
Location_2 = "/Users/sdhulipa/Desktop/OneDrive - NREL/NREL-Github/EGRET-SIIP-Results/data/DAY_AHEAD_Results_2020-07-01_2020-07-14.json"

df_siip_thermal_uc_results = DataFrames.DataFrame(CSV.File(Location_1));
EGRET_UC_results = JSON.parsefile(Location_2);
       
gen_comps = EGRET_UC_results["elements"]["generator"];

date_format = Dates.DateFormat("Y-m-d H:M")
time_stamps = Dates.DateTime.(EGRET_UC_results["system"]["time_keys"],date_format)

df = DataFrames.DataFrame()

for col_name in DataFrames.names(df_siip_thermal_uc_results)
    if (col_name !="DateTime")
        # SIIP values need to be rounded because in some instances a ON status is recorded as '0.999999999999997'
        model_results_dict = Dict([("SIIP", round.(df_siip_thermal_uc_results[!,col_name])), ("EGRET", round.(gen_comps[col_name]["commitment"]["values"]))]);
        for idx in 1:length(time_stamps)
            for model in keys(model_results_dict)
                results_dict = Dict()
                push!(results_dict,"DateTime" =>time_stamps[idx])
                push!(results_dict,"Generator_Name" =>col_name)
                push!(results_dict,"Model" =>model)
                push!(results_dict,"Value" =>model_results_dict[model][idx])

                append!(df,results_dict)
            end
        end
    end
end
csv_path = "/Users/sdhulipa/Desktop/OneDrive - NREL/NREL-Github/EGRET-SIIP-Results/data/test.csv"
CSV.write(csv_path, df,writeheader = true)

result_discrepancies = []
# Compare Results
for col_name in DataFrames.names(df_siip_thermal_uc_results)
    if (col_name !="DateTime")
        # SIIP values need to be rounded because in some instances a ON status is recorded as '0.999999999999997'
        siip_results = round.(df_siip_thermal_uc_results[!,col_name])
        egret_results = round.(gen_comps[col_name]["commitment"]["values"])
        for idx in 1:length(time_stamps)
            if (siip_results[idx] != egret_results[idx])
                temp = result_disc(col_name,egret_results[idx],siip_results[idx],time_stamps[idx]);
                push!(result_discrepancies,Dict(fn=>getfield(temp, fn) for fn ∈ fieldnames(result_disc)));
            end
        end
    end
end

data = Dict("result_comparison" => result_discrepancies)

json_path = "/Users/sdhulipa/Desktop/OneDrive - NREL/NREL-Github/EGRET-SIIP-Results/data/test.json"
open(json_path,"w") do f
    JSON.print(f, data, 4)
end

# New comparsion report - filtering by timestamp
import OrderedCollections
struct result_disc_new
    component_name::String
    EGRET::Union{Int64,Float64,Bool}
    SIIP::Union{Int64,Float64,Bool}

    result_disc_new(x="101_CT_1",y=20.01,z=20.009) = new(x,y,z)
end

disc_dict = OrderedCollections.OrderedDict()
for idx in 1:length(time_stamps)
    result_discrepancies = []
    for col_name in DataFrames.names(df_siip_thermal_uc_results)
        if (col_name !="DateTime")
            siip_result = round(df_siip_thermal_uc_results[idx,col_name])
            egret_result = round.(gen_comps[col_name]["commitment"]["values"])[idx]
            
            if (siip_result != egret_result)
                temp = result_disc_new(col_name,egret_result,siip_result);
                push!(result_discrepancies,Dict(fn=>getfield(temp, fn) for fn ∈ fieldnames(result_disc_new)));
            end
            
        end
        if (length(result_discrepancies) !=0)
            push!(disc_dict,time_stamps[idx] => result_discrepancies)
        end 
    end
end

json_path = "/Users/sdhulipa/Desktop/OneDrive - NREL/NREL-Github/EGRET-SIIP-Results/data/test-new.json"
open(json_path,"w") do f
    JSON.print(f, disc_dict, 4)
end
#=
thermal_gen_keys = [key for key in keys(gen_comps) if get(gen_comps[key],"generator_type","None") == "thermal"]
all_renewable_gen_keys = [key for key in keys(gen_comps) if get(gen_comps[key],"generator_type","None") == "renewable"]
hydro_gen_keys = [key for key in all_renewable_gen_keys if get(gen_comps[key],"unit_type","None") == "HYDRO"]
renewable_standard_gen_keys = [key for key in all_renewable_gen_keys if get(gen_comps[key],"unit_type","None") != "HYDRO"]
=#
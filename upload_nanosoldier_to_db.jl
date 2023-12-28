using Tar, CodecZlib, CodecXz, CodecZstd
using BenchmarkTools
using DataFrames, Dates
using SQLite

function process_benchmark_archive(path, aid, artifact_df, pstat_df, pstat_series_table; return_group_only=false)
    println("Processing $path...")
    mktempdir() do dir
        # extract
        open(path) do io
            stream = if endswith(path, ".xz")
                XzDecompressorStream(io)
            elseif endswith(path, ".gz")
                GzipDecompressorStream(io)
            elseif endswith(path, ".zst")
                ZstdDecompressorStream(io)
            else
                error("Unknown file extension")
            end
            Tar.extract(stream, dir)
        end

        # strip the contained "data" directory
        data = joinpath(dir, "data")
        if !isdir(data)
            data = dir
        end

        firstfile = true
        for file in readdir(data)
            if !endswith(file, ".json") || !contains(file, r".(minimum|median|mean).json")
                continue
            end
            primary_metric = split(file, '.')[end-1]
            if primary_metric == "minimum"
                primary_metric = "min-wall-time"
            elseif primary_metric == "median"
                primary_metric = "median-wall-time"
            elseif primary_metric == "mean"
                primary_metric = "mean-wall-time"
            # elseif primary_metric == "std" # parsing std files fails
            #     primary_metric = "std-wall-time"
            else
                throw("Unknown metric")
            end

            group = BenchmarkTools.load(joinpath(data, file))[1]
            return_group_only && return group

            artifact_row = create_artifact_row(path, file, aid)

            # Sometimes the same commit is benchmarked multiple times, so we store the most recent data
            if isempty(artifact_df)
                idx = nothing
            else
                idx = findfirst(==(artifact_row.name), artifact_df[:, "name"])
            end
            if !isnothing(idx)
                if artifact_row.date > artifact_df[idx, "date"]
                    artifact_df[idx, "date"] = artifact_row.date

                    aid = artifact_df[idx, "id"]
                    idxs_to_del = findall(row->row["aid"]==aid, eachrow(pstat_df))
                    deleteat!(pstat_df, idxs_to_del)
                end
            else
                push!(artifact_df, artifact_row)
            end

            benchmark_data = rec_flatten_benchmarkgroup(group)

            # need to tranform into vector as indexing into df extremely slow
            names_col = pstat_series_table[:, "crate"]
            metrics_col = pstat_series_table[:, "metric"]

            for (benchmark_name, trial) in benchmark_data
                if firstfile # get alloc and memory data, same for all files
                    for metric in (:allocs, :memory) # allocs is num of allocations, memory is in bytes
                        series_id_idx = findfirst(i->names_col[i] == benchmark_name && metrics_col[i] == string(metric), 1:length(names_col))
                        series_id = pstat_series_table[series_id_idx, :id]
                        pstat_row = (series=series_id, aid=aid, cid=0, value=Float64(getfield(trial, metric)))
                        push!(pstat_df, pstat_row)
                    end
                end

                series_id_idx = findfirst(i->names_col[i] == benchmark_name && metrics_col[i] == primary_metric, 1:length(names_col))
                series_id = pstat_series_table[series_id_idx, :id]
                pstat_row = (series=series_id, aid=aid, cid=0, value=Float64(trial.time)) # time in ns
                push!(pstat_df, pstat_row)
            end

            firstfile = false
        end
    end
end

function create_pstat_rows(series_id, aid, val)
    len =  length(val)
    DataFrame(series=series_id, aid=fill(aid, len), cid=fill(0, len), value=val)
end

function create_artifact_row(path, file, id)
    commit_sha = split(file, '_')[1]
    date = join(splitpath(path)[end-2:end-1], '-') |> DateTime |> datetime2unix |> Int64
    (id=id, name=commit_sha, date=date, type="master")
end

function rec_flatten_benchmarkgroup(d)
    new_d = Dict{String, BenchmarkTools.TrialEstimate}()
    for (key, value) in pairs(d.data)
        if key isa Tuple
            key = "(" * join(key, ", ") * ")"
        end
        if isa(value, BenchmarkGroup)
            flattened_value = rec_flatten_benchmarkgroup(value)
            for (ikey, ivalue) in pairs(flattened_value)
                new_d["$key.$ikey"] = ivalue
            end
        else
            new_d[key] = value
        end
    end
    return new_d
end

function create_benchmark(data::AbstractDict)
    len = length(data)
    DataFrame(name=collect(keys(data)), stabilized=zeros(Int64, len), category=fill("primary", len))
end

function create_pstat_series(benchmark_table)
    df = DataFrame()

    pid = 1
    for row in eachrow(benchmark_table)
        for metric in ("min-wall-time", "median-wall-time", "mean-wall-time", "allocs", "memory")
            push!(df, (id=pid, crate=row["name"], profile="opt", scenario="full", backend="llvm", metric=metric))
            pid += 1
        end
    end

    return df
end

function process_benchmarks(dir)
    db = SQLite.DB("julia.db")

    # id_query = DBInterface.execute(db, "SELECT id FROM artifact ORDER BY id DESC LIMIT 1") |> DataFrame
    # id = isempty(id_query) ? 1 : id_query[1, "id"]+1
    id = 1

    pstat_series_table = DBInterface.execute(db, "SELECT * FROM pstat_series") |> DataFrame

    artifact_df = DataFrame()
    pstat_df = DataFrame()

    for (root, dirs, files) in walkdir(dir)
        for file in files
            if contains(file, r"^data.tar.\w+$")
                result = process_benchmark_archive(joinpath(root, file), id, artifact_df, pstat_df, pstat_series_table)
                id += 1
            end
        end
    end

    DBInterface.execute(db, "DELETE FROM artifact")
    artifact_df |> SQLite.load!(db, "artifact"; replace=true)
    DBInterface.execute(db, "DELETE FROM pstat")
    pstat_df |> SQLite.load!(db, "pstat"; replace=true)

    nothing
end

function main()
    process_benchmarks("/home/rag/Documents/Code/NanosoldierReports/benchmark/by_date")
end

function create_tables()
    dir = "/home/rag/Documents/Code/NanosoldierReports/benchmark/by_date"
    @show dir
    # dates = readdir(dir)
    # sort!(dates; by=x->DateTime(x))
    # last_date = dates[end]
    # dir = joinpath(dir, last_date)

    # days = readdir(dir)
    # sort!(days; by=x->parse(Int, x))
    # last_day = days[end]
    # dir = joinpath(dir, last_day)

    # for file in readdir(dir)
    #     if contains(file, r"^data.tar.\w+$")

    benchmark_table = nothing

    for (root, dirs, files) in walkdir(dir)
        for file in files
            if contains(file, r"^data.tar.\w+$")
                group = process_benchmark_archive(joinpath(root, file), nothing, nothing, nothing, nothing; return_group_only=true)
                isnothing(group) && continue
                data = rec_flatten_benchmarkgroup(group)
                new_benchmark_table = create_benchmark(data)
                if isnothing(benchmark_table)
                    benchmark_table = new_benchmark_table
                else
                    benchmark_table = unique(append!(benchmark_table, new_benchmark_table))
                end
            end
        end
    end

    pstat_series_table = create_pstat_series(benchmark_table)

    return benchmark_table, pstat_series_table

    db = SQLite.DB("julia.db")

    DBInterface.execute(db, "DELETE FROM benchmark")
    DBInterface.execute(db, "DELETE FROM pstat_series")
    benchmark_table |> SQLite.load!(db, "benchmark"; replace=true)
    pstat_series_table |> SQLite.load!(db, "pstat_series"; replace=true)

    nothing
end
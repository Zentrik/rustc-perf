using Tar, CodecZlib, CodecXz, CodecZstd
using BenchmarkTools
using DataFrames, Dates
using SQLite

function process_benchmark_archive!(df, path, artifact_id, db, benchmark_to_pstat_series_id; return_group_only=false)
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
                primary_metric = "min"
            end

            group = BenchmarkTools.load(joinpath(data, file))[1]
            return_group_only && return group

            # Sometimes the same commit is benchmarked multiple times, so we store the most recent data
            if firstfile
                artifact_row = create_artifact_row(path, file, artifact_id)

                artifact_query = DBInterface.execute(db, "SELECT * FROM artifact WHERE name='$(artifact_row.name)' LIMIT 1") |> DataFrame

                if isempty(artifact_query)
                    # artifact_row = (id=artifact_id, name=commit_sha, date=date, type="master")
                    DBInterface.execute(db, "INSERT INTO artifact (id, name, date, type) VALUES ($(artifact_row.id), '$(artifact_row.name)', $(artifact_row.date), '$(artifact_row.type)')")
                else
                    if artifact_row.date > artifact_query[1, "date"]
                        DBInterface.execute(db, "UPDATE artifact SET date=$(artifact_row.date) WHERE name='$(artifact_row.name)'")

                        aid = artifact_query[1, "id"]
                        DBInterface.execute(db, "DELETE FROM pstat WHERE aid=$aid")
                    else
                        return
                    end
                end
            end

            benchmark_data = rec_flatten_benchmarkgroup(group)

            for (benchmark_name, trial) in benchmark_data
                # benchmark_query = DBInterface.execute(db, "SELECT stabilized FROM benchmark WHERE name=$benchmark_name LIMIT 1") |> DataFrame
                # if isempty(benchmark_query)
                #     # benchmark_row = (name=benchmark_name, stabilized=0, category="primary")
                #     DBInterface.execute(db, "INSERT INTO benchmark (name, stabilized, category) VALUES ($benchmark_name, 0, 'primary')")
                # end

                if firstfile # get alloc and memory data, same for all files
                    for metric in (:allocs, :memory) # allocs is num of allocations, memory is in bytes
                        push_metric_to_pstat!(df, benchmark_name, string(metric), artifact_id, getfield(trial, metric), benchmark_to_pstat_series_id)
                    end
                end

                push_metric_to_pstat!(df, benchmark_name, primary_metric * "-wall-time", artifact_id, trial.time, benchmark_to_pstat_series_id)
                push_metric_to_pstat!(df, benchmark_name, primary_metric * "-gc-time", artifact_id, trial.gctime, benchmark_to_pstat_series_id)
            end

            firstfile = false
        end
    end
end

function push_metric_to_pstat!(df::DataFrame, benchmark_name::String, metric::String, aid::Int64, value, benchmark_to_pstat_series_id)
    # series_id_idx = findfirst(i->benchmark_names_column[i] == benchmark_name && metrics_column[i] == metric, 1:length(benchmark_names_column))
    # series_id = pstat_series_id_column[series_id_idx]
    series_id = benchmark_to_pstat_series_id[(benchmark_name, metric)]

    # series_id_query = DBInterface.execute(db, "SELECT id FROM pstat_series WHERE crate=$benchmark_name AND metric=$metric LIMIT 1") |> DataFrame
    # series_id = nothing
    # if isempty(series_id_query)
    #     # pstat_series_row = (id=pid, crate=benchmark_name, profile="opt", scenario="full", backend="llvm", metric=metric)
    #     DBInterface.execute(db, "INSERT INTO pstat_series (id, crate, profile, scenario, backend, metric) VALUES ($(pstat_series_next_id[]), $benchmark_name, 'opt', 'full', 'llvm', $metric)")
    #     series_id = pstat_series_next_id[]
    #     pstat_series_next_id[] += 1
    # else
    #     series_id = series_id_query[1, "id"]
    # end

    pstat_row = (series=series_id, aid=aid, cid=0, value=Float64(value))
    push!(df, pstat_row)
    # DBInterface.execute(db, "INSERT INTO pstat (series, aid, cid, value) VALUES ($series_id, $aid, 0, $(Float64(value)))")
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
        for metric in ("min-wall-time", "median-wall-time", "mean-wall-time", "allocs", "memory", "min-gc-time", "median-gc-time", "mean-gc-time")
            push!(df, (id=pid, crate=row["name"], profile="opt", scenario="full", backend="llvm", metric=metric))
            pid += 1
        end
    end

    return df
end

function process_benchmarks(dir, )
    db = SQLite.DB("julia.db")

    artifact_id_query = DBInterface.execute(db, "SELECT id FROM artifact ORDER BY id DESC LIMIT 1") |> DataFrame
    artifact_id = isempty(artifact_id_query) ? 1 : artifact_id_query[1, "id"]+1

    pstat_series_table = DBInterface.execute(db, "SELECT * FROM pstat_series") |> DataFrame
    # need to tranform into vector as indexing into df extremely slow
    names_col = pstat_series_table[:, "crate"]
    metrics_col = pstat_series_table[:, "metric"]
    pstat_series_id_column = pstat_series_table[:, "id"]

    benchmark_to_pstat_series_id = Dict((name, metric) => id for (id, name, metric) in zip(pstat_series_id_column, names_col, metrics_col))

    # artifact_df = DataFrame()
    # pstat_df = DataFrame()

    for (root, dirs, files) in walkdir(dir)
        pstat_df = DataFrame()
        for file in files
            if contains(file, r"^data.tar.\w+$")
                process_benchmark_archive!(pstat_df, joinpath(root, file), artifact_id, db, benchmark_to_pstat_series_id)

                artifact_id += 1
            end
        end
        if !isempty(pstat_df)
            SQLite.load!(pstat_df, db, "pstat")
        end
    end

    # dir = "/home/rag/Documents/Code/NanosoldierReports/benchmark/by_date/2023-12/28/data.tar.zst"
    # pstat_df = DataFrame()
    # result = process_benchmark_archive!(pstat_df, dir, artifact_id, db, benchmark_to_pstat_series_id)
    # return pstat_df
    # artifact_id += 1

    # for file in readdir(dir)
    #     if contains(file, r"^data.tar.\w+$")
    #         result = process_benchmark_archive(joinpath(dir, file), id, db)
    #         id += 1
    #     end
    # end


    # DBInterface.execute(db, "DELETE FROM artifact")
    # artifact_df |> SQLite.load!(db, "artifact")
    # DBInterface.execute(db, "DELETE FROM pstat")
    # pstat_df |> SQLite.load!(db, "pstat")

    nothing
end

function main(month=lpad(month(now()), 2, '0'), year=year(now()))
    process_benchmarks("/home/rag/Documents/Code/NanosoldierReports/benchmark/by_date/$year-$month")
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
                group = process_benchmark_archive!(nothing, joinpath(root, file), nothing, nothing, nothing, nothing; return_group_only=true)
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
    benchmark_table |> SQLite.load!(db, "benchmark")
    pstat_series_table |> SQLite.load!(db, "pstat_series")

    nothing
end

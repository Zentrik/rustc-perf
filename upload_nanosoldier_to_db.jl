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

        for file in readdir(data)
            if !endswith(file, ".json") || !contains(file, r".minimum.json")
                continue
            end
            group = BenchmarkTools.load(joinpath(data, file))[1]
            return_group_only && return group

            artifact_row = create_artifact_row(path, file, aid)

            data = rec_flatten_benchmarkgroup(group)
            series_ids = [pstat_series_table[findfirst(==(name), pstat_series_table[:, "crate"]), "id"] for name in keys(data)]
            pstat_rows = create_pstat_rows(series_ids, aid, (data |> values |> collect .|> x->getfield(x, :time)))# ./ 1e9)

            if isnothing(artifact_df)
                artifact_df = artifact_row
                pstat_df = pstat_rows
            else
                idx = findfirst(==(artifact_row[1, "name"]), artifact_df[:, "name"])
                if !isnothing(idx)
                    if artifact_row[1, "date"] > artifact_df[idx, "date"]
                        artifact_df[idx, "date"] = artifact_row[1, "date"]

                        aid = artifact_df[idx, "id"]
                        idxs_to_del = findall(row->row["aid"]==aid, eachrow(pstat_df))
                        deleteat!(pstat_df, idxs_to_del)
                    end
                else
                    artifact_df = append!(artifact_df, artifact_row)
                end
                pstat_df = append!(pstat_df, pstat_rows)
            end

            return artifact_df, pstat_df
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
    DataFrame(id=id, name=commit_sha, date=date, type="master")
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
    len = nrow(benchmark_table)
    DataFrame(id=1:len, crate=benchmark_table[:, "name"], profile=fill("opt", len), scenario=fill("full", len), backend=fill("llvm", len), metric=fill("min-wall-time", len))
end

function process_benchmark(dir)
    db = SQLite.DB("julia.db")
    # db = nothing

    # id_query = DBInterface.execute(db, "SELECT id FROM artifact ORDER BY id DESC LIMIT 1") |> DataFrame
    # id = isempty(id_query) ? 1 : id_query[1, "id"]+1
    id = 1

    pstat_series_table = DBInterface.execute(db, "SELECT * FROM pstat_series") |> DataFrame

    artifact_df = nothing
    pstat_df = nothing

    for (root, dirs, files) in walkdir(dir)
        for file in files
            if contains(file, r"^data.tar.\w+$")
                result = process_benchmark_archive(joinpath(root, file), id, artifact_df, pstat_df, pstat_series_table)
                isnothing(result) && continue
                artifact_df, pstat_df = result
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
    process_benchmark(joinpath(@__DIR__, "..", "/NanosoldierReports/benchmark/by_date"))
    # process_benchmark(joinpath(@__DIR__, "..", "..", "benchmark/by_date"))
end

function create_tables()
    dir = joinpath(@__DIR__, "..", "/NanosoldierReports/benchmark/by_date")
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

    db = SQLite.DB("julia.db")

    DBInterface.execute(db, "DELETE FROM benchmark")
    DBInterface.execute(db, "DELETE FROM pstat_series")
    benchmark_table |> SQLite.load!(db, "benchmark"; replace=true)
    pstat_series_table |> SQLite.load!(db, "pstat_series"; replace=true)

    nothing
end
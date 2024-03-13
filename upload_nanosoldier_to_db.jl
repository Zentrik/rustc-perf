using Tar, CodecZlib, CodecXz, CodecZstd
using BenchmarkTools
using DataFrames, Dates, TimeZones
using SQLite
using HTTP, JSON3

function process_benchmark_archive!(df, path, next_artifact_id, db, benchmark_to_pstat_series_id; return_group_only=false)
    println("Processing $path...")
    mktempdir() do dir
    # dir = mktempdir()
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

        # TODO: Support non full benchmark suites, to do need to address TODO about overwriting data conditionally
        report_file = readuntil(joinpath(splitpath(path)[1:end-1]..., "report.md"), "## Results")
        if !return_group_only && !occursin("*Tag Predicate:* `ALL`", report_file)
            return
        end

        # strip the contained "data" directory
        data = joinpath(dir, "data")
        if !isdir(data)
            data = dir
        end

        processed_commits = String[]

        for file in readdir(data)
            if !endswith(file, ".json") || !contains(file, r".(minimum|median|mean).json")
                continue
            end
            primary_metric = split(file, '.')[end-1]
            if primary_metric == "minimum"
                primary_metric = "min"
            end

            artifact_id = nothing
            sha = get_sha(file)

            # Sometimes the same commit is benchmarked multiple times, we just keep the original data
            if !return_group_only
                artifact_query = DBInterface.execute(db, "SELECT * FROM artifact WHERE name='$(sha)' LIMIT 1") |> DataFrame

                if sha ∉ processed_commits
                    if !isempty(artifact_query)
                        continue
                        # TODO: Just overwrite data we also have results for not all data
                        # DBInterface.execute(db, "DELETE FROM pstat WHERE aid=$aid")
                        # artifact_query[1, "id"]
                    end

                    artifact_row, parent_sha = create_artifact_row(path, file, next_artifact_id[])

                    pr_details = HTTP.get("https://api.github.com/repos/JuliaLang/Julia/commits/$sha/pulls").body |> JSON3.read
                    if !isempty(pr_details)
                        mini = 0
                        min_created_date = nothing
                        for i in eachindex(pr_details)
                            if isnothing(min_created_date) || DateTime(pr_details[i].created_at, dateformat"yyyy-mm-ddTHH:MM:SS\Z") < min_created_date
                                min_created_date = DateTime(pr_details[i].created_at, dateformat"yyyy-mm-ddTHH:MM:SS\Z")
                                mini = i
                            end
                        end

                        if !isnothing(min_created_date)
                            pr_num = pr_details[mini].number
                            DBInterface.execute(db, "INSERT INTO pull_request_build (bors_sha, pr, parent_sha, commit_date) VALUES ('$sha', $pr_num, '$parent_sha', $(artifact_row.date))")
                        else
                            println("Commit $sha has no PR")
                        end
                    else
                        println("Commit $sha has no PR")
                    end

                    artifact_id = artifact_row.id
                    next_artifact_id[] += 1

                    DBInterface.execute(db, "INSERT INTO artifact (id, name, date, type) VALUES ($(artifact_row.id), '$(artifact_row.name)', $(artifact_row.date), '$(artifact_row.type)')")
                else
                    artifact_id = artifact_query[1, "id"]
                end
            end

            group = BenchmarkTools.load(joinpath(data, file))[1]
            return_group_only && return group

            benchmark_data = rec_flatten_benchmarkgroup(group)

            for (benchmark_name, trial) in benchmark_data
                if sha ∉ processed_commits # get alloc and memory data, same for all files
                    for metric in (:allocs, :memory) # allocs is num of allocations, memory is in bytes
                        push_metric_to_pstat!(df, db, benchmark_name, string(metric), artifact_id, getfield(trial, metric), benchmark_to_pstat_series_id)
                    end
                end

                push_metric_to_pstat!(df, db, benchmark_name, primary_metric * "-wall-time", artifact_id, trial.time, benchmark_to_pstat_series_id)
                push_metric_to_pstat!(df, db, benchmark_name, primary_metric * "-gc-time", artifact_id, trial.gctime, benchmark_to_pstat_series_id)
            end

            if sha ∉ processed_commits
                push!(processed_commits, sha)
            end
        end
    end
end

function push_metric_to_pstat!(df::DataFrame, db::SQLite.DB, benchmark_name::String, metric::String, aid::Int64, value, benchmark_to_pstat_series_id)
    if !haskey(benchmark_to_pstat_series_id, (benchmark_name, metric))
        pstat_series_query = DBInterface.execute(db, "SELECT * FROM pstat_series ORDER BY id DESC LIMIT 1") |> DataFrame
        next_pid = 1 + pstat_series_query[1, "id"]

        temp_df = DataFrame(id=next_pid, crate=benchmark_name, profile="opt", scenario="full", backend="llvm", metric=metric)
        SQLite.load!(temp_df, db, "pstat_series")
        benchmark_to_pstat_series_id[(benchmark_name, metric)] = next_pid
    end
    series_id = benchmark_to_pstat_series_id[(benchmark_name, metric)]

    pstat_row = (series=series_id, aid=aid, cid=0, value=Float64(value))
    push!(df, pstat_row)
end

function create_pstat_rows(series_id, aid, val)
    len =  length(val)
    DataFrame(series=series_id, aid=fill(aid, len), cid=fill(0, len), value=val)
end

get_sha(file) = split(file, '_')[1]
function create_artifact_row(path, file, id)
    commit_sha = get_sha(file)

    date = nothing
    kind = nothing
    parent_sha = nothing

    search_on_master = HTTP.get("https://api.github.com/search/commits?q=repo:JuliaLang/julia+hash:$commit_sha").body |> JSON3.read

    if search_on_master.total_count == 0 # commit not in master branch
        commit_details = HTTP.get("https://api.github.com/repos/JuliaLang/Julia/git/commits/$commit_sha").body |> JSON3.read # can remove /git/ not sure why it's there
        date = DateTime(commit_details.author.date, dateformat"yyyy-mm-ddTHH:MM:SS\Z") |> datetime2unix |> Int64
        kind = "try"
        parent_sha = commit_details.parents[1].sha # How do you deal with multiple parents? Presumably we want the one on master
    elseif search_on_master.total_count == 1
        @assert search_on_master.items[1].sha == commit_sha
        date = DateTime(ZonedDateTime(search_on_master.items[1].commit.author.date), UTC) |> datetime2unix |> Int64
        kind = "master"
        parent_sha = search_on_master.items[1].parents[1].sha
    else
        println("Commit: $commit_sha")
        display(search_on_master)
        error("Found too many commits")
    end

    (id=id, name=commit_sha, date=date, type=kind), parent_sha
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

function process_benchmarks(dir)
    db = SQLite.DB("julia.db")

    artifact_id_query = DBInterface.execute(db, "SELECT id FROM artifact ORDER BY id DESC LIMIT 1") |> DataFrame
    next_artifact_id = Ref{Int}((isempty(artifact_id_query) ? 0 : artifact_id_query[1, "id"]) + 1)

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
                process_benchmark_archive!(pstat_df, joinpath(root, file), next_artifact_id, db, benchmark_to_pstat_series_id)
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

function auto_load(month=lpad(month(now()), 2, '0'), year=year(now()))
    process_benchmarks("/home/rag/Documents/Code/NanosoldierReports/benchmark/by_date/$year-$month")
    # for dir in filter(isdir, readdir("/home/rag/Documents/Code/NanosoldierReports/benchmark/by_hash/", join=true))
    #     process_benchmarks(dir)
    # end
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

using LibGit2
function fix_dates()
    db = SQLite.DB("julia.db")
    artifacts_table = DBInterface.execute(db, "SELECT * FROM artifact") |> DataFrame

    mktempdir() do dir
        repo = LibGit2.clone("https://github.com/JuliaLang/julia.git", dir)
        for (i, row) in pairs(eachrow(artifacts_table))
            commit = LibGit2.GitCommit(repo, row.name)
            commit_date = LibGit2.author(commit).time
            artifacts_table[i, "date"] = commit_date
        end
    end

    DBInterface.execute(db, "DELETE FROM artifact")
    artifacts_table |> SQLite.load!(db, "artifact")
end

function add_pr_nums()
    db = SQLite.DB("julia.db")
    artifacts = DBInterface.execute(db, "SELECT * FROM artifact") |> DataFrame
    pr_df = DataFrame()

    for row in eachrow(artifacts)
        if row["type"] == "master"
            sha = row["name"]
            pr_details = HTTP.get("https://api.github.com/repos/JuliaLang/Julia/commits/$sha/pulls", headers= ["Authorization" => "Bearer secret"]).body |> JSON3.read
            if !isempty(pr_details) && haskey(pr_details[1], :number)
                pr_num = pr_details[1].number
                push!(pr_df, (bors_sha = sha, pr = pr_num, parent_sha="", exclude=missing, complete=missing, runs=missing, include=missing, commit_date=missing, requested=missing))
                # DBInterface.execute(db, "INSERT INTO pull_request_build (bors_sha, pr) VALUES ('$sha', $pr_num)")
            else
                println("Commit $sha has no PR")
            end
        else
            # Doesn't really work due to force pushes I think, e.g. https://github.com/JuliaLang/julia/commit/4ff1f007974a4ea1d89e636d8feed83723bbb779 has no pr
            sha = row["name"]
            pr_details = HTTP.get("https://api.github.com/repos/JuliaLang/Julia/commits/$sha/pulls", headers= ["Authorization" => "Bearer secret"]).body |> JSON3.read
            if !isempty(pr_details)
                mini = 0
                min_created_date = nothing
                for i in eachindex(pr_details)
                    if isnothing(min_created_date) || DateTime(pr_details[i].created_at, dateformat"yyyy-mm-ddTHH:MM:SS\Z") < min_created_date
                        min_created_date = DateTime(pr_details[i].created_at, dateformat"yyyy-mm-ddTHH:MM:SS\Z")
                        mini = i
                    end
                end

                pr_num = pr_details[mini].number

                commit_details = HTTP.get("https://api.github.com/repos/JuliaLang/Julia/git/commits/$sha").body |> JSON3.read # can remove /git/ not sure why it's there
                date = DateTime(commit_details.author.date, dateformat"yyyy-mm-ddTHH:MM:SS\Z") |> datetime2unix |> Int64
                parent_sha = commit_details.parents[1].sha # How do you deal with multiple parents? Presumably we want the one on master

                push!(pr_df, (bors_sha=sha, pr=pr_num, parent_sha=parent_sha, exclude=missing, complete=missing, runs=missing, include=missing, commit_date=date, requested=missing))
                # DBInterface.execute(db, "INSERT INTO pull_request_build (bors_sha, pr, parent_sha, commit_date) VALUES ('$sha', $pr_num, '$parent_sha', $(artifact_row.date))")
            else
                println("Commit $sha has no PR")
            end
        end
    end

    return pr_df
    pr_df |> SQLite.load!(db, "pull_request_build")
end
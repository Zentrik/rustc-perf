using Pkg
Pkg.activate(@__DIR__)
using LibGit2, Dates
include("upload_nanosoldier_to_db.jl")
include("buildkite_logs.jl")

const sleep_time = Dates.Minute(5)
const db_path = "/media/rag/NVME/Code/rustc-perf-db/julia.db"

# Taken from PProf.jl
const proc = Ref{Union{Base.Process,Nothing}}(nothing)
function start_server()
    if !isnothing(proc[])
        error("Server already running")
    end
    proc[] = open(pipeline(`$(joinpath(@__DIR__, "prod_site")) $db_path`, stdout=stdout), read=false)
end
function kill_server()
    if !isnothing(proc[])
        kill(proc[])
        proc[] = nothing
    end
end

function main()
    nanosoldier_dir = joinpath(@__DIR__, "..", "NanosoldierReports")
    repo = LibGit2.GitRepo(nanosoldier_dir)

    julia_dir = joinpath(@__DIR__, "..", "julia-rustc-perf")
    julia_repo = LibGit2.GitRepo(julia_dir)

    start_server()
    atexit(kill_server)

    while true
        fetch_time = now(UTC)
        sleep(1) # little buffer to make sure fetch_time <= mtime(dir) is true
        changed = false

        julia_fetched = false
        julia_old_head = string(LibGit2.head_oid(julia_repo))
        try
            LibGit2.fetch(julia_repo)
            LibGit2.merge!(julia_repo, fastforward=true)
            julia_fetched = true
        catch err
            println("Error: $err") # Sometimes fetch fails
        end

        if julia_fetched
            shas = LibGit2.with(LibGit2.GitRevWalker(julia_repo)) do walker
                LibGit2.map((oid, julia_repo) -> string(oid), walker)
            end
            idx = findfirst(x -> x == julia_old_head, shas)
            shas = reverse(shas[1:(idx-1)])

            artifact_size_df, pstat_df = process_logs(db_path, shas, julia_repo)
            changed |= !isempty(artifact_size_df)
        end

        fetched = false
        try
            LibGit2.fetch(repo)
            LibGit2.merge!(repo, fastforward=true)
            fetched = true
        catch err
            println("Error: $err") # Sometimes fetch fails
        end

        if fetched
            for rel_dir in ("by_date", "by_hash")
                for benchmark_dir in readdir(joinpath(nanosoldier_dir, "benchmark", rel_dir), join=true)
                    if isdir(benchmark_dir) && fetch_time <= unix2datetime(mtime(benchmark_dir))
                        changed = true
                        kill_server()
                        println("$(benchmark_dir) changed")
                        process_benchmarks(benchmark_dir, db_path)
                    end
                end
            end
        end

        if changed
            start_server()
        end
        sleep(sleep_time)
    end
end

function process_logs(db_path, shas, julia_repo)
    db = SQLite.DB(db_path)
    artifact_id_query = DBInterface.execute(db, "SELECT id FROM artifact ORDER BY id DESC LIMIT 1") |> DataFrame
    next_artifact_id = Ref{Int}((isempty(artifact_id_query) ? 0 : artifact_id_query[1, "id"]) + 1)

    artifact_size_df = DataFrame()
    pstat_df = DataFrame()
    for sha in shas
        artifact_query = DBInterface.execute(db, "SELECT * FROM artifact WHERE name='$(sha)' LIMIT 1") |> DataFrame
        artifact_id = if !isempty(artifact_query)
            artifact_query[1, "id"]
        else
            date = LibGit2.author(LibGit2.GitCommit(julia_repo, sha)).time
            artifact_row = (id=next_artifact_id[], name=sha, date=date, type="master")

            next_artifact_id[] += 1

            DBInterface.execute(db, "INSERT INTO artifact (id, name, date, type) VALUES ($(artifact_row.id), '$(artifact_row.name)', $(artifact_row.date), '$(artifact_row.type)')")
            artifact_row.id
        end

        process_commit!(artifact_size_df, pstat_df, artifact_id, sha, "master", identity)
        # for row in eachrow(pstat_df)
        #     metric = row.series in ("minor", "major") ? "$(row.series)-pagefaults" : row.series
        #     push_metric_to_pstat!(df, db, "init", "median-$metric", artifact_row.id, median(row.value), benchmark_to_pstat_series_id)
        # end
    end

    if !isempty(artifact_size_df)
        SQLite.load!(artifact_size_df, db, "artifact_size")
    end
    return artifact_size_df, pstat_df
end

isinteractive() || main()

# julia_old_head = "b0b7a859ed5bfa69ff368045982f87e50ef0ee32"
# julia_dir = joinpath(@__DIR__, "..", "julia-rustc-perf")
# julia_repo = LibGit2.GitRepo(julia_dir)
# shas = LibGit2.with(LibGit2.GitRevWalker(julia_repo)) do walker
#     LibGit2.map((oid, julia_repo) -> string(oid), walker)
# end
# idx = findfirst(x -> x == julia_old_head, shas)
# shas = reverse(shas[1:(idx-1)])
# process_logs(db_path, shas, julia_repo)
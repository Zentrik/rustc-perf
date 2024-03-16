using Pkg
Pkg.activate(@__DIR__)
using LibGit2, Dates
include("upload_nanosoldier_to_db.jl")

const sleep_time = Dates.Minute(5)

# Taken from PProf.jl
const proc = Ref{Union{Base.Process,Nothing}}(nothing)
function start_server()
    if !isnothing(proc[])
        error("Server already running")
    end
    proc[] = open(pipeline(`$(joinpath(@__DIR__, "prod_site")) julia.db`, stdout=stdout), read=false)
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

    start_server()
    atexit(kill_server)

    while true
        now = Dates.now()
        sleep(1) # little buffer to make sure now <= mtime(dir) is true

        LibGit2.fetch(repo)
        LibGit2.merge!(repo, fastforward=true)

        changed = false
        for rel_dir in ("by_date", "by_hash")
            for benchmark_dir in readdir(joinpath(nanosoldier_dir, "benchmark", rel_dir), join=true)
                if isdir(benchmark_dir) && now <= unix2datetime(mtime(joinpath(benchmark_dir, benchmark_dir)))
                    changed = true
                    kill_server()
                    println("$(joinpath(rel_dir, benchmark_dir)) changed")
                    process_benchmarks(benchmark_dir)
                end
            end
        end

        if changed
            start_server()
        end
        sleep(sleep_time)
    end
end

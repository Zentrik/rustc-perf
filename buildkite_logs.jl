using HTTP, JSON3, DataFrames

function get_logs(page)
    url = "https://buildkite.com/julialang/julia-master/builds?branch=master&page=$page"

    r = HTTP.get(url)
    html = String(r.body)

    build_urls = map(x -> x.match, eachmatch(r"julialang/julia-\w*/builds/(\d+)", html)) |> unique

    sha_to_logs = Dict{String,String}()

    for build_url in build_urls
        details_url = "https://buildkite.com/" * build_url * ".json"
        details_json = HTTP.get(details_url).body |> JSON3.read
        idx = findfirst(x -> x.name == ":linux: build x86_64-linux-gnu", details_json.jobs)

        logs_url = "https://buildkite.com/" * details_json.jobs[idx].base_path * "/raw_log"

        log = HTTP.get(logs_url).body |> String
        sha = details_json.commit_id

        sha_to_logs[sha] = log
    end

    return sha_to_logs
end

function get_log(sha, branch, commit_time)
    url = "https://buildkite.com/julialang/julia-$branch/builds?commit=$sha"

    r = HTTP.get(url)
    html = String(r.body)

    build_num_matches = match(r"href=\"/julialang/julia-master/builds/(\d+)\"", html)
    if build_num_matches == nothing
        return :no_ci
    end
    build_num = build_num_matches.captures[1]

    details_url = "https://buildkite.com/julialang/julia-$branch/builds/$build_num.json"
    details_json = HTTP.get(details_url).body |> JSON3.read
    idx = findfirst(x -> x.name == ":linux: build x86_64-linux-gnu", details_json.jobs)

    idx_launch_builds = findfirst(x -> x.name == "Launch build jobs",details_json.jobs)

    try
        if details_json.jobs[idx_launch_builds].exit_status isa Integer && details_json.jobs[idx_launch_builds].exit_status != 0 && isnothing(idx)
            return :no_ci
        end
        if details_json.jobs[idx].exit_status isa Integer && details_json.jobs[idx].exit_status != 0
            return :no_ci
        end
        if details_json.jobs[idx].state != "finished"
            return :not_finished
        end
    catch err
        println("Error processing build status for $sha")
        println("Error: $err")

        if time() - commit_time > 60 * 60 * 6 # If no log after 6 hours, assumed failed
            println("Build not finished after 6 hours at $(time()) for $sha commited at $commit_time, skipping")
            return :no_ci
        end
        return :not_finished
    end

    logs_url = "https://buildkite.com/" * details_json.jobs[idx].base_path * "/raw_log"

    return HTTP.get(logs_url).body |> String
end

@views function parse_log!(timings, binary_sizes, log)
    binary_size_start_idx = (findfirst("==> ./julia binary sizes", log) |> last) + 1
    binary_size_end_idx = (findfirst("==> ./julia launch speedtest", log) |> first) - 1

    binaries = eachmatch(r"/([a-zA-Z\.\-0-9]+)[[:blank:]]+:", log[binary_size_start_idx:binary_size_end_idx]) |> collect
    for (i, binary) in pairs(binaries)
        binary_name = binary.captures[1]
        libLLVM_matcher = match(r"libLLVM-\d+jl\.([a-zA-Z]+)", binary_name)
        if libLLVM_matcher != nothing
            binary_name = "libLLVM.$(libLLVM_matcher.captures[1])"
        end
        binary_sizes[binary_name] = Dict{String,UInt64}()

        next_binary = i == lastindex(binaries) ? binary_size_end_idx : binaries[i+1].match.offset + binary_size_start_idx

        for m in eachmatch(r"([a-zA-Z\.]+)[[:blank:]]*(\d+)", log[binary_size_start_idx+binary.match.offset:next_binary])
            binary_sizes[binary_name][m.captures[1]] = parse(UInt64, m.captures[2])
        end
    end

    speedtest_start_idx = (findfirst("==> ./julia launch speedtest", log) |> last) + 1
    speedtest_end_idx = (findfirst("Create build artifacts", log) |> first) - 1

    for m in eachmatch(r"[^\[]([\d\.]+)[[:blank:]]*([a-zA-Z]+)", log[speedtest_start_idx:speedtest_end_idx])
        if !haskey(timings, m.captures[2])
            timings[m.captures[2]] = Float64[]
        end
        push!(timings[m.captures[2]], parse(Float64, m.captures[1]))
    end
end

function parse_logs!(sha_to_timings, sha_to_binary_sizes, sha_to_logs)
    for (sha, log) in sha_to_logs
        parse_log!(sha_to_timings[sha], sha_to_binary_sizes[sha], log)
    end
end

function process_commit!(artifact_size_df, pstat_df, aid, sha, branch, init_metric_to_series_id, commit_time)
    log = get_log(sha, branch, commit_time)
    if log isa Symbol
        return log
    end

    timings = Dict{String,Vector{Float64}}()
    binary_sizes = Dict{String,Dict{String,UInt64}}()
    parse_log!(timings, binary_sizes, log)

    for (binary, sizes) in binary_sizes
        # SQLite doesn't support UInt64? so we convert to Int
        # https://github.com/JuliaDatabases/SQLite.jl/issues/313
        push!(artifact_size_df, (aid=aid, component=binary, size=Int(sizes["Total"])))
    end

    for (timing_series, time) in timings
        push!(pstat_df, (aid=aid, series=init_metric_to_series_id(timing_series), value=time))
    end
end

# @testset "Processing Commit" begin
#     artifact_size_df = DataFrame()
#     pstat_df = DataFrame()

#     aid = 23
#     sha = "0a491e00a1f38b814ca173bd7d9bffeadde65738"
#     branch = "master"

#     process_commit!(artifact_size_df, pstat_df, aid, sha, branch, identity)
#     @test artifact_size_df == DataFrame(aid=[aid, aid, aid], component=["julia", "sys.so", "libjulia.so"], size=[9478, 197751633, 199055])
#     @test pstat_df == DataFrame(aid=[aid, aid, aid, aid, aid, aid, aid, aid, aid, aid, aid], series=["elapsed", "system", "user", "outputs", "minor", "swaps", "maxresident", "major", "avgtext", "avgdata", "inputs"], value=[[0.13, 0.13, 0.14], [0.07, 0.06, 0.07], [0.26, 0.28, 0.28], [0.0, 0.0, 0.0], [20532.0, 20531.0, 20598.0], [0.0, 0.0, 0.0], [180252.0, 180360.0, 180400.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]])
# end

# # sha_to_logs = get_binaryurl(1)
# # sha_to_timings = Dict{String,Dict{String,Vector{Float64}}}(sha => Dict{String,Vector{Float64}}() for sha in keys(sha_to_logs))
# # sha_to_binary_sizes = Dict{String,Dict{String,Dict{String,UInt64}}}(sha => Dict{String,Dict{String,UInt64}}() for sha in keys(sha_to_logs))

# # parse_logs!(sha_to_timings, sha_to_binary_sizes, sha_to_logs)

# # # for (sha, timing_series) in sha_to_timings, (name, timings) in timing_series
# # #     println(name, "\n ", sum(timings) / length(timings))
# # # end

# # for (sha, binary_sizes) in sha_to_binary_sizes
# #     println(sha, ": ", binary_sizes["sys.so"]["Total"] |> Int)
# # end

# using Test
# @testset "parsing logs" begin
#     sha_to_logs_test = JSON3.read("sha_to_logs_test.json", Dict{String,String})
#     sha_to_timings = Dict{String,Dict{String,Vector{Float64}}}(sha => Dict{String,Vector{Float64}}() for sha in keys(sha_to_logs_test))
#     sha_to_binary_sizes = Dict{String,Dict{String,Dict{String,UInt64}}}(sha => Dict{String,Dict{String,UInt64}}() for sha in keys(sha_to_logs_test))

#     parse_logs!(sha_to_timings, sha_to_binary_sizes, sha_to_logs_test)

#     sha_to_timings_test = JSON3.read("sha_to_timings_test.json", Dict{String,Dict{String,Vector{Float64}}})
#     sha_to_binary_sizes_test = JSON3.read("sha_to_binary_sizes_test.json", Dict{String,Dict{String,Dict{String,UInt64}}})

#     @test sha_to_timings == sha_to_timings_test
#     @test sha_to_binary_sizes == sha_to_binary_sizes_test
# end
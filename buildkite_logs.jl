using HTTP, JSON3

function get_binaryurl(page)
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

function parse_logs!(sha_to_timings, sha_to_binary_sizes, sha_to_logs)
    @views for (sha, log) in sha_to_logs
        binary_size_start_idx = (findfirst("==> ./julia binary sizes", log) |> last) + 1
        binary_size_end_idx = (findfirst("==> ./julia launch speedtest", log) |> first) - 1

        binaries = eachmatch(r"/([a-zA-Z.]+)[[:blank:]]+:", log[binary_size_start_idx:binary_size_end_idx]) |> collect
        for (i, binary) in pairs(binaries)
            binary_name = binary.captures[1]
            sha_to_binary_sizes[sha][binary_name] = Dict{String,UInt64}()

            next_binary = i == lastindex(binaries) ? binary_size_end_idx : binaries[i+1].match.offset + binary_size_start_idx

            for m in eachmatch(r"([a-zA-Z.]+)[[:blank:]]*(\d+)", log[binary_size_start_idx+binary.match.offset:next_binary])
                sha_to_binary_sizes[sha][binary_name][m.captures[1]] = parse(UInt64, m.captures[2])
            end
        end

        speedtest_start_idx = (findfirst("==> ./julia launch speedtest", log) |> last) + 1
        speedtest_end_idx = (findfirst("Create build artifacts", log) |> first) - 1

        for m in eachmatch(r"[^\[]([\d.]+)[[:blank:]]*([a-zA-Z]+)", log[speedtest_start_idx:speedtest_end_idx])
            if !haskey(sha_to_timings[sha], m.captures[2])
                sha_to_timings[sha][m.captures[2]] = Float64[]
            end
            push!(sha_to_timings[sha][m.captures[2]], parse(Float64, m.captures[1]))
        end
    end
end

sha_to_logs = get_binaryurl(1)
sha_to_timings = Dict{String,Dict{String,Vector{Float64}}}(sha => Dict{String,Vector{Float64}}() for sha in keys(sha_to_logs))
sha_to_binary_sizes = Dict{String,Dict{String,Dict{String,UInt64}}}(sha => Dict{String,Dict{String,UInt64}}() for sha in keys(sha_to_logs))

parse_logs!(sha_to_timings, sha_to_binary_sizes, sha_to_logs)

# for (sha, timing_series) in sha_to_timings, (name, timings) in timing_series
#     println(name, "\n ", sum(timings) / length(timings))
# end

for (sha, binary_sizes) in sha_to_binary_sizes
    println(sha, ": ", binary_sizes["sys.so"]["Total"] |> Int)
end

@testset "parsing logs" begin
    sha_to_logs_test = JSON3.read("sha_to_logs_test.json", Dict{String,String})
    sha_to_timings = Dict{String,Dict{String,Vector{Float64}}}(sha => Dict{String,Vector{Float64}}() for sha in keys(sha_to_logs))
    sha_to_binary_sizes = Dict{String,Dict{String,Dict{String,UInt64}}}(sha => Dict{String,Dict{String,UInt64}}() for sha in keys(sha_to_logs))

    parse_logs!(sha_to_timings, sha_to_binary_sizes, sha_to_logs_test)

    sha_to_timings_test = JSON3.read("sha_to_timings_test.json", Dict{String,Dict{String,Vector{Float64}}})
    sha_to_binary_sizes_test = JSON3.read("sha_to_binary_sizes_test.json", Dict{String,Dict{String,Dict{String,UInt64}}})

    @test sha_to_timings == sha_to_timings_test
    @test sha_to_binary_sizes == sha_to_binary_sizes_test
end
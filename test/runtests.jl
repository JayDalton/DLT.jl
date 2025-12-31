using .DLT
using Test

function read_unique_app_ctx(file_name::AbstractString)
    store = Dict{AbstractString,AbstractString}()
    for (date, time, ecu, app, ctx, vrb, typ, nfo, noar, msg) in DLT.read_resumable(file_name)
        store[app] = ctx
    end
    store
end

function print_msg_log_type(file_name::AbstractString)
    for (date, time, ecu, app, ctx, vrb, typ, nfo, noar, msg) in DLT.read_resumable(file_name)
        if typ == "LOG" && app == "DE"
            println(date, " ", time, " ", ecu, " ", app, " ", ctx, " ", vrb, ": ", nfo)
        end
    end
end

function print_msg_by_channel(file_name::AbstractString)
    for (date, time, ecu, app, ctx, vrb, typ, nfo, noar, msg) in DLT.read_channel(file_name)
        if typ == "LOG" && app == "DE"
            println(date, " ", DLT.msg_content(noar, msg))
        end
    end
end

function print_msg_by_resumable(file_name::AbstractString)
    for (date, time, ecu, app, ctx, vrb, typ, nfo, noar, msg) in DLT.read_resumable(file_name)
        if typ == "LOG" && app == "DE"
            println(date, " ", DLT.msg_content(noar, msg))
        end
    end
end

@testset "DLT.jl" begin
    # Write your tests here.
    @test 0 == 0
end

test_file = "data/sample.dlt"
read_unique_app_ctx(test_file)
# print_msg_log_type(test_file)
# print_msg_by_channel(test_file)
# print_msg_by_resumable(test_file)

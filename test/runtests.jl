using UProbes
using Test

function get_lib(provider, name, args=())
    file, io = mktemp(@__DIR__)
    close(io)
    ptr = UProbes.emit_probe(provider, name, args; file = file)
    return ptr, file
end

function get_note(provider, name, args=())
    _, file = get_lib(provider, name, args)
    note = read(`readelf -n $file`, String)
    rm(file)
    return note
end

note = get_note(:julia, :test)
@test occursin("NT_STAPSDT", note)
@test occursin("Provider: julia", note)
@test occursin("Name: test", note)

note = get_note(:julia, :test, (Int64,))
@test occursin("Arguments: -8@", note)

note = get_note(:julia, :test, (UInt64,))
@test occursin("Arguments: 8@", note)

note = get_note(:julia, :test, (UInt8,))
@test occursin("Arguments: 1@", note)

function f(arg)
    if @query(:julia, :test, typeof(arg))
        @probe(:julia, :test, arg)
    end
end

f(1)
f(UInt64(1))
f(UInt8(1))

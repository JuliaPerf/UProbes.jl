using UProbes

f() = @probe(:julia, :test)

function main()
    while true
        f()
        ccall(:jl_breakpoint, Cvoid, ())
    end
end

main()

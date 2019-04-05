module UProbes

using LLVM
using LLVM.Interop

export @probe

# TODO:
# - Semaphore support

# Links:
# * https://lwn.net/Articles/753601/
# * systemtap-sdt-dev for dtrace util on Linux
# * GDB support https://sourceware.org/gdb/onlinedocs/gdb/Static-Probe-Points.html
# * Interesting bcc utils https://github.com/iovisor/bcc/pull/774
# * https://github.com/opendtrace/toolkit
# * bpftrace: https://github.com/iovisor/bpftrace/blob/master/docs/reference_guide.md
# * Both these tools create elf files dynamically
#   * https://github.com/chrisa/libusdt
#   * https://github.com/sthima/libstapsdt
# * https://cuviper.github.io/rust-libprobe/doc/src/probe/src/platform/systemtap.rs.html
# * https://sourceware.org/systemtap/man/stapprobes.3stap.html#lbAO (see `process.mark`)
# * https://sourceware.org/systemtap/wiki/AddingUserSpaceProbingToApps
# * https://sourceware.org/systemtap/wiki/UserSpaceProbeImplementation
# * https://sourceware.org/gdb/onlinedocs/gdb/Static-Probe-Points.html

macro probe(provider, name, args...)
    quote
        $emit_probeasm(Val($provider), Val($name), $(map(esc, args)...))
    end
end

@generated function emit_probeasm(::Val{provider}, ::Val{name}, args...) where {provider, name}
    @assert length(args) <= 12

    argstr = join((string("-", sizeof(args[i]), "@\$\$", i-1) for i in 1:length(args)), ' ')
    addr = string(".", sizeof(Int), "byte")

    # FIXME set semaphore address
    # 993:
    # ...
    # $addr 0 // semaphore address
    # maybe just
    #    $addr $(provider)_$(name)_semaphore
    # Need to create a GlobalVariable of that name in the module beforehand
    # `__extension__ extern unsigned short $(provider)_$(name)_semaphore __attribute__ ((unused)) __attribute__ ((section (".probes")))`
    # semaphore = GlobalVariable(mod, LLVM.Int16Type(ctx), "template_semaphore")
    # section!(semaphore, ".probes")
    # linkage!(semaphore, ...)

    asm = """
990:    nop
        .pushsection .note.stapsdt,"?","note"
        .balign 4
        .4byte 992f-991f, 994f-993f, 3
991:    .asciz "stapsdt"
992:    .balign 4
993:    $addr 990b
        $addr _.stapsdt.base
        $addr 0
        .asciz "$provider"
        .asciz "$name"
        .asciz "$argstr"
994:    .balign 4
        .popsection
.ifndef _.stapsdt.base
        .pushsection .stapsdt.base,"aG","progbits",.stapsdt.base,comdat
        .weak _.stapsdt.base
        .hidden _.stapsdt.base
_.stapsdt.base: .space 1
        .size _.stapsdt.base, 1
        .popsection
.endif
"""
    
    expr = quote
        @asmcall($asm, "", true, Nothing, Tuple{$(args...)}, args...)
        return nothing
    end
    expr
end

end # module

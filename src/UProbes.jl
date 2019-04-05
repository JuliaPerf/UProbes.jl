module UProbes

using LLVM
import Libdl

export @probe, @query

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
        $__probe(Val($provider), Val($name), $(map(esc, args)...))
    end
end

macro query(provider, name, types...)
    quote
        $__query(Val($provider), Val($name), Tuple{$(map(esc, args)...)})
    end
end

@generated function __probe(::Val{provider}, ::Val{name}, args...) where {provider, name}
    dlptr = cache_dl(provider, name, args)
    dlsym = Libdl.dlsym(dlptr, Symbol(join(("__uprobe", provider, name), "_")))
    quote
        ccall($dlsym, Nothing, ($(args...),), $((:(args[$i]) for i in 1:length(args))...))
    end
end

@generated function __probe(::Val{provider}, ::Val{name}, ::Tuple{args}) where {provider, name, args}
    dlptr = cache_dl(provider, name, args)
    dlsym = Libdl.dlsym(dlptr, Symbol(join((provider, name, "semaphore"), "_")))
    quote
        unsafe_load(convert(Ptr{UInt16}, $dlsym)) % Bool
    end
end

const __probes = Dict{Tuple{Symbol, Symbol, Tuple}, Ptr{Nothing}}()
function cache_dl(provider, name, args)
    key = (provider, name, args)
    if !haskey(__probes, key)
        dlptr = emit_probe(provider, name, args)
        __probes[key] = dlptr
        return dlptr
    end
    return __probes[key]
end

function emit_probe(provider::Symbol, name::Symbol, args::Tuple; file = tempname())
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
        $addr $(provider)_$(name)_semaphore
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

    ctx = LLVM.Interop.JuliaContext()
    mod = LLVM.Module("uprobe_$(provider)_$(name)", ctx)

    # Create semaphore variable
    semaphore = LLVM.GlobalVariable(mod, LLVM.Int16Type(ctx), "$(provider)_$(name)_semaphore")
    section!(semaphore, ".probes")
    linkage!(semaphore, LLVM.API.LLVMDLLExportLinkage)

    # create function that will do a call to nop assembly
    rettyp = convert(LLVMType, Nothing)
    argtyp = LLVMType[convert.(LLVMType, args)...]

    ft = LLVM.FunctionType(rettyp, argtyp)
    f = LLVM.Function(mod, string("__uprobe_", provider, "_", name), ft)
    linkage!(f, LLVM.API.LLVMDLLExportLinkage)

    inline_asm = InlineAsm(ft, asm, "", true)
    
    # generate IR
    Builder(ctx) do builder
        entry = BasicBlock(f, "entry", ctx)
        position!(builder, entry)

        val = call!(builder, inline_asm, collect(parameters(f)))
        ret!(builder)
    end

    triple = LLVM.triple()
    target = LLVM.Target(triple)
    objfile = tempname()
    TargetMachine(target, triple) do tm
        LLVM.emit(tm, mod, LLVM.API.LLVMObjectFile, objfile)
    end

    run(`ld -shared $objfile -o $file`)
    return Libdl.dlopen(file, Libdl.RTLD_LOCAL)
end

end #module


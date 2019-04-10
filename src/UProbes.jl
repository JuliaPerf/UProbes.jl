module UProbes

include("libusdt.jl")

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


if Sys.iswindows()
macro probe(args...)
    :()
end
macro quert(args...)
    :(false)
end

else

macro probe(provider, name, args...)
    quote
        $__probe(Val($provider), Val($name), $(map(esc, args)...))
    end
end

macro query(provider, name, types...)
    quote
        $__query(Val($provider), Val($name), Tuple{$(map(esc, types)...)})
    end
end

end # iswindows

@generated function __probe(::Val{provider}, ::Val{name}, args...) where {provider, name}
    dlptr = cache_dl(provider, name, args)
    dlsym = Libdl.dlsym(dlptr, Symbol(join(("__uprobe", provider, name), "_")))
    quote
        ccall($dlsym, Nothing, ($(args...),), $((:(args[$i]) for i in 1:length(args))...))
    end
end

# If a semaphore is associated with a probe, it will be of type unsigned short.
# A semaphore may gate invocations of a probe; it must be set to a non-zero
# value to guarantee that the probe will be hit. Semaphores are treated
# as a counter; your tool should increment the semaphore to enable it,
# and decrement the semaphore when finished.
@generated function __query(::Val{provider}, ::Val{name}, ::Type{args}) where {provider, name, args}
    args = (args.parameters..., )
    dlptr = cache_dl(provider, name, args)
    dlsym = Libdl.dlsym(dlptr, Symbol(join((provider, name, "semaphore"), "_")))
    quote
        unsafe_load(convert(Ptr{UInt16}, $dlsym)) !== UInt16(0)
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

argstring(::Type{T}, i) where T = error("UProbes.jl doesn't know how to handle $T") 
argstring(::Type{T}, i) where T <: Signed   = string("-", sizeof(T), raw"@$", i) 
argstring(::Type{T}, i) where T <: Unsigned = string(     sizeof(T), raw"@$", i)

if Sys.ARCH === :powerpc64le || Sys.ARCH === :ppc64le
    constraint(::Type{T}) where T <: Integer = "nZr"
else
    constraint(::Type{T}) where T <: Integer = "nor"
end

function emit_probe(provider::Symbol, name::Symbol, args::Tuple; file = tempname())
    @assert length(args) <= 12


    argstr = join((argstring(args[i], i-1) for i in 1:length(args)), ' ')
    constr = join((constraint(args[i])     for i in 1:length(args)), ',')
    addr = string(".", sizeof(Int), "byte")

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
    int16_t = LLVM.Int16Type(ctx)
    semaphore = LLVM.GlobalVariable(mod, int16_t, "$(provider)_$(name)_semaphore")
    section!(semaphore, ".probes")
    linkage!(semaphore, LLVM.API.LLVMExternalLinkage)
    initializer!(semaphore, ConstantInt(int16_t, 0))

    # GDB is rather unhappy if there is no `.data` section
    gdb_unhappy = LLVM.GlobalVariable(mod, int16_t, "are_you_happy_now")
    section!(gdb_unhappy, ".data")
    linkage!(gdb_unhappy, LLVM.API.LLVMExternalLinkage)
    initializer!(gdb_unhappy, ConstantInt(int16_t, 0))

    # create function that will do a call to nop assembly
    rettyp = convert(LLVMType, Nothing)
    argtyp = LLVMType[convert.(LLVMType, args)...]

    ft = LLVM.FunctionType(rettyp, argtyp)
    f = LLVM.Function(mod, string("__uprobe_", provider, "_", name), ft)
    linkage!(f, LLVM.API.LLVMExternalLinkage)

    inline_asm = InlineAsm(ft, asm, constr, true)
    
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
    TargetMachine(target, triple, "", "", LLVM.API.LLVMCodeGenLevelDefault, LLVM.API.LLVMRelocPIC) do tm
        LLVM.emit(tm, mod, LLVM.API.LLVMObjectFile, objfile)
    end

    run(`ld -shared $objfile -o $file`)
    return Libdl.dlopen(file, Libdl.RTLD_LOCAL)
end

end #module


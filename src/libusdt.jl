module LibUSDT

include(joinpath(@__DIR__, "..", "deps", "deps.jl"))

const ARG_MAX = 32

const ERROR_MALLOC = Cint(0)
const ERROR_VALLOC = Cint(1)
const ERROR_NOPROBES = Cint(2)
const ERROR_LOADDOF = Cint(3)
const ERROR_ALREADYENABLED = Cint(4)
const ERROR_UNLOADDOF = Cint(5)
const ERROR_DUP_PROBE = Cint(6)
const ERROR_REMOVE_PROBE = Cint(7)

struct Probe
    isenabled::Ptr{Cvoid} # int (*func)(void)
    probe::Ptr{Probe}
end

# Consider changing these `Ptr{}`s to `Ref{}`s
function is_enabled(probe)
    ccall((:usdt_is_enabled, libusdt), Cint, (Ptr{Probe},), probe)
end

function fire_probe(probe, args...)
    # void usdt_fire_probe(usdt_probe_t *probe, size_t argc, void **argv);
    ccall((:usdt_fire_probe, libusdt), Nothing, (Ptr{Probe}, Csize_t, Ptr{Ptr{Nothing}}), probe, length(args), collect(args))
end

struct ProbeDef
    name::Cstring
    func::Cstring
    argc::Csize_t
    types::NTuple{ARG_MAX, Cchar}
    probe::Ptr{Probe}
    next::Ptr{ProbeDef}
    refcnt::Cint
end

function create_probe(func, name, types::Vector{String})
    # usdt_probedef_t *usdt_create_probe(const char *func, const char *name,
    #                                    size_t argc, const char **types);
    ccall((:usdt_create_probe, libusdt), Ptr{ProbeDef}, (Cstring, Cstring, Csize_t, Ptr{Ptr{Cchar}}), func, name, length(types), types)
end

function release(probedef)
    ccall((:usdt_probe_release, libusdt), Cvoid, (Ptr{ProbeDef},), probedef)
end

struct Provider
    name::Cstring
    module_name::Cstring
    # ProbeDefs provide a linked-list like interface via pd.next
    probedefs::Ptr{ProbeDef}
    error::Cstring
    enabled::Cint
    file::Ptr{Cvoid}
end

function create_provider(name, module_name)
    # usdt_provider_t *usdt_create_provider(const char *name, const char *module);
    ccall((:usdt_create_provider, libusdt), Ptr{Provider}, (Cstring, Cstring), name, module_name)
end
function provider_add_probe(provider, probedef)
    # int usdt_provider_add_probe(usdt_provider_t *provider, usdt_probedef_t *probedef);
    ccall((:usdt_add_probe, libusdt), Cint, (Ptr{Provider}, Ptr{ProbeDef}), provider, probedef)
end
function provider_remove_probe(provider, probedef)
    # int usdt_provider_remove_probe(usdt_provider_t *provider, usdt_probedef_t *probedef);
    ccall((:usdt_remove_probe, libusdt), Cint, (Ptr{Provider}, Ptr{ProbeDef}), provider, probedef)
end
function provider_enable(provider)
    # int usdt_provider_enable(usdt_provider_t *provider);
    ccall((:usdt_provider_enable, libusdt), Nothing, (Ptr{Provider},), provider)
end
function provider_disable(provider)
    # int usdt_provider_disable(usdt_provider_t *provider);
    ccall((:usdt_provider_disable, libusdt), Nothing, (Ptr{Provider},), provider)
end
function provider_free(provider)
    # void usdt_provider_free(usdt_provider_t *provider);
    ccall((:usdt_provider_free, libusdt), Nothing, (Ptr{Provider},), provider)
end

# TODO: varargs...?
function error(provider, error, args...)
  ccall((:usdt_error, libusdt), Nothing, (Ptr{Provider}, Cint, Cstring...), provider, error, args...)
end
#    # void usdt_error(usdt_provider_t *provider, usdt_error_t error, ...);
#    ccall((:usdt_error, libusdt), Nothing, (Ptr{Provider}, Cint, typeof(args)...), provider, error, args...);
#end
function errstr(provider)
    # char *usdt_errstr(usdt_provider_t *provider);
    ccall((:usdt_errstr, libusdt), Cstring, (Ptr{Provider},), provider)
end

end

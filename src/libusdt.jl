module LibUSDT

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
    isenabled::Ptr{Nothing} # int (*func)(void)
    probe::Ptr{Nothing}
end

function is_enabled(probe)
    ccall((:usdt_is_enabled, libusdt), Cint, (Ref{Probe},), probe)
end

function fire_probe(probe, args...)
    # void usdt_fire_probe(usdt_probe_t *probe, size_t argc, void **argv);
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

function create_probe(func, name, types...)
    # usdt_probedef_t *usdt_create_probe(const char *func, const char *name,
    #                                    size_t argc, const char **types);
end

function release(probedef)
    ccall((:usdt_probe_release, libusdt), Cvoid, (Ptr{ProbeDef},), probedef)
end

struct _DofFile end

struct Provider
    name::Cstring
    module_name::Cstring
    # ProbeDefs provide a linked-list like interface via pd.next
    probedefs::Ptr{ProbeDef}
    error::Cstring
    enabled::Cint
    file::Ptr{_DofFile}
end

function create_provider(name, module_name)
    # usdt_provider_t *usdt_create_provider(const char *name, const char *module);
    #ccall((:usdt_create_provider, libusdt), Ptr{Provider}, (Cstring, Cstring), name, module_name)
end
# int usdt_provider_add_probe(usdt_provider_t *provider, usdt_probedef_t *probedef);
# int usdt_provider_remove_probe(usdt_provider_t *provider, usdt_probedef_t *probedef);
# int usdt_provider_enable(usdt_provider_t *provider);
# int usdt_provider_disable(usdt_provider_t *provider);
# void usdt_provider_free(usdt_provider_t *provider);
# 
# void usdt_error(usdt_provider_t *provider, usdt_error_t error, ...);
# char *usdt_errstr(usdt_provider_t *provider);

end

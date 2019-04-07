# UProbes.jl
*Lightweight instrumentation for dtrace/bpftrace for Julia programs*

UProbes.jl allows you to insert lightweight instrumentation points into your Julia
program and lets you enable that instrumentation during runtime with bpftrace on Linux
and dtrace elsewhere.

## Entrypoints

- `@query(provider, name, types...)`, query whether a probe is active.
- `@probe(provider, name, args...)`, place a probepoint and pass along args.

## Example

```julia
using UProbes

function f(arg)
    if @query(:julia, :test, typeof(arg))
        @probe(:julia, :test, arg)
    end
end

while true
    i = rand(Int64)
    f(i)
end
```

```bash
sudo bpftrace -p $PID -e "usdt:julia:test { @[comm] = count(); }"
Attaching 1 probe...
^C

@[8906]: 4071763
```

## Status
- Semaphore support works!
- Argument passing does not :/

## Also see
- https://github.com/cuviper/rust-libprobe

# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder

name = "libusdt"
version = v"2017.4.0"

# Collection of sources required to build libusdt
sources = [
    "https://github.com/chrisa/libusdt.git" =>
    "4d20408c00f1b6745eef857a2042f3271a78265d",

]

# Bash recipe for building across all platforms
script = raw"""
mkdir -p $WORKSPACE/destdir/lib
cd $WORKSPACE/srcdir/libusdt
make  CFLAGS="-g2 -fPIC"
$CC -fPIC -shared -o libusdt.$dlext -L. -Wl,-all_load -lusdt
cp libusdt.* $WORKSPACE/destdir/lib/

"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = [
    MacOS(:x86_64)
]

# The products that we will ensure are always built
products(prefix) = [
    LibraryProduct(prefix, "libusdt", :libusdt)
]

# Dependencies that must be installed before this package can be built
dependencies = [
    
]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies)


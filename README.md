# Setup
  - Clone the Prunt repo into a directory next to this one. 
  - install alr
  - run `alr with are` to install a dependency
  - make sure npm is installed
  - `alr build`
# System Dependencies (Ubuntu 24.04)
  - libudev-dev
  - libglfw3-dev

# Implementing from a language other than Ada
Ada seems interesting, but it's also very different and not so easy to hop into and be productive right away. We want to print NOW, right? So it'd be great to just write the implementation in a language we're familiar with. Luckily we can make Ada bindings for C functions without much effort. Pretty much every language can produce functions with the C calling convention.
    
    procedure Enable_Stepper_C (Stepper : Integer);
    pragma Import (C, Enable_Stepper_C, "enable_stepper");

This block instructs the compiler to expect the linker will find a C function named `enable_stepper`. Basically the same as `extern void enable_stepper(int);`

    procedure Enable_Stepper (Stepper : Stepper_Name) is
    begin
      Enable_Stepper_C (StepperToCInt(Stepper));
    end Enable_Stepper;

The second block wraps our C calling convention function in one with the Ada calling convention that Prunt expects. There's one more function happening in there, `StepperToCInt`, which explicitly converts the Ada enum type `Stepper` to the integer that our C function expects with a switch statement. You could also use `Stepper_Name'Pos` but I wanted to be explicit about which axis is which number.

## Linking Setup
Alire can actually compile C directly making this part superfluous, but I don't want to be constrained to C, so instead we'll link against a static library. If you do want to have Alire deal with all of this, get rid of the linker section in prunt_simulator.gpr and move the `callbacks.c` file into the `src` folder, next to `prunt_simulator.adb`. That should be it.
We specify which static library to link against in `prunt_simulator.gpr`.

Here's the entry to use the zig implementation.

    package Linker is 
      for Default_Switches ("Ada") use ("-Lzig_impl/zig-out/lib", "-lcallbacks");
    end Linker;
This syntax is pretty much the same as you'd use with GCC, `-Lblahblah` is the directory the archive is in, `-lblah` is the library to link against (without the lib on the front, so the actual file linked against is `libcallbacks.a`). The entry for the C version is in the file, but commented out. 

# Building
## Zig
The zig impl is written assuming compiler 0.14.0. For a debug build `zig build` from the zig_impl directory should do it, for a release build `zig build -Doptimize=ReleaseFast`. `build.zig` is written to include both `compiler-rt` and `ubsan-rt` in the library, these should be unused for a release fast build, but are used in a debug build. Comment out those lines in `build.zig` if their presence causes a problem.
## C
    gcc -c callbacks.c -o callbacks.o
    ar rcs libcallbacks.a callbacks.o

# Running with plotted output
This is broken right now, the C callbacks don't print in the same format.

    stdbuf -oL -eL ./bin/prunt_simulator | stdbuf -oL -eL awk '/DATA OUTPUT,/ {print > "/dev/stdout"} !/DATA OUTPUT,/ {print > "/dev/stderr"}' | stdbuf -oL -eL python3 ./continuous_plot.py

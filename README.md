# Kiber Uni Project

Vivado university project for Kyber/NTT hardware design work.

## Repository Layout

- `Design Sources/` - Verilog/SystemVerilog design modules, memory initialization data, Vivado block designs, and IP metadata.
- `Constraints/` - Vivado XDC constraint files.
- `Simulation Sources/` - Testbenches and simulation-only sources.
- `Utility Sources/` - Vivado utility/imported implementation artifacts.
- `Reports/` - Timing, utilization, and clock information reports.
- `Vivado Project/` - Original Vivado project file.

## Main Design Files

- `ntt_3ram_core.v`
- `ntt_3ram_datapath.v`
- `ntt_3ram_fsm.v`
- `ntt_2stage_4butterfly.v`
- `butterfly.v`
- `K2RED.v`
- `KRED.v`
- `twiddle_rom_k2red.v`
- `RAM1.v`

## Notes

Generated Vivado output directories such as runs, cache, simulation output, and logs are intentionally excluded from Git.

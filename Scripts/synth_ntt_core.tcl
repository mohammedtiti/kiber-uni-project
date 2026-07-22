# Out-of-context synthesis and timing sanity check for ntt_3ram_core.
# Vivado 2023.2 on Windows can mis-resolve Desktop known-folder paths.  The
# optional environment variable makes batch runs unambiguous; pwd is the
# portable fallback when that quirk is not present.
if {[info exists ::env(KYBER_PROJECT_ROOT)]} {
  set root_dir $::env(KYBER_PROJECT_ROOT)
} else {
  set root_dir [pwd]
}
set out_dir [file join $root_dir kiber_test.runs kyber_core_synth]

# Avoid a Vivado 2023.2 Windows helper-process cleanup failure observed when
# the repository is inside the Desktop known folder.
set_param general.maxThreads 1

set rtl_files [list \
  [file join $root_dir "Design Sources" K2RED.v] \
  [file join $root_dir "Design Sources" RAM1.v] \
  [file join $root_dir "Design Sources" butterfly.v] \
  [file join $root_dir "Design Sources" ntt_2stage_4butterfly.v] \
  [file join $root_dir "Design Sources" ntt_2x2_schedule.v] \
  [file join $root_dir "Design Sources" kyber_modmul.v] \
  [file join $root_dir "Design Sources" twiddle_rom_k2red.v] \
  [file join $root_dir "Design Sources" ntt_3ram_datapath.v] \
  [file join $root_dir "Design Sources" ntt_3ram_fsm.v] \
  [file join $root_dir "Design Sources" ntt_3ram_core.v]]
read_verilog $rtl_files

synth_design -top ntt_3ram_core -part xc7a35tcpg236-1 -flatten_hierarchy rebuilt
create_clock -name core_clk -period 10.000 [get_ports clk]
opt_design

report_utilization -hierarchical -file [file join $out_dir utilization_hierarchical.rpt]
report_timing_summary -delay_type max -max_paths 20 \
  -file [file join $out_dir timing_summary_100mhz.rpt]
write_checkpoint -force [file join $out_dir ntt_3ram_core_post_synth.dcp]
write_verilog -force -mode funcsim \
  [file join $out_dir ntt_3ram_core_post_synth_funcsim.v]

set timing_paths [get_timing_paths -max_paths 1]
if {[llength $timing_paths] > 0} {
  set worst_slack [get_property SLACK [lindex $timing_paths 0]]
  puts "KYBER_CORE_WORST_SLACK_NS=$worst_slack"
}
puts "KYBER_CORE_SYNTHESIS_COMPLETE"

# Re-time the post-synthesis checkpoint at the Cmod A7 board's 12 MHz clock.
if {[info exists ::env(KYBER_PROJECT_ROOT)]} {
  set root_dir $::env(KYBER_PROJECT_ROOT)
} else {
  set root_dir [pwd]
}
set out_dir [file join $root_dir kiber_test.runs kyber_core_synth]
open_checkpoint [file join $out_dir ntt_3ram_core_post_synth.dcp]
create_clock -name core_clk -period 83.333 [get_ports clk]
report_timing_summary -delay_type max -max_paths 20 \
  -file [file join $out_dir timing_summary_12mhz.rpt]
set paths [get_timing_paths -max_paths 1]
if {[llength $paths] > 0} {
  puts "KYBER_CORE_12MHZ_WORST_SLACK_NS=[get_property SLACK [lindex $paths 0]]"
}
puts "KYBER_CORE_12MHZ_TIMING_COMPLETE"

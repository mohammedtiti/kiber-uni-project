set part_name xc7a35tcpg236-1
set out_dir timing_ntt_core
set clk_period_ns 4.000

file mkdir $out_dir

read_verilog -sv kiber_test.srcs/sources_1/new/RAM1.v
read_verilog -sv kiber_test.srcs/sources_1/new/twiddle_rom_k2red.v
read_verilog -sv kiber_test.srcs/sources_1/imports/project/K2RED.v
read_verilog -sv kiber_test.srcs/sources_1/imports/project/butterfly.v
read_verilog -sv kiber_test.srcs/sources_1/new/ntt_2stage_4butterfly.v
read_verilog -sv kiber_test.srcs/sources_1/new/ntt_3ram_datapath.v
read_verilog -sv kiber_test.srcs/sources_1/new/ntt_3ram_fsm.v
read_verilog -sv kiber_test.srcs/sources_1/new/ntt_3ram_core.v

set synth_status [catch {
  synth_design -top ntt_3ram_core -part $part_name -mode out_of_context \
    -generic TW_MEMFILE=kiber_test.srcs/sources_1/imports/Desktop/twiddle_k2red.mem
} synth_result]
if {$synth_status != 0} {
  puts "WARNING: synth_design returned an error: $synth_result"
  if {[llength [get_designs]] == 0} {
    error $synth_result
  }
  puts "WARNING: continuing because a synthesized design is loaded."
}

create_clock -name clk -period $clk_period_ns [get_ports clk]

opt_design
place_design
phys_opt_design
route_design
phys_opt_design

report_timing_summary -delay_type max -max_paths 10 -file $out_dir/timing_summary_4ns.rpt
report_utilization -file $out_dir/utilization.rpt

set worst_path [lindex [get_timing_paths -delay_type max -max_paths 1] 0]
set wns [get_property SLACK $worst_path]
set estimated_period_ns [expr {$clk_period_ns - $wns}]
set estimated_fmax_mhz [expr {1000.0 / $estimated_period_ns}]

set fp [open "$out_dir/fmax_summary.txt" w]
puts $fp "part=$part_name"
puts $fp "constraint_ns=$clk_period_ns"
puts $fp "wns_ns=$wns"
puts $fp "estimated_period_ns=$estimated_period_ns"
puts $fp "estimated_fmax_mhz=$estimated_fmax_mhz"
puts $fp "startpoint=[get_property STARTPOINT_PIN $worst_path]"
puts $fp "endpoint=[get_property ENDPOINT_PIN $worst_path]"
close $fp

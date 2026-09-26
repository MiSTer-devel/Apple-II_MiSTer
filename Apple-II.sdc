# gamma_corr captures Apple II pixel data only on the ce_pix rising edge. In
# the fastest mode, consecutive captures are four 57.273 MHz video clocks apart.
set apple2_pixel_clock [get_clocks {*|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}]
set apple2_gamma_capture_regs [get_registers -nowarn {
	*video_mixer|gamma|R_in*
	*video_mixer|gamma|G_in*
	*video_mixer|gamma|B_in*
	*video_mixer|gamma|hs
	*video_mixer|gamma|vs
	*video_mixer|gamma|hb
	*video_mixer|gamma|vb
	*video_mixer|gamma|gamma_index*
	*video_mixer|gamma|gamma_curve_rtl_0|*portb_address_reg*
}]

if {[get_collection_size $apple2_pixel_clock] != 1} {
	post_message -type error "Apple II pixel clock constraint matched [get_collection_size $apple2_pixel_clock] clocks"
}
if {[get_collection_size $apple2_gamma_capture_regs] == 0} {
	post_message -type error "Apple II gamma capture constraint matched no registers"
}

set_multicycle_path -from $apple2_pixel_clock -to $apple2_gamma_capture_regs -setup 4
set_multicycle_path -from $apple2_pixel_clock -to $apple2_gamma_capture_regs -hold 3
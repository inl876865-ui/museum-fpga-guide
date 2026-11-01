# Soft placement hint for flash preflight logic; existing hard bounds are unchanged.
set pfe_cells [get_cells -hier {sd_card_bmp_m0/u_volume_store/u_service/u_preflight/*}]
if {[llength $pfe_cells] != 285} {error "Expected exactly 285 current preflight cells"}
create_bound flash_preflight_timer_cluster -mode soft -width 12 -height 16 -origin {14 28}
add_cells_to_bound -bound flash_preflight_timer_cluster -cells $pfe_cells

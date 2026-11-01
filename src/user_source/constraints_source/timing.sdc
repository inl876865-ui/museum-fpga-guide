
# ============================================================
# merged_top_tf_hdmi_audio.sdc
# 用于：TF 图片轮播 + HDMI(视频+音频) 整合工程
#
# 合并原则：
# 1) 保留 top.sdc 里的系统主时钟与 derive_clocks
# 2) 把 timing(2).sdc 里的 pixel/serial 时钟改成整合工程实际名字
# 3) 保留 hdmi_5x_clk；第四讲音频复用 video_clk
# 4) 不再对内部 net 直接 create_clock，避免和 derive_clocks 重复
# ============================================================

# ------------------------------------------------------------
# 1. 板级输入主时钟
#    你的原 top.sdc 里 clk=50MHz，所以这里仍然用 20ns
# ------------------------------------------------------------
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

# ------------------------------------------------------------
# 2. 自动推导 PLL 输出时钟
# ------------------------------------------------------------
derive_clocks

# ------------------------------------------------------------
# 3. 给关键 PLL 输出命名
#    下面这些路径是按你当前工程实例名写的：
#      sys_pll      -> sys_pll_m0
#      video_pll    -> video_pll_m0
#
#    如果综合后实例路径略有不同，就按 Timing Analyzer 里的实际 pin 路径改。
# ------------------------------------------------------------
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sd_pll_m0/pll_inst.clkc[0]}]
# Lesson 6 SDRAM timing reference: sys_pll clk1/clk2 are 40 MHz;
# clk2 is the phase-shifted sampling clock used by the SDRAM hard IP.
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]

# ------------------------------------------------------------
# 4. video_clk 与 hdmi_5x_clk 同时运行，存在像素到串行器的数据路径。
# 移除原 exclusive 分组，按同源相关时钟分析，不屏蔽真实跨频路径。
# ------------------------------------------------------------

# ------------------------------------------------------------
# 5. 第四讲 PCM、音频包和视频编码均使用 video_clk，无 I2S 跨域。
#    已移除 audio_mclk 的重命名和异步时钟分组。
# ------------------------------------------------------------

# ------------------------------------------------------------
# 6. 可选：如果你的 frame_read_write 内部异步 FIFO 已经完全处理好了跨域，
#    且报告里总出现 video_clk / sd_card_clk / ext_mem_clk 之间的大量伪违例，
#    可以打开下面这组异步分组。
#
#    建议先不要开，先看报告；
#    只有确认这些跨域都只经过 FIFO / 同步器时再开。
# ------------------------------------------------------------
# set_clock_groups -asynchronous \
#     -group [get_clocks {sd_card_clk}] \
#     -group [get_clocks {ext_mem_clk}] \
#     -group [get_clocks {video_clk}] \
#     -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 7. 其余 Input/Output delay 先保持空白
#    你当前两个原始 sdc 也都没有写这部分。
# ------------------------------------------------------------

# 第六讲：异步复位仅在同步器边界豁免，输出到业务的释放路径继续计时。
# 仅豁免同步器的异步输入，不豁免同步器输出到业务寄存器的复位时序。
set_false_path -from [get_ports {rst_n}]
set_false_path -from [get_regs {power_on_done}] -to [get_regs {u_pll_startup_guard/lock_sync[*] u_pll_startup_guard/lock_count[*] u_pll_startup_guard/lock_qualified}]
set_false_path -from [get_regs {power_on_done u_pll_startup_guard/lock_qualified}] -to [get_regs {reset_sd_sync[*] reset_mem_sync[*] reset_video_sync[*] reset_serial_sync[*] reset_ui_sync[*]}]
# 只豁免初始化标志同步器的第一级；后续级和业务启动条件继续计时。
set_false_path -from [get_clocks {ext_mem_clk}] -to [get_regs {sdram_init_sync[0]}]

# SW4 is asynchronous; only the first synchronizer stage is exempted.
set_false_path -from [get_ports {thumbnail_switch}] -to [get_regs {sd_card_bmp_m0/g_screen_menu_keys$u_player_keys/main_sw_sync0[2]}]

# Static sleep indication: only the first synchronizer stage is asynchronous.
set_false_path -to [get_regs {clock_sleep_sd_sync[0]}]

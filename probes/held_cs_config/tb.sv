// Cycle-level probe of spi_host_fsm: pin timing (SCK, CSB) and the per-byte
// launch/shift/sample/read events, for the parent revision and the port.
// Plusargs (first command A / second command B):
//   CPHA, CPHA2, CLKDIV, CLKDIV2, SPEED, SPEED2 (0 std, 1 dual, 2 quad),
//   DIR, DIR2 (0 dummy, 1 read, 2 write, 3 bidir), LEN, LEN2, TRAIL, LEAD, IDLE,
//   MODE, DELAY, TRACE.
//   MODE 0: A on CS0 with CSAAT=1; B on CS1 DELAY cycles after the FSM is idle.
//   MODE 1: A on CS0 with CSAAT=0 (reference trail); B on CS1 after idle.
//   MODE 2: A on CS0 with CSAAT=1; B on CS0 (same CS) DELAY cycles after idle.
//   MODE 3: A on CS0 with CSAAT=1; B on CS1 presented right after A is accepted.
//   MODE 4: A on CS0 with CSAAT=1; B on CS0 presented right after A is accepted.
module tb;
  import spi_host_cmd_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  command_t   command;
  logic       command_valid = 1'b0;
  logic       command_ready;
  logic       sck;
  logic [1:0] csb;
  logic [3:0] sd_en;
  logic       last_read, last_write, wr_en, rd_en, sample_en, shift_en, full_cyc;
  logic [1:0] speed;
  logic       rx_stall, tx_stall, active;

`ifdef DUT_HEAD
  fsm_head #(.NumCS(2)) u_dut (
`else
  fsm_main #(.NumCS(2)) u_dut (
`endif
    .clk_i(clk), .rst_ni(rst_n), .en_i(1'b1),
    .command_i(command), .command_valid_i(command_valid), .command_ready_o(command_ready),
    .sck_o(sck), .csb_o(csb), .sd_en_o(sd_en), .last_read_o(last_read), .last_write_o(last_write),
    .wr_en_o(wr_en), .sr_wr_ready_i(1'b1), .rd_en_o(rd_en), .sr_rd_ready_i(1'b1),
    .sample_en_o(sample_en), .shift_en_o(shift_en), .speed_o(speed), .full_cyc_o(full_cyc),
    .rx_stall_o(rx_stall), .tx_stall_o(tx_stall), .active_o(active), .sw_rst_i(1'b0));

  int cpha_arg, cpha2_arg, clkdiv_arg, clkdiv2_arg, speed_arg, speed2_arg, dir_arg, dir2_arg;
  int trail_arg, lead_arg, idle_arg, len_arg, len2_arg, mode_arg, delay_arg, trace_arg;
  int cyc = 0;
  bit started = 1'b0;
  always @(posedge clk) cyc <= cyc + 1;

  // Per-CS window monitor (pins), plus whole-run event totals.
  int fall_cyc [2], first_sck [2], last_sck [2], n_edges [2], min_half [2];
  int tot_wr = 0, tot_shift = 0, tot_rd = 0, tot_accept = 0, tot_last_rd = 0, tot_last_wr = 0;
  int csb_high_start = -1;
  logic sck_prev;
  logic [1:0] csb_prev;
  logic [7:0] trace_prev;
  initial begin
    sck_prev = 1'b0;
    csb_prev = 2'b11;
    trace_prev = '0;
  end
  always @(posedge clk) begin
    if (started) begin
      tot_wr      += int'(wr_en);
      tot_shift   += int'(shift_en);
      tot_rd      += int'(rd_en);
      tot_accept  += int'(command_valid && command_ready);
      tot_last_rd += int'(last_read);
      tot_last_wr += int'(last_write);
      for (int idx_cs = 0; idx_cs < 2; idx_cs++) begin
        if (csb_prev[idx_cs] && !csb[idx_cs]) begin
          if (&csb_prev && csb_high_start >= 0) begin
            $display("CSB all-high gap before CS%0d = %0d", idx_cs, cyc - csb_high_start);
          end
          fall_cyc[idx_cs]  = cyc;
          first_sck[idx_cs] = -1;
          last_sck[idx_cs]  = -1;
          n_edges[idx_cs]   = 0;
          min_half[idx_cs]  = 1 << 30;
        end
        if (!csb[idx_cs] && sck != sck_prev) begin
          if (first_sck[idx_cs] < 0) begin
            first_sck[idx_cs] = cyc;
          end else if (cyc - last_sck[idx_cs] < min_half[idx_cs]) begin
            min_half[idx_cs] = cyc - last_sck[idx_cs];
          end
          last_sck[idx_cs] = cyc;
          n_edges[idx_cs]++;
        end
        if (!csb_prev[idx_cs] && csb[idx_cs]) begin
          $display("CS%0d lead=%0d trail=%0d edges=%0d min_half=%0d", idx_cs,
                   first_sck[idx_cs] - fall_cyc[idx_cs], cyc - last_sck[idx_cs], n_edges[idx_cs],
                   min_half[idx_cs]);
        end
      end
      if (!(&csb_prev) && (&csb)) begin
        csb_high_start = cyc;
      end
      if (trace_arg != 0) begin
        if ({sck, csb, wr_en, shift_en, sample_en, rd_en, u_dut.cmd_wr_en_q} != trace_prev ||
            wr_en || shift_en || rd_en) begin
          $display("t=%0d st=%0d sck=%b csb=%b wr=%b sh=%b samp=%b rd=%b cmd_wr_q=%b sd_en=%b bit=%0d byte0=%0d byte1=%0d",
                   cyc, u_dut.state_q, sck, csb, wr_en, shift_en, sample_en, rd_en, u_dut.cmd_wr_en_q,
                   sd_en, u_dut.bit_cntr_q, u_dut.byte_cntr_cpha0_q, u_dut.byte_cntr_cpha1_q);
        end
        trace_prev = {sck, csb, wr_en, shift_en, sample_en, rd_en, u_dut.cmd_wr_en_q};
      end
    end
    sck_prev <= sck;
    csb_prev <= csb;
  end

  task automatic present(input int cs, input bit csaat, input int cpha_val, input int clkdiv_val,
                         input int speed_val, input int dir_val, input int len_val);
    @(negedge clk);
    command = '0;
    command.csid                = cs[0];
    command.segment.speed       = 2'(speed_val);
    command.segment.cmd_wr_en   = dir_val[1];
    command.segment.cmd_rd_en   = dir_val[0];
    command.segment.len         = 24'(len_val);
    command.segment.csaat       = csaat;
    command.configopts.clkdiv   = 16'(clkdiv_val);
    command.configopts.csnidle  = 4'(idle_arg);
    command.configopts.csnlead  = 4'(lead_arg);
    command.configopts.csntrail = 4'(trail_arg);
    command.configopts.cpha     = cpha_val[0];
    command_valid = 1'b1;
  endtask

  task automatic wait_accept();
    do @(posedge clk); while (!command_ready);
    @(negedge clk);
    command_valid = 1'b0;
  endtask

  initial begin
    if (!$value$plusargs("CPHA=%d", cpha_arg))       cpha_arg = 0;
    if (!$value$plusargs("CPHA2=%d", cpha2_arg))     cpha2_arg = cpha_arg;
    if (!$value$plusargs("CLKDIV=%d", clkdiv_arg))   clkdiv_arg = 7;
    if (!$value$plusargs("CLKDIV2=%d", clkdiv2_arg)) clkdiv2_arg = clkdiv_arg;
    if (!$value$plusargs("SPEED=%d", speed_arg))     speed_arg = 0;
    if (!$value$plusargs("SPEED2=%d", speed2_arg))   speed2_arg = speed_arg;
    if (!$value$plusargs("DIR=%d", dir_arg))         dir_arg = 3;
    if (!$value$plusargs("DIR2=%d", dir2_arg))       dir2_arg = dir_arg;
    if (!$value$plusargs("TRAIL=%d", trail_arg))     trail_arg = 1;
    if (!$value$plusargs("LEAD=%d", lead_arg))       lead_arg = 1;
    if (!$value$plusargs("IDLE=%d", idle_arg))       idle_arg = 1;
    if (!$value$plusargs("LEN=%d", len_arg))         len_arg = 0;
    if (!$value$plusargs("LEN2=%d", len2_arg))       len2_arg = len_arg;
    if (!$value$plusargs("MODE=%d", mode_arg))       mode_arg = 0;
    if (!$value$plusargs("DELAY=%d", delay_arg))     delay_arg = 0;
    if (!$value$plusargs("TRACE=%d", trace_arg))     trace_arg = 0;
    command = '0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (3) @(negedge clk);
    started = 1'b1;
    present(0, mode_arg != 1, cpha_arg, clkdiv_arg, speed_arg, dir_arg, len_arg);
    wait_accept();
    if (mode_arg <= 2) begin
      // Wait until the FSM is idle again (Idle or IdleCSBActive).
      do @(posedge clk); while (active);
      repeat (delay_arg) @(posedge clk);
    end
    present((mode_arg == 2 || mode_arg == 4) ? 0 : 1, 1'b0, cpha2_arg, clkdiv2_arg, speed2_arg,
            dir2_arg, len2_arg);
    wait_accept();
    repeat (3000) @(posedge clk);
    $display("TOTAL accept=%0d wr_en=%0d shift_en=%0d rd_en=%0d last_read=%0d last_write=%0d",
             tot_accept, tot_wr, tot_shift, tot_rd, tot_last_rd, tot_last_wr);
    $finish;
  end
endmodule

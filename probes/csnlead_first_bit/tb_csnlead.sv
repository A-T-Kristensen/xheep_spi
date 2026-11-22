// First-bit sampling bench for the SPI host FSM and shift register, with a
// long chip-select lead time.
//
// Question: with CPHA=0 and FULLCYC=0, does the host sample the first bit at
// the first leading SCK edge, which ends the CSNLEAD lead time, or earlier,
// in the first WaitLead timeslice? A host that samples early reads the bit
// before a slow device has driven it.
//
// The bench runs one standard-speed read of two bytes through spi_host_fsm
// and spi_host_shift_register, and prints the two bytes that the host
// captured.
//
// Device model (CPOL=0): the device drives the bits of DeviceBytes, MSB first.
//   CPHA=0: bit 0 from FIRSTBIT clock cycles after the CSB fall, the next bit
//           at each falling SCK edge. Before FIRSTBIT cycles have passed, the
//           device drives the inverse of bit 0, so a sample taken earlier
//           changes the first byte.
//   CPHA=1: the next bit at each rising SCK edge. FIRSTBIT has no effect.
// The device sees an SCK edge one cycle after sck_o changes, registers the
// new bit one cycle later, and the bit then passes DELAY more registers, so
// the bit reaches sd_i[1] DELAY+2 clock cycles after the sck_o change.
// Before the first bit, after the last bit, and while CSB is high, the device
// drives the inverse of the neighbouring bit, so a sample one bit early or
// late, or after the CSB rise, changes a byte.
//
// Expected for a host that samples the first bit at the first leading SCK
// edge, CPHA=0: the bytes match while FIRSTBIT+DELAY+2 is less than the
// number of cycles from the CSB fall to that edge, and a larger FIRSTBIT
// gives MISMATCH (the negative control: the bench can fail).
//
// Plusargs: CPHA, FULLCYC, CLKDIV, DELAY, CSNLEAD, CSNTRAIL, FIRSTBIT.
// Prints one RESULT line, with the cycle count from the CSB fall to the
// first rising SCK edge.
`default_nettype none

module tb_csnlead;
import spi_host_cmd_pkg::*;

localparam logic [15:0] DeviceBytes   = 16'hA53C;  // asymmetric, no two bytes equal
localparam int          NumDeviceBits = 16;
localparam int          MaxDelay      = 64;
localparam int          MaxCsnField   = 15;        // CONFIGOPTS.CSNLEAD and CSNTRAIL are 4-bit fields
localparam int          RunCycles     = 4000;      // two bytes at CLKDIV 31 need about 1100

logic clk = 1'b0;
logic reset_n = 1'b0;
always #5 clk = ~clk;

command_t   command;
logic       command_valid = 1'b0;
logic       command_ready;
logic       sck;
logic [1:0] csb;
logic [3:0] sd_en;
logic       last_read;
logic       last_write;
logic       wr_en;
logic       rd_en;
logic       sample_en;
logic       shift_en;
logic       full_cyc;
logic       wr_ready;
logic       rd_ready;
logic [1:0] speed;
logic       rx_stall;
logic       tx_stall;
logic       active;
logic [7:0] rx_data;
logic       rx_valid;
logic       rx_last;
logic [3:0] sd_out;
logic [3:0] sd_in;

int cpha_arg;
int full_cyc_arg;
int clkdiv_arg;
int delay_arg;
int csnlead_arg;
int csntrail_arg;
int first_bit_arg;

int                  bit_index;              // bit the device drives now, -1 before the first
int                  cycles_since_csb_fall;
int                  first_sck_rise_cycles;  // -1 until the first rising SCK edge
logic                sck_prev;
logic                csb_prev;
logic                device_bit;
logic [MaxDelay-1:0] device_history;

int         num_received;
logic [7:0] received [2];

spi_host_fsm #(.NumCS(2)) u_fsm (
  .clk_i            (clk),
  .rst_ni           (reset_n),
  .en_i             (1'b1),
  .command_i        (command),
  .command_valid_i  (command_valid),
  .command_ready_o  (command_ready),
  .sck_o            (sck),
  .csb_o            (csb),
  .sd_en_o          (sd_en),
  .last_read_o      (last_read),
  .last_write_o     (last_write),
  .wr_en_o          (wr_en),
  .sr_wr_ready_i    (wr_ready),
  .rd_en_o          (rd_en),
  .sr_rd_ready_i    (rd_ready),
  .sample_en_o      (sample_en),
  .shift_en_o       (shift_en),
  .speed_o          (speed),
  .full_cyc_o       (full_cyc),
  .rx_stall_o       (rx_stall),
  .tx_stall_o       (tx_stall),
  .active_o         (active),
  .sw_rst_i         (1'b0)
);

spi_host_shift_register u_shift_reg (
  .clk_i        (clk),
  .rst_ni       (reset_n),
  .wr_en_i      (wr_en),
  .wr_ready_o   (wr_ready),
  .rd_en_i      (rd_en),
  .rd_ready_o   (rd_ready),
  .speed_i      (speed),
  .shift_en_i   (shift_en),
  .sample_en_i  (sample_en),
  .last_read_i  (last_read),
  .last_write_i (last_write),
  .full_cyc_i   (full_cyc),
  .tx_data_i    (8'h00),
  .tx_valid_i   (1'b0),
  .tx_ready_o   (),
  .tx_flush_o   (),
  .rx_data_o    (rx_data),
  .rx_valid_o   (rx_valid),
  .rx_ready_i   (1'b1),
  .rx_last_o    (rx_last),
  .sw_rst_i     (1'b0),
  .sd_o         (sd_out),
  .sd_i         (sd_in)
);

function automatic logic device_value(input int index, input int cycles_after_fall);
  logic value;
  if (index < 0) begin
    value = ~DeviceBytes[NumDeviceBits - 1];
  end else if (index >= NumDeviceBits) begin
    value = ~DeviceBytes[0];
  end else if (cpha_arg == 0 && index == 0 && cycles_after_fall < first_bit_arg) begin
    value = ~DeviceBytes[NumDeviceBits - 1];
  end else begin
    value = DeviceBytes[NumDeviceBits - 1 - index];
  end
  return value;
endfunction : device_value

// Device: CPOL=0, so a rising edge is the leading edge.
always @(posedge clk) begin
  sck_prev <= sck;
  csb_prev <= csb[0];
  if (csb_prev && !csb[0]) begin
    bit_index             <= (cpha_arg == 0) ? 0 : -1;
    cycles_since_csb_fall <= 0;
  end else begin
    if (!csb[0] && cycles_since_csb_fall < RunCycles) begin
      cycles_since_csb_fall <= cycles_since_csb_fall + 1;
    end
    if (!csb[0] && sck != sck_prev) begin
      if ((cpha_arg == 0 && !sck) || (cpha_arg == 1 && sck)) begin
        bit_index <= bit_index + 1;
      end
      if (sck && first_sck_rise_cycles < 0) begin
        first_sck_rise_cycles <= cycles_since_csb_fall;
      end
    end
  end
  device_bit     <= csb[0] ? ~DeviceBytes[0] : device_value(bit_index, cycles_since_csb_fall);
  device_history <= {device_history[MaxDelay-2:0], device_bit};
end

assign sd_in = {2'b00, device_history[delay_arg - 1], 1'b0};

always @(posedge clk) begin
  if (rx_valid) begin
    if (num_received < 2) begin
      received[num_received] <= rx_data;
    end
    num_received <= num_received + 1;
  end
end

initial begin
  if (!$value$plusargs("CPHA=%d", cpha_arg)) begin
    cpha_arg = 0;
  end
  if (!$value$plusargs("FULLCYC=%d", full_cyc_arg)) begin
    full_cyc_arg = 0;
  end
  if (!$value$plusargs("CLKDIV=%d", clkdiv_arg)) begin
    clkdiv_arg = 7;
  end
  if (!$value$plusargs("DELAY=%d", delay_arg)) begin
    delay_arg = 1;
  end
  if (!$value$plusargs("CSNLEAD=%d", csnlead_arg)) begin
    csnlead_arg = 1;
  end
  if (!$value$plusargs("CSNTRAIL=%d", csntrail_arg)) begin
    csntrail_arg = 1;
  end
  if (!$value$plusargs("FIRSTBIT=%d", first_bit_arg)) begin
    first_bit_arg = 0;
  end
  if (delay_arg < 1 || delay_arg > MaxDelay) begin
    $fatal(1, "DELAY must be 1 to %0d", MaxDelay);
  end
  if (csnlead_arg < 0 || csnlead_arg > MaxCsnField || csntrail_arg < 0 || csntrail_arg > MaxCsnField) begin
    $fatal(1, "CSNLEAD and CSNTRAIL must be 0 to %0d", MaxCsnField);
  end
  if (first_bit_arg < 0 || first_bit_arg >= RunCycles) begin
    $fatal(1, "FIRSTBIT must be 0 to %0d", RunCycles - 1);
  end
  bit_index             = -1;
  cycles_since_csb_fall = 0;
  first_sck_rise_cycles = -1;
  sck_prev              = 1'b0;
  csb_prev              = 1'b1;
  device_bit            = 1'b0;
  device_history        = '0;
  num_received          = 0;
  received[0]           = 8'h00;
  received[1]           = 8'h00;
  command               = '0;
  repeat (3) @(negedge clk);
  reset_n = 1'b1;
  repeat (3) @(negedge clk);
  command.csid                = '0;
  command.segment.speed       = 2'd0;
  command.segment.cmd_wr_en   = 1'b0;
  command.segment.cmd_rd_en   = 1'b1;
  command.segment.len         = 24'd1;  // length field is bytes minus one
  command.segment.csaat       = 1'b0;
  command.configopts.clkdiv   = 16'(clkdiv_arg);
  command.configopts.csnidle  = 4'd1;
  command.configopts.csnlead  = 4'(csnlead_arg);
  command.configopts.csntrail = 4'(csntrail_arg);
  command.configopts.full_cyc = full_cyc_arg[0];
  command.configopts.cpha     = cpha_arg[0];
  command.configopts.cpol     = 1'b0;
  command_valid = 1'b1;
  do begin
    @(posedge clk);
  end while (!command_ready);
  @(negedge clk);
  command_valid = 1'b0;
  repeat (RunCycles) @(posedge clk);
  $display("RESULT cpha=%0d fullcyc=%0d clkdiv=%0d csnlead=%0d csntrail=%0d firstbit=%0d bit_delay=%0d first_sck_rise=%0d bytes=%0d got=%02h%02h expected=%04h %s",
           cpha_arg, full_cyc_arg, clkdiv_arg, csnlead_arg, csntrail_arg, first_bit_arg, delay_arg + 2,
           first_sck_rise_cycles, num_received, received[0], received[1], DeviceBytes,
           (num_received == 2 && {received[0], received[1]} == DeviceBytes) ? "MATCH" : "MISMATCH");
  $finish;
end

endmodule : tb_csnlead

`default_nettype wire

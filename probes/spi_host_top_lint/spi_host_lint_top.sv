// Lint-only top that instantiates spi_host with the x-heep register bus types,
// as the x-heep peripheral subsystem does, so the full spi_host hierarchy
// elaborates with its shipped parameters (NumCS, depths and widths come from
// spi_host_reg_pkg).
`default_nettype none

module spi_host_lint_top
  import spi_host_reg_pkg::*;
(
  input  wire logic                                       clk,
  input  wire logic                                       reset_n,
  input  wire xheep_reg_pkg::xheep_reg_req_t              reg_req_in,
  output      xheep_reg_pkg::xheep_reg_rsp_t              reg_rsp_out,
  input  wire prim_alert_pkg::alert_rx_t [NumAlerts-1:0]  alert_rx_in,
  output      prim_alert_pkg::alert_tx_t [NumAlerts-1:0]  alert_tx_out,
  output      logic                                       sck_out,
  output      logic                                       sck_en_out,
  output      logic [NumCS-1:0]                           csb_out,
  output      logic [NumCS-1:0]                           csb_en_out,
  output      logic [3:0]                                 sd_out,
  output      logic [3:0]                                 sd_en_out,
  input  wire logic [3:0]                                 sd_in,
  input  wire spi_device_pkg::passthrough_req_t           passthrough_in,
  output      spi_device_pkg::passthrough_rsp_t           passthrough_out,
  output      logic                                       rx_valid_out,
  output      logic                                       tx_ready_out,
  output      spi_host_reg_pkg::spi_host_hw2reg_status_reg_t hw2reg_status_out,
  output      logic                                       intr_error_out,
  output      logic                                       intr_spi_event_out
);

spi_host #(
  .reg_req_t (xheep_reg_pkg::xheep_reg_req_t),
  .reg_rsp_t (xheep_reg_pkg::xheep_reg_rsp_t)
) u_spi_host (
  .clk_i            (clk),
  .rst_ni           (reset_n),
  .reg_req_i        (reg_req_in),
  .reg_rsp_o        (reg_rsp_out),
  .alert_rx_i       (alert_rx_in),
  .alert_tx_o       (alert_tx_out),
  .cio_sck_o        (sck_out),
  .cio_sck_en_o     (sck_en_out),
  .cio_csb_o        (csb_out),
  .cio_csb_en_o     (csb_en_out),
  .cio_sd_o         (sd_out),
  .cio_sd_en_o      (sd_en_out),
  .cio_sd_i         (sd_in),
  .passthrough_i    (passthrough_in),
  .passthrough_o    (passthrough_out),
  .rx_valid_o       (rx_valid_out),
  .tx_ready_o       (tx_ready_out),
  .hw2reg_status_o  (hw2reg_status_out),
  .intr_error_o     (intr_error_out),
  .intr_spi_event_o (intr_spi_event_out)
);

endmodule : spi_host_lint_top

`default_nettype wire

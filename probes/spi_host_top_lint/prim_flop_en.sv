// Lint-only stand-in for the prim_flop_en wrapper that x-heep's primgen step
// generates: it forwards to the generic implementation with the same
// parameters, so the SPI host state machine elaborates without the generator.
`default_nettype none

module prim_flop_en #(
  parameter int               Width      = 1,
  parameter logic [Width-1:0] ResetValue = 0
) (
  input  wire logic             clk_i,
  input  wire logic             rst_ni,
  input  wire logic             en_i,
  input  wire logic [Width-1:0] d_i,
  output      logic [Width-1:0] q_o
);

prim_generic_flop_en #(
  .Width      (Width),
  .ResetValue (ResetValue)
) u_prim_generic_flop_en (
  .clk_i  (clk_i),
  .rst_ni (rst_ni),
  .en_i   (en_i),
  .d_i    (d_i),
  .q_o    (q_o)
);

endmodule : prim_flop_en

`default_nettype wire

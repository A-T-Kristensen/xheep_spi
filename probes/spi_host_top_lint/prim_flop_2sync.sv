// Lint-only stand-in for the prim_flop_2sync wrapper that x-heep's primgen
// step generates: it forwards to the generic two-flop synchronizer with the
// same parameters.
`default_nettype none

module prim_flop_2sync #(
  parameter int               Width      = 16,
  parameter logic [Width-1:0] ResetValue = '0
) (
  input  wire logic             clk_i,
  input  wire logic             rst_ni,
  input  wire logic [Width-1:0] d_i,
  output      logic [Width-1:0] q_o
);

prim_generic_flop_2sync #(
  .Width      (Width),
  .ResetValue (ResetValue)
) u_prim_generic_flop_2sync (
  .clk_i  (clk_i),
  .rst_ni (rst_ni),
  .d_i    (d_i),
  .q_o    (q_o)
);

endmodule : prim_flop_2sync

`default_nettype wire

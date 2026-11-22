// Lint-only stand-in for the prim_buf wrapper that x-heep's primgen step
// generates: it forwards to the generic implementation with the same width.
`default_nettype none

module prim_buf #(
  parameter int Width = 1
) (
  input  wire logic [Width-1:0] in_i,
  output      logic [Width-1:0] out_o
);

prim_generic_buf #(
  .Width (Width)
) u_prim_generic_buf (
  .in_i  (in_i),
  .out_o (out_o)
);

endmodule : prim_buf

`default_nettype wire

// Bench stubs for the packages and the flop that spi_host_fsm uses from
// the x-heep and OpenTitan primitive libraries.
`default_nettype none

package prim_util_pkg;
  function automatic int vbits(input int value);
    return (value == 1) ? 1 : $clog2(value);
  endfunction : vbits
endpackage : prim_util_pkg

package spi_host_reg_pkg;
  parameter int NumCS = 2;
endpackage : spi_host_reg_pkg

module prim_flop_en (
  input  wire logic clk_i,
  input  wire logic rst_ni,
  input  wire logic en_i,
  input  wire logic d_i,
  output      logic q_o
);

always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    q_o <= 1'b0;
  end else if (en_i) begin
    q_o <= d_i;
  end
end

endmodule : prim_flop_en

`default_nettype wire

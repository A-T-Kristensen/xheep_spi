package prim_util_pkg;
  function automatic int vbits(int value);
    return (value == 1) ? 1 : $clog2(value);
  endfunction
endpackage

package spi_host_reg_pkg;
  parameter int NumCS = 2;
endpackage

module prim_flop_en (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic en_i,
  input  logic d_i,
  output logic q_o
);
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      q_o <= 1'b0;
    end else if (en_i) begin
      q_o <= d_i;
    end
  end
endmodule

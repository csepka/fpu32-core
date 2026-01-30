`timescale 1ns/1ps
module smoke_tb;
  // clock & reset
  logic clk = 0;
  logic reset = 1;
  always #5 clk = ~clk; // 100 MHz

  // DUT interface
  logic        operands_val;
  logic [31:0] operands_bits_A;
  logic [31:0] operands_bits_B;
  logic [1:0]  operands_sel;       // 00=add, 01=sub, 10=mul
  logic        operands_rdy;

  logic        result_val;
  logic [31:0] result_bits;
  logic        result_rdy = 1'b1;  // always ready

  integer wait_cycles;

  // DUT
  fpu_top dut (
    .clk(clk),
    .reset(reset),
    .operands_val(operands_val),
    .operands_bits_A(operands_bits_A),
    .operands_bits_B(operands_bits_B),
    .operands_sel(operands_sel),
    .operands_rdy(operands_rdy),
    .result_val(result_val),
    .result_bits(result_bits),
    .result_rdy(result_rdy)
  );

  // known IEEE-754 constants
  localparam [31:0] F32_1P0 = 32'h3F800000; // 1.0
  localparam [31:0] F32_2P0 = 32'h40000000; // 2.0

  // simple send (one-beat ready/valid)
  task automatic send(input [31:0] A, input [31:0] B, input [1:0] OP);
    @(posedge clk);
    while (!operands_rdy) @(posedge clk);
    operands_bits_A <= A;
    operands_bits_B <= B;
    operands_sel    <= OP;
    operands_val    <= 1'b1;
    @(posedge clk);
    operands_val    <= 1'b0;
  endtask

  initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, smoke_tb);
    $dumpvars(0, smoke_tb.dut);
    $dumpvars(0, smoke_tb.dut.u_add);

  end

  initial begin
    // init
    operands_val    = 1'b0;
    operands_bits_A = '0;
    operands_bits_B = '0;
    operands_sel    = 2'b00;

    // reset
    repeat (5) @(posedge clk);
    reset = 0;

    // 1.0 + 1.0 = 2.0
    send(F32_1P0, F32_1P0, 2'b00);

    // wait for result (with small timeout)
    wait_cycles = 0;
    while (!result_val) begin
      @(posedge clk);
      wait_cycles = wait_cycles + 1;
      if (wait_cycles > 1000) begin
        $display("TIMEOUT waiting for result");
        $fatal(1);
      end
    end

    if (result_bits === F32_2P0) begin
      $display("PASS: 1.0 + 1.0 = 2.0 (0x%h)", result_bits);
    end else begin
      $display("FAIL: got 0x%h, expected 0x%h", result_bits, F32_2P0);
      $fatal(1);
    end

    $finish;
  end
endmodule
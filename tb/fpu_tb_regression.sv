`timescale 1ns/1ps
module fpu_tb_regression;

  // ---------------- Clock & reset ----------------
  logic clk = 0;
  logic reset = 1;
  always #5 clk = ~clk; // 100 MHz

  // ---------------- DUT interface (ready/valid) ----------------
  logic        operands_val;
  logic [31:0] operands_bits_A;
  logic [31:0] operands_bits_B;
  logic [1:0]  operands_sel;   // 00=add, 01=sub, 10=mul
  logic        operands_rdy;

  logic        result_val;
  logic [31:0] result_bits;
  logic        result_rdy;

  // ---------------- Instantiate DUT ----------------
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

  // ---------------- Constants (IEEE-754 single) ----------------
  localparam [31:0] F32_0P0  = 32'h0000_0000;
  localparam [31:0] F32_1P0  = 32'h3F80_0000;
  localparam [31:0] F32_2P0  = 32'h4000_0000;
  localparam [31:0] F32_NEG1 = 32'hBF80_0000;
  localparam [31:0] F32_NEG2 = 32'hC000_0000;
  localparam [31:0] F32_1P5  = 32'h3FC0_0000;
  localparam [31:0] F32_2P5  = 32'h4020_0000;
  localparam [31:0] F32_1P25 = 32'h3FA0_0000;

  // ============================================================
  // Portable helpers (no $bitstoshortreal / $shortrealtobits)
  // ============================================================
  function automatic shortreal b2f(input logic [31:0] x);
    int  e = x[30:23];
    int  m = x[22:0];
    real s = x[31] ? -1.0 : 1.0;
    real frac, val;
    if (e == 8'hFF) begin
      if (m != 0) return shortreal'(0.0/0.0);        // NaN
      else        return shortreal'(s * (1.0/0.0));   // ±Inf
    end
    if (e == 8'h00) begin
      if (m == 0) return shortreal'(s * 0.0);        // ±0
      frac = m / 8388608.0;                          // 2^23
      val  = s * frac * (2.0 ** -126.0);             // subnormal
      return shortreal'(val);
    end
    frac = 1.0 + (m / 8388608.0);
    val  = s * frac * (2.0 ** (e - 127));            // normal
    return shortreal'(val);
  endfunction

  function automatic logic [31:0] f2b(input shortreal xs);
    int  sign, E, frac, e;
    real r, a, m, fscaled, rem;
    r    = real'(xs);
    if (r != r)          return 32'h7FC0_0000; // NaN
    if (r ==  1.0/0.0)   return 32'h7F80_0000; // +Inf
    if (r == -1.0/0.0)   return 32'hFF80_0000; // -Inf

    sign = (r < 0.0) ? 1 : 0;
    a    = (r < 0.0) ? -r : r;
    if (a == 0.0)        return {sign[0], 31'd0};    // ±0

    // Subnormal
    if (a < (2.0 ** -126.0)) begin
      if (a < (2.0 ** -149.0)) return {sign[0], 31'd0}; // underflow → 0
      fscaled = a * (2.0 ** 149.0);            // a * 2^149 in [1 .. 2^23)
      frac    = $rtoi($floor(fscaled));
      rem     = fscaled - frac;
      if (rem > 0.5)        frac = frac + 1;        // round-to-nearest-even
      else if (rem < 0.5)   /* keep */;
      else                  frac = (frac & 1) ? (frac + 1) : frac;
      if (frac >= (1<<23))  frac = (1<<23) - 1;     // clamp
      return {sign[0], 8'h00, frac[22:0]};
    end

    // Normalized: 1.0 <= m < 2.0
    e = 0; m = a;
    while (m >= 2.0) begin m = m / 2.0; e = e + 1; end
    while (m <  1.0) begin m = m * 2.0; e = e - 1; end

    fscaled = (m - 1.0) * 8388608.0;  // 2^23
    frac    = $rtoi($floor(fscaled));
    rem     = fscaled - frac;
    if (rem > 0.5)        frac = frac + 1;          // round-to-nearest-even
    else if (rem < 0.5)   /* keep */;
    else                  frac = (frac & 1) ? (frac + 1) : frac;

    if (frac == (1<<23)) begin
      frac = 0;
      e    = e + 1;
    end

    E = e + 127;
    if (E >= 255) return {sign[0], 8'hFF, 23'd0};   // overflow → Inf
    return {sign[0], E[7:0], frac[22:0]};
  endfunction

  // IEEE-aware equality (treat ±0 equal, NaN==NaN for test purposes)
  function automatic bit is_nan(input logic [31:0] x);
    return (x[30:23] == 8'hFF) && (x[22:0] != 0);
  endfunction
  function automatic bit is_zero_ign_sign(input logic [31:0] x);
    return (x[30:0] == 31'd0);
  endfunction
  function automatic bit equalish(input logic [31:0] got, exp);
    if (is_nan(got) && is_nan(exp)) return 1;
    if (is_zero_ign_sign(got) && is_zero_ign_sign(exp)) return 1;
    return (got === exp);
  endfunction

  // ---------------- Reference model ----------------
  function automatic logic [31:0] ref_model(input logic [31:0] A, input logic [31:0] B, input logic [1:0] OP);
    shortreal a = b2f(A);
    shortreal b = b2f(B);
    shortreal r;
    case (OP)
      2'b00: r = a + b;
      2'b01: r = a - b;
      2'b10: r = a * b;
      default: r = 0.0;
    endcase
    return f2b(r);
  endfunction

  // ---------------- Ready/valid helpers ----------------
  task automatic send(input logic [31:0] A, input logic [31:0] B, input logic [1:0] OP);
    @(posedge clk);
    while (!operands_rdy) @(posedge clk);
    operands_bits_A <= A;
    operands_bits_B <= B;
    operands_sel    <= OP;
    operands_val    <= 1'b1;
    @(posedge clk);
    operands_val    <= 1'b0;
  endtask

  task automatic recv(output logic [31:0] Z);
    @(posedge clk);
    while (!result_val) @(posedge clk);
    Z = result_bits;
  endtask

  // ---------------- Random normalized float generator ----------------
  function automatic logic [31:0] rand_norm_float();
    logic [31:0] rbits;
    rbits[31]    = $urandom_range(0,1);
    rbits[30:23] = $urandom_range(1,254);         // avoid denorm/Inf/NaN
    rbits[22:0]  = $urandom_range(0, 8388607);
    return rbits;
  endfunction

  // ---------------- Test harness state ----------------
  integer fails;
  integer i, k;                 // loop indices
  logic [31:0] got, exp;
  logic [31:0] A_rand, B_rand;
  logic [1:0]  OP_rand;

  // Run a single check (label via simple id)
  task automatic check_case_id(
    input integer id,
    input logic [31:0] A,
    input logic [31:0] B,
    input logic [1:0]  OP
  );
    exp = ref_model(A,B,OP);
    send(A,B,OP);
    recv(got);
    if (!equalish(got, exp)) begin
      $display("FAIL case%0d  A=%h  B=%h  OP=%0d  got=%h  exp=%h", id, A,B,OP,got,exp);
      fails = fails + 1;
    end else begin
      $display("PASS case%0d  A=%h  B=%h  OP=%0d  got=%h", id, A,B,OP,got);
    end
  endtask

  // ---------------- Waves ----------------
  initial begin
    $dumpfile("waves_regression.vcd");
    $dumpvars(0, fpu_tb_regression);
  end

  // ---------------- Main sequence ----------------
  initial begin
    // init
    operands_val    = 1'b0;
    operands_bits_A = '0;
    operands_bits_B = '0;
    operands_sel    = 2'b00;
    result_rdy      = 1'b1;
    fails           = 0;

    // reset
    repeat (5) @(posedge clk);
    reset = 0;

    // Directed sanity
    check_case_id(0, F32_1P0,  F32_1P0,  2'b00); // 1+1=2
    check_case_id(1, F32_2P5,  F32_1P25, 2'b01); // 2.5-1.25=1.25
    check_case_id(2, F32_1P5,  F32_NEG2, 2'b00); // 1.5+(-2)=-0.5
    check_case_id(3, F32_NEG1, F32_NEG1, 2'b10); // (-1)*(-1)=1
    check_case_id(4, F32_2P0,  F32_0P0,  2'b10); // x*0=0

    // ---- Back-to-back (safe order: send then recv each) ----
    exp = ref_model(F32_1P0, F32_1P0, 2'b00);   // 1+1=2
    send(F32_1P0, F32_1P0, 2'b00);
    recv(got);
    if (!equalish(got, exp)) begin
      $display("FAIL safe[0]: got=%h exp=%h", got, exp); fails = fails + 1;
    end else $display("PASS safe[0]: got=%h", got);

    exp = ref_model(F32_2P0, F32_1P0, 2'b01);   // 2-1=1
    send(F32_2P0, F32_1P0, 2'b01);
    recv(got);
    if (!equalish(got, exp)) begin
      $display("FAIL safe[1]: got=%h exp=%h", got, exp); fails = fails + 1;
    end else $display("PASS safe[1]: got=%h", got);

    exp = ref_model(F32_1P5, F32_2P0, 2'b10);   // 1.5*2=3.0
    send(F32_1P5, F32_2P0, 2'b10);
    recv(got);
    if (!equalish(got, exp)) begin
      $display("FAIL safe[2]: got=%h exp=%h", got, exp); fails = fails + 1;
    end else $display("PASS safe[2]: got=%h", got);

    // Randomized vectors (no fancy backpressure in this simple TB)
    for (i = 0; i < 100; i = i + 1) begin
      A_rand  = rand_norm_float();
      B_rand  = rand_norm_float();
      OP_rand = $urandom_range(0,2); // 0:add,1:sub,2:mul
      exp     = ref_model(A_rand, B_rand, OP_rand);
      send(A_rand, B_rand, OP_rand);
      recv(got);
      if (!equalish(got, exp)) begin
        $display("FAIL rand i=%0d  OP=%0d A=%h B=%h got=%h exp=%h", i, OP_rand, A_rand, B_rand, got, exp);
        fails = fails + 1;
      end
    end

    if (fails == 0) $display("ALL TESTS PASSED");
    else            $display("TOTAL FAILS = %0d", fails);
    $finish;
  end

endmodule
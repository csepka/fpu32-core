module fpu_top (
    input clk,
    input reset,

    input operands_val,
    input [31:0] operands_bits_A,
    input [31:0] operands_bits_B,
    input [1:0] operands_sel,
    output operands_rdy,

    output result_val,
    output [31:0] result_bits,
    input result_rdy

);

parameter S_IDLE = 0, S_SEND_A = 1, S_SEND_B = 2, S_WAIT_Z = 3;

reg[31:0] a_q, b_q;
reg [1:0] op_q;

reg operands_rdy_reg, result_val_reg;
reg [31:0] result_bits_reg;

assign operands_rdy = operands_rdy_reg;
assign result_val = result_val_reg;
assign result_bits = result_bits_reg;

wire use_mul = (op_q == 2'b10);

wire [31:0] add_b_data = (op_q == 2'b01) ? {~b_q[31], b_q[30:0]} : b_q;


// STB/ACK stuff
reg add_a_stb, add_b_stb, add_z_ack;
reg mul_a_stb, mul_b_stb, mul_z_ack;

wire add_a_ack, add_b_ack, add_z_stb;
wire mul_a_ack, mul_b_ack, mul_z_stb;

wire [31:0] add_z, mul_z;

reg [2:0] state;



always @(posedge clk) begin
    if (reset) begin
        state <= S_IDLE;
        operands_rdy_reg <= 1'b1;
        result_val_reg <= 1'b0;
        result_bits_reg <= 32'h0;
        a_q <= 32'h0;
        b_q <= 32'h0;
        op_q <= 2'b00;

        add_a_stb <= 1'b0;
        add_b_stb <= 1'b0;
        add_z_ack <= 1'b0;
        mul_a_stb <= 1'b0;
        mul_b_stb <= 1'b0;
        mul_z_ack <= 1'b0;
    end
    else begin
        result_val_reg <= 1'b0;
        case(state)
            S_IDLE: begin
                operands_rdy_reg <= 1'b1;

                add_a_stb <= 1'b0;
                add_b_stb <= 1'b0;
                add_z_ack <= 1'b0;
                mul_a_stb <= 1'b0;
                mul_b_stb <= 1'b0;
                mul_z_ack <= 1'b0;

                if (operands_val && operands_rdy_reg) begin
                    a_q <= operands_bits_A;
                    b_q <= operands_bits_B;
                    op_q <= operands_sel;
                    operands_rdy_reg <= 1'b0;
                    state <= S_SEND_A;
                end

            end

            S_SEND_A: begin
                if (use_mul) begin
                    // Drive MUL A until its ACK drops (handshake consumed)
                    mul_a_stb <= 1'b1;
                    if (!mul_a_ack) begin
                        mul_a_stb <= 1'b0;   // drop after handshake
                        state     <= S_SEND_B;
                    end
                end else begin
                    // Drive ADD A until its ACK drops (handshake consumed)
                    add_a_stb <= 1'b1;
                    if (!add_a_ack) begin
                        add_a_stb <= 1'b0;   // drop after handshake
                        state     <= S_SEND_B;
                    end
                end
            end

            S_SEND_B: begin
                if (use_mul) begin
                    // Drive MUL B until its ACK drops
                    mul_b_stb <= 1'b1;
                    if (!mul_b_ack) begin
                        mul_b_stb <= 1'b0;
                        state     <= S_WAIT_Z;
                    end
                end else begin
                    // Drive ADD B until its ACK drops
                    add_b_stb <= 1'b1;
                    if (!add_b_ack) begin
                        add_b_stb <= 1'b0;
                        state     <= S_WAIT_Z;
                    end
                end
            end
            S_WAIT_Z: begin
                if (!use_mul) begin
                    if (add_z_stb && result_rdy) begin
                        result_bits_reg <= add_z;
                        result_val_reg <= 1'b1;
                        add_z_ack <= 1'b1;
                        state <= S_IDLE;
                    end
                    else begin
                        add_z_ack <= 1'b0;
                    end
                end
                else begin
                    if (mul_z_stb && result_rdy) begin
                        result_bits_reg <= mul_z;
                        result_val_reg <= 1'b1;
                        mul_z_ack <= 1'b1;
                        state <= S_IDLE;
                    end
                    else begin
                        mul_z_ack <= 1'b0;
                    end
                end
            end
            default: state <= S_IDLE;
        endcase
    end
end



adder u_add(
    .clk(clk),
    .rst(reset),

    .input_a(a_q),
    .input_a_stb(add_a_stb),
    .input_a_ack(add_a_ack),

    .input_b(add_b_data),
    .input_b_stb(add_b_stb),
    .input_b_ack(add_b_ack),

    .output_z(add_z),
    .output_z_stb(add_z_stb),
    .output_z_ack(add_z_ack)
);

multiplier u_mult(
    .clk(clk),
    .rst(reset),

    .input_a(a_q),
    .input_a_stb(mul_a_stb),
    .input_a_ack(mul_a_ack),
    
    .input_b(b_q),
    .input_b_stb(mul_b_stb),
    .input_b_ack(mul_b_ack),

    .output_z(mul_z),
    .output_z_stb(mul_z_stb),
    .output_z_ack(mul_z_ack)
);

endmodule
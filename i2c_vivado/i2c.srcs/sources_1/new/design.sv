module i2c_master (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic [6:0] addr,
    input  logic rw,             // 0 = write, 1 = read
    input  logic [7:0] data_in,
    output logic [7:0] data_out,
    output logic done,

    inout  wire sda,
    output logic scl
);

    typedef enum logic [2:0] {
        IDLE, START, ADDR, DATA, STOP, DONE
    } state_t;

    state_t state;
    logic [3:0] bit_cnt;
    logic sda_out_en;
    logic sda_out;

    assign sda = sda_out_en ? sda_out : 1'bz;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            scl <= 1;
            done <= 0;
            bit_cnt <= 0;
            sda_out_en <= 0;
        end else begin
            case (state)

                IDLE: begin
                    done <= 0;
                    if (start) begin
                        state <= START;
                    end
                end

                START: begin
                    sda_out_en <= 1;
                    sda_out <= 0; // START condition
                    state <= ADDR;
                    bit_cnt <= 6;
                end

                ADDR: begin
                    scl <= ~scl;
                    if (scl) begin
                        sda_out <= addr[bit_cnt];
                        if (bit_cnt == 0)
                            state <= DATA;
                        else
                            bit_cnt <= bit_cnt - 1;
                    end
                end

                DATA: begin
                    scl <= ~scl;
                    if (scl) begin
                        sda_out <= data_in[bit_cnt];
                        if (bit_cnt == 0)
                            state <= STOP;
                        else
                            bit_cnt <= bit_cnt - 1;
                    end
                end

                STOP: begin
                    scl <= 1;
                    sda_out <= 1; // STOP condition
                    state <= DONE;
                end

                DONE: begin
                    done <= 1;
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule